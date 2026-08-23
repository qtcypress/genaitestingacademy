"""Take the next item off the content backlog and turn it into work.

Run weekly by .github/workflows/content-slot.yml. Two modes, chosen by whether an
ANTHROPIC_API_KEY secret exists on the repository:

  no key  → prints a brief, and the workflow opens it as a GitHub issue
  key set → drafts the FAQ answer, inserts it, rebuilds, and the workflow opens a
            pull request

The distinction matters more than it looks. A pull request is reviewable by
construction: nothing reaches the site until a human reads the diff and merges it.
Generated content published without that step is how sites earn a manual action,
and the value of this job is the *cadence* — something arriving every Monday that
has to be dealt with — not the prose. A brief in an issue delivers that cadence
perfectly well on its own.

Usage:
    python3 seo/content_slot.py --brief     # print the next brief, mark it OPEN
    python3 seo/content_slot.py --draft     # also draft it (needs ANTHROPIC_API_KEY)
"""
import json
import os
import pathlib
import re
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
BACKLOG = HERE / "content-backlog.md"
FAQ_FILE = HERE / "pages_faq.py"

LINE = re.compile(r"^(TODO|OPEN|DONE)\s*\|\s*(faq|page)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*$")


def next_item():
    """First TODO line, with its line index so we can mark it."""
    lines = BACKLOG.read_text(encoding="utf-8").split("\n")
    for i, ln in enumerate(lines):
        m = LINE.match(ln.strip())
        if m and m.group(1) == "TODO":
            return i, lines, {"kind": m.group(2), "question": m.group(3), "angle": m.group(4)}
    return None, lines, None


def mark_open(idx, lines):
    lines[idx] = lines[idx].replace("TODO |", "OPEN |", 1)
    BACKLOG.write_text("\n".join(lines), encoding="utf-8")


def brief(item):
    where = ("a new entry in seo/pages_faq.py — it will appear on faq.html and in "
             "the FAQPage schema automatically"
             if item["kind"] == "faq"
             else "a new standalone page, which also needs a sitemap entry in "
                  "seo/build.py and a link from the footer")
    return f"""**Question to answer:** {item['question']}

**Angle:** {item['angle']}

**Where it goes:** {where}

**How to write it.** The answer has to stand on its own, because an assistant lifts
one paragraph and attributes it — a sentence that only makes sense after reading the
rest of the page is a sentence that will never be quoted. Be specific enough to be
worth quoting: name the actual tools, metrics and failure modes rather than
gesturing at them. Where the honest answer includes "not this course" or "a
competitor does this better", say so; a page that claims to be best at everything is
the one assistants learn to distrust, and readers can tell too.

Target 150–350 words. No invented statistics, no ratings, no claims about outcomes
we have not measured.

**To do this with Claude:** open the repo and ask for this question to be added to
the FAQ, pointing at this issue. The build step is `python3 seo/build.py`.

---
*Opened automatically from `seo/content-backlog.md`. The line is now marked `OPEN`;
set it to `DONE` when this is live.*"""


def draft_with_api(item):
    """Ask Claude for the answer. Returns HTML for the FAQ answer body, or None."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return None
    prompt = f"""Write one FAQ answer for genaitesting.online, a site teaching software
testers how to test GenAI, LLM, RAG and AI-agent applications.

Question: {item['question']}
Angle to take: {item['angle']}

Rules:
- 150 to 350 words, as one to three <p>-free paragraphs of HTML using only <strong>,
  <em> and <code> inline. Do not include the question itself.
- Self-contained: it will be quoted in isolation by AI assistants.
- Specific: name real tools, metrics and failure modes.
- Honest: if a competitor or a certification is the better answer for some readers,
  say so plainly.
- No invented statistics, no ratings, no outcome claims.
Return only the answer HTML."""
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps({"model": "claude-sonnet-4-5", "max_tokens": 1200,
                         "messages": [{"role": "user", "content": prompt}]}).encode(),
        headers={"content-type": "application/json", "x-api-key": key,
                 "anthropic-version": "2023-06-01"})
    with urllib.request.urlopen(req, timeout=120) as r:
        body = json.loads(r.read())
    return "".join(b.get("text", "") for b in body.get("content", [])).strip()


def insert_faq(question, answer_html):
    """Add the pair to the QA list in pages_faq.py, just before its closing bracket.

    The FAQ page and its FAQPage schema are both generated from that one list, so
    inserting here updates the visible answer and the structured data together —
    they cannot end up describing different things.
    """
    s = FAQ_FILE.read_text(encoding="utf-8")
    anchor = "\n]\n"
    i = s.rindex('     evaluation framework first either way')      # inside last entry
    close = s.index(anchor, i)
    q = question.replace('"', '\\"')
    entry = f'''
    ("{q}",
     """{answer_html}"""),
'''
    s = s[:close] + entry + s[close:]
    FAQ_FILE.write_text(s, encoding="utf-8")


def main():
    idx, lines, item = next_item()
    if item is None:
        print("Backlog is empty — nothing marked TODO.")
        print("::notice::content backlog exhausted; add more targets to seo/content-backlog.md")
        return 0

    want_draft = "--draft" in sys.argv
    text = brief(item)

    drafted = None
    if want_draft:
        try:
            drafted = draft_with_api(item)
        except Exception as e:
            print(f"::warning::drafting failed, falling back to a brief — {e}")

    if drafted:
        insert_faq(item["question"], drafted)
        pathlib.Path("SLOT_TITLE.txt").write_text("Draft: " + item["question"], encoding="utf-8")
        pathlib.Path("SLOT_BODY.md").write_text(
            text + "\n\n---\n\n**A draft is included in this pull request.** Read it before "
                   "merging — it has not been checked by anyone yet, and an unreviewed "
                   "generated answer on a page whose whole value is being trustworthy is a "
                   "bad trade.\n", encoding="utf-8")
    else:
        pathlib.Path("SLOT_TITLE.txt").write_text("Content slot: " + item["question"], encoding="utf-8")
        pathlib.Path("SLOT_BODY.md").write_text(text, encoding="utf-8")

    mark_open(idx, lines)
    print(("Drafted: " if drafted else "Brief for: ") + item["question"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
