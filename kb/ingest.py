#!/usr/bin/env python3
"""Fill the knowledge base the help agent answers from.

    python3 kb/ingest.py --source site --paths faq.html genai-testing-course.html
    python3 kb/ingest.py --source capstone --paths "RAG project/TripSage_RAG_02_Test_Plan.docx"
    python3 kb/ingest.py --source video --paths lesson-04.mp4 --module "Module 4"
    python3 kb/ingest.py --source site --paths faq.html --dry-run

Environment:
    SUPABASE_URL                  https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY     service role — the ingestion RPCs are revoked
                                  from anon and authenticated on purpose
    EMBED_PROVIDER                jina | gemini | hf   (default jina)
    EMBED_API_KEY                 the key for whichever that is
    GROQ_API_KEY                  only needed for --source video (Whisper)

Why this is a script and not an edge function: PDF and DOCX extraction wants
real libraries, Deno has poor ones, and ingestion is a thing you run when the
material changes rather than a thing that has to be online. Nothing about it
needs to live in the request path.

Why it is idempotent: the commonest way a knowledge base rots is the same
document present three times at three ages, with retrieval picking whichever it
likes. Documents are keyed on (source, external_ref) and chunks are replaced
wholesale, so running this twice changes nothing and running it after an edit
updates in place. The content hash means an unchanged document never spends
embedding quota twice.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

UA = "GenAITesting-kb-ingest/1.0 (+https://genaitesting.online)"

# Groq sits behind Cloudflare, which rejects clients that send no User-Agent
# using its own error — "error code: 1010" on HTTP 403, nothing to do with the
# key. Every call here sends one. See claude/qt-groq-403-diagnosis.md.
BASE_HEADERS = {"User-Agent": UA, "Accept": "application/json"}

TARGET_CHARS = 1400      # a chunk big enough to answer from, small enough to rank
OVERLAP_CHARS = 180      # so a sentence split across a boundary is still findable
EMBED_DIM = 768


# ---------------------------------------------------------------- extraction
def strip_html(html: str) -> list[tuple[str, str]]:
    """HTML to (heading, text) sections.

    Sectioning on headings rather than cutting every N characters is the single
    biggest quality difference in a corpus like this: a citation that says
    "Poisoning defences" is useful to a student and "chunk 37" is not. Script,
    style and nav are dropped — a page's navigation appearing in every chunk
    makes every chunk look similar to every other, which is how retrieval goes
    flat.
    """
    # <head> first: the title and twenty meta tags are not course content, and
    # left in they become the first chunk of every single page — so every page
    # starts with a chunk that looks like every other page's first chunk.
    html = re.sub(r"(?is)<head\b.*?</head>", " ", html)
    html = re.sub(r"(?is)<(script|style|nav|footer|svg)\b.*?</\1>", " ", html)
    html = re.sub(r"(?is)<!--.*?-->", " ", html)

    parts = re.split(r"(?is)<(h[1-4])\b[^>]*>(.*?)</\1>", html)
    sections: list[tuple[str, str]] = []

    def clean(s: str) -> str:
        s = re.sub(r"(?is)<br\s*/?>", "\n", s)
        s = re.sub(r"(?is)</(p|div|li|tr|section)>", "\n", s)
        s = re.sub(r"(?s)<[^>]+>", " ", s)
        s = (s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<")
              .replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'")
              .replace("&mdash;", "—").replace("&rsquo;", "'"))
        s = re.sub(r"[ \t]+", " ", s)
        s = re.sub(r"\n\s*\n\s*\n+", "\n\n", s)
        return s.strip()

    # A heading is a label, so it is collapsed to one line. Source HTML wraps
    # them freely, and a citation reading "AI and GenAI testing\n questions"
    # looks broken to a student even though the text is right.
    def one_line(s: str) -> str:
        return re.sub(r"\s+", " ", clean(s)).strip()

    lead = clean(parts[0]) if parts else ""
    if lead:
        sections.append(("", lead))
    for i in range(1, len(parts) - 1, 3):
        heading = one_line(parts[i + 1])
        body = clean(parts[i + 2]) if i + 2 < len(parts) else ""
        if body or heading:
            sections.append((heading, body))
    return sections


def extract_docx(path: str) -> list[tuple[str, str]]:
    """DOCX via python-docx, keeping Heading styles as section boundaries."""
    try:
        from docx import Document  # noqa: PLC0415
    except ImportError:
        sys.exit("python-docx is not installed: pip install python-docx --break-system-packages")
    doc = Document(path)
    sections, heading, buf = [], "", []
    for p in doc.paragraphs:
        text = (p.text or "").strip()
        if not text:
            continue
        if (p.style.name or "").startswith("Heading"):
            if buf:
                sections.append((heading, "\n".join(buf)))
                buf = []
            heading = text
        else:
            buf.append(text)
    for table in doc.tables:
        rows = [" | ".join((c.text or "").strip() for c in r.cells) for r in table.rows]
        rows = [r for r in rows if r.strip(" |")]
        if rows:
            buf.append("\n".join(rows))
    if buf:
        sections.append((heading, "\n".join(buf)))
    return sections


def extract_pdf(path: str) -> list[tuple[str, str]]:
    """PDF, one section per page.

    Per page rather than per heading because PDF has no heading structure to
    read — only text with coordinates. Guessing headings from font size is
    unreliable enough that a page number is the more honest citation.
    """
    try:
        import pdfplumber  # noqa: PLC0415
    except ImportError:
        sys.exit("pdfplumber is not installed: pip install pdfplumber --break-system-packages")
    out = []
    with pdfplumber.open(path) as pdf:
        for i, page in enumerate(pdf.pages, 1):
            text = (page.extract_text() or "").strip()
            if text:
                out.append((f"Page {i}", text))
    return out


def transcribe(path: str) -> list[tuple[str, str]]:
    """Video or audio through Groq's Whisper, which the free tier includes.

    Segments are grouped into roughly chunk-sized pieces carrying their start
    time, so a citation can be a link that starts playing at the right moment —
    which is the only form of video citation a student can actually act on.
    """
    key = os.environ.get("GROQ_API_KEY")
    if not key:
        sys.exit("GROQ_API_KEY is needed to transcribe video")

    boundary = "----kbingest" + hashlib.sha1(path.encode()).hexdigest()[:16]
    with open(path, "rb") as fh:
        payload = fh.read()
    name = os.path.basename(path)

    body = b""
    for field, value in (("model", "whisper-large-v3"),
                         ("response_format", "verbose_json"),
                         ("temperature", "0")):
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{field}\"\r\n\r\n"
                 f"{value}\r\n").encode()
    body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
             f"filename=\"{name}\"\r\nContent-Type: application/octet-stream\r\n\r\n").encode()
    body += payload + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/audio/transcriptions", data=body,
        headers={**BASE_HEADERS, "Authorization": f"Bearer {key}",
                 "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req, timeout=600) as res:
            data = json.loads(res.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"Groq Whisper refused this ({e.code}). Its own words: {e.read()[:400]!r}")

    segments = data.get("segments") or []
    if not segments:
        return [("", (data.get("text") or "").strip())]

    out, buf, start = [], [], None
    for seg in segments:
        if start is None:
            start = int(seg.get("start", 0))
        buf.append((seg.get("text") or "").strip())
        if sum(len(x) for x in buf) >= TARGET_CHARS:
            out.append((f"From {start // 60:02d}:{start % 60:02d}", " ".join(buf)))
            buf, start = [], None
    if buf:
        out.append((f"From {(start or 0) // 60:02d}:{(start or 0) % 60:02d}", " ".join(buf)))
    return out


# ------------------------------------------------------------------ chunking
def chunk_sections(sections, target=TARGET_CHARS, overlap=OVERLAP_CHARS):
    """Sections to chunks, splitting only what is too long to leave whole.

    A section shorter than the target is one chunk, whatever its length —
    splitting a 200-character answer in half produces two chunks that each
    answer nothing. Only oversized sections are cut, and then on paragraph and
    sentence boundaries, with an overlap so a fact sitting across a cut is still
    retrievable from one side of it.
    """
    chunks = []
    for heading, body in sections:
        body = (body or "").strip()
        if not body:
            continue
        # Too small to answer anything, and it still competes for a retrieval
        # slot. A page's stray "Questions" fragment outranking a real paragraph
        # is how a corpus starts returning headings instead of answers.
        if len(heading or "") + len(body) < 60:
            continue
        if len(body) <= target:
            chunks.append({"heading": heading, "content": body})
            continue

        pieces, cur = [], ""
        for para in re.split(r"\n\s*\n", body):
            para = para.strip()
            if not para:
                continue
            if len(para) > target:
                for sent in re.split(r"(?<=[.!?])\s+", para):
                    if len(cur) + len(sent) + 1 > target and cur:
                        pieces.append(cur.strip())
                        cur = cur[-overlap:] if overlap else ""
                    cur += (" " if cur else "") + sent
            elif len(cur) + len(para) + 2 > target and cur:
                pieces.append(cur.strip())
                cur = (cur[-overlap:] + "\n\n" + para) if overlap else para
            else:
                cur += ("\n\n" if cur else "") + para
        if cur.strip():
            pieces.append(cur.strip())

        for i, piece in enumerate(pieces):
            chunks.append({
                "heading": heading if i == 0 else f"{heading} (continued)" if heading else "",
                "content": piece,
            })
    return chunks


# ---------------------------------------------------------------- embeddings
def embed_batch(texts):
    """One vector per text, 768 dimensions, or None if no key is configured.

    Returning None rather than failing is deliberate: a corpus with no vectors
    is still fully searchable lexically, so ingestion should not refuse to run
    because an embedding key is missing. The database stamps the active model
    on every vector and refuses a foreign one, so a half-embedded corpus can be
    finished later but never silently mixed.
    """
    key = os.environ.get("EMBED_API_KEY")
    provider = os.environ.get("EMBED_PROVIDER", "jina").lower()
    if not key:
        return [None] * len(texts), None

    if provider == "gemini":
        model = os.environ.get("EMBED_MODEL", "text-embedding-004")
        out = []
        for t in texts:
            url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
                   f"{model}:embedContent?key={key}")
            body = {"content": {"parts": [{"text": t}]}, "outputDimensionality": EMBED_DIM}
            out.append(_post_json(url, body, {})["embedding"]["values"])
        return out, model

    if provider == "hf":
        model = os.environ.get("EMBED_MODEL", "sentence-transformers/all-mpnet-base-v2")
        url = f"https://api-inference.huggingface.co/pipeline/feature-extraction/{model}"
        data = _post_json(url, {"inputs": texts, "options": {"wait_for_model": True}},
                          {"Authorization": f"Bearer {key}"})
        return data, model

    model = os.environ.get("EMBED_MODEL", "jina-embeddings-v3")
    data = _post_json("https://api.jina.ai/v1/embeddings",
                      {"model": model, "task": "retrieval.passage",
                       "dimensions": EMBED_DIM, "input": texts},
                      {"Authorization": f"Bearer {key}"})
    return [d["embedding"] for d in data["data"]], model


def _post_json(url, body, extra_headers):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={**BASE_HEADERS, "Content-Type": "application/json", **extra_headers})
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return json.loads(res.read())
    except urllib.error.HTTPError as e:
        detail = e.read()[:400]
        # Never collapse an auth failure into "bad key" — the body is the
        # diagnosis, and on 403 it is often Cloudflare rather than the provider.
        if b"error code: 1010" in detail or b"cloudflare" in detail.lower():
            sys.exit(f"Cloudflare blocked this request before it reached the provider "
                     f"({e.code}). Not a key problem. Verbatim: {detail!r}")
        sys.exit(f"{url.split('/')[2]} returned {e.code}. Its own words: {detail!r}")


# ------------------------------------------------------------------ supabase
def rpc(name, payload):
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base or not key:
        sys.exit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must both be set")
    req = urllib.request.Request(
        f"{base}/rest/v1/rpc/{name}", data=json.dumps(payload).encode(),
        headers={**BASE_HEADERS, "Content-Type": "application/json",
                 "apikey": key, "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=180) as res:
            raw = res.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{name} failed ({e.code}): {e.read()[:400]!r}")


# ---------------------------------------------------------------------- main
KIND_BY_EXT = {
    ".html": "html", ".htm": "html", ".pdf": "pdf", ".docx": "docx",
    ".txt": "text", ".md": "text",
    ".mp4": "video", ".m4a": "video", ".mp3": "video", ".wav": "video", ".webm": "video",
}


def extract(path, kind):
    if kind == "html":
        return strip_html(open(path, encoding="utf-8", errors="replace").read())
    if kind == "docx":
        return extract_docx(path)
    if kind == "pdf":
        return extract_pdf(path)
    if kind == "video":
        return transcribe(path)
    return [("", open(path, encoding="utf-8", errors="replace").read())]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True,
                    choices=["site", "lms", "capstone", "video", "manual"])
    ap.add_argument("--paths", nargs="+", required=True)
    ap.add_argument("--module", default=None)
    ap.add_argument("--title", default=None, help="override the derived title")
    ap.add_argument("--uri-base", default="https://genaitesting.online/")
    ap.add_argument("--dry-run", action="store_true",
                    help="extract and chunk, print what would be sent, touch nothing")
    ap.add_argument("--force", action="store_true",
                    help="re-embed even when the content hash is unchanged")
    args = ap.parse_args()

    for path in args.paths:
        if not os.path.isfile(path):
            print(f"  skip   {path} — not a file", file=sys.stderr)
            continue

        ext = os.path.splitext(path)[1].lower()
        kind = KIND_BY_EXT.get(ext, "other")
        name = os.path.basename(path)
        title = args.title or re.sub(r"[-_]+", " ", os.path.splitext(name)[0]).strip().title()

        sections = extract(path, kind)
        chunks = chunk_sections(sections)
        text = "\n\n".join(c["content"] for c in chunks)
        digest = hashlib.sha256(text.encode()).hexdigest()

        print(f"\n{path}\n  kind={kind} sections={len(sections)} chunks={len(chunks)} "
              f"chars={len(text)} hash={digest[:12]}")

        if args.dry_run:
            for c in chunks[:3]:
                print(f"    [{c['heading'][:48]}] {c['content'][:90].replace(chr(10), ' ')}…")
            if len(chunks) > 3:
                print(f"    … and {len(chunks) - 3} more")
            continue

        uri = args.uri_base + name if args.source == "site" else None
        res = rpc("kb_upsert_document", {
            "p_source_slug": args.source, "p_external_ref": name, "p_title": title,
            "p_kind": kind, "p_module": args.module, "p_uri": uri,
            "p_content_hash": digest, "p_char_count": len(text)})
        row = res[0] if isinstance(res, list) and res else res
        doc_id, unchanged = row["document_id"], row["unchanged"]

        if unchanged and not args.force:
            print("  unchanged — not re-embedding (use --force to override)")
            continue

        vectors, model = embed_batch([c["content"] for c in chunks])
        if model:
            print(f"  embedded {sum(1 for v in vectors if v)} chunks with {model}")
        else:
            print("  no EMBED_API_KEY — storing text only; lexical search will still work")

        payload = []
        for i, (c, v) in enumerate(zip(chunks, vectors)):
            start = None
            m = re.match(r"From (\d+):(\d+)", c["heading"] or "")
            if m:
                start = int(m.group(1)) * 60 + int(m.group(2))
            payload.append({
                "ordinal": i, "heading": c["heading"] or None, "content": c["content"],
                "char_count": len(c["content"]),
                "start_sec": start, "end_sec": None,
                "embedding": json.dumps(v) if v else "",
                "embed_model": model or "",
            })

        n = rpc("kb_replace_chunks", {"p_document": doc_id, "p_chunks": payload})
        print(f"  stored {n} chunks")
        time.sleep(0.2)   # the free embedding tiers are rate limited; be polite


if __name__ == "__main__":
    main()
