# TripSage RAG — testing console

Serves all four versions of the TripSage RAG engine from one process. The student picks a
version, reads what that version changed, and then works it through a set of tabs. Pure Python
standard library — no `pip install`, no LLM API key, nothing to pay for per request.

```
rag-console/
  server.py            the console (router + UI + access gate + session isolation)
  render.yaml          Render blueprint
  Procfile             for hosts that read one
  versions/v1..v4/     the four engines, one folder each
```

## Tabs, and which versions have them

Tabs are built from what each engine can actually do, not from a hardcoded list, so adding a
capability to an engine makes its tab appear.

| Tab | v1 | v2 | v3 | v4 | Backed by |
|---|:--:|:--:|:--:|:--:|---|
| Ask | ✓ | ✓ | ✓ | ✓ | `RAGEngine.ask` |
| Red / blue team | ✓ | ✓ | ✓ | ✓ | `tests/red_team.json`, `tests/blue_team.json` |
| Knowledge base | | ✓ | ✓ | ✓ | `add_kb_doc` / `list_kb` present |
| Vector DB | | | ✓ | ✓ | `probe`, `eval_retrieval`, `store.stats` present |
| Logs | ✓ | ✓ | ✓ | ✓ | traces captured per session |

The Ask tab on v4 also carries a **defences on/off** toggle, because only v4 has `self.defenses`.
Turning it off reproduces the breach: the same question comes back with
`BREACH_indirect_injection_executed` instead of `indirect_injection_neutralised`.

## Test verdicts have three outcomes, not two

`pass`, `fail`, and `weak`. **Weak** means the version did not misbehave, but not for the reason
the case was written to test — it abstained because retrieval came back empty rather than because
a guardrail fired, for instance. Collapsing that into "pass" hides the thing a tester most needs
to notice. The rule and its reasoning are printed beside every row so students can disagree.

Poisoning verdicts look at **which document grounded the answer**, not merely at whether a
poisoned document was cited. Only the first used chunk composes the answer, so a poisoned doc
appearing further down the citation list is a different (and much less serious) finding.

---

## Why not just host the original `app.py`?

Three things make it unsuitable for a shared URL, and this wrapper fixes all three without
touching the engines themselves.

**It binds localhost and opens a browser.** `ThreadingHTTPServer(("127.0.0.1", port))` is
unreachable from outside the machine, and every version hardcodes port 8000, so they can't run
side by side. This binds `0.0.0.0` on `$PORT`.

**Its engine is one global object that any visitor can mutate.** `POST /api/config` changes
`top_k`, flips poison mode, turns defences off and calls `reindex()` — on the *shared* engine.
On a laptop with one tester that's the point. On a public URL, one student turning defences off
changes what every other student sees at that moment, and `reindex()` on demand is free CPU for
anyone who wants to hammer it.

Here the boot-time indexes are immutable and shared, and any action that *would* mutate one —
adding a document, turning defences off — instead builds a private overlay engine keyed to that
browser session. `top_k` and `threshold` are applied per request; poisoned mode selects a
pre-built poisoned index rather than re-indexing. Sessions are capped (40 sessions, 6 documents
of 20 KB each per version, 45-minute idle expiry, LRU eviction) so the isolation cannot be turned
into a memory-exhaustion trick. Verified: one session adding a document that contradicts the
knowledge base changes only that session's answer, while another session still gets the original.

**It writes to disk.** `write_trace()` appends every query to `logs/trace.jsonl`, judgments and
retrieval evaluations go to CSVs, and the vector store persists a JSON snapshot. On every free
host the filesystem is wiped on restart, and all visitors would share one file — so those writes
are redirected into per-session memory. That is also what makes the Logs tab show *your* run
rather than everyone's.

---

## Deploy on Render (free, no card)

1. Copy this whole `rag-console/` folder into the repo root and push.
2. Render → **New** → **Blueprint** → pick the repo. It reads `render.yaml`.
   Or **New → Web Service** by hand: runtime **Python**, root directory `rag-console`,
   build command empty, start command `python server.py`.
3. Set one environment variable in the Render dashboard: `RAG_GATE_SECRET`.
   Generate it anywhere, e.g. in Supabase's SQL editor:
   `select encode(gen_random_bytes(32), 'hex');`
4. Deploy. Watch the log — you should see all four versions build their indexes and then
   `listening on 0.0.0.0:10000  (gate: on)`.
5. Check `https://your-service.onrender.com/healthz` returns
   `{"versions_loaded": 4, "total": 4}`.

**What free costs you:** 750 instance-hours a month (plenty — it sleeps when idle), and a
**cold start of about a minute** after 15 minutes without traffic. The first student of the day
waits. `projects.html` warns them about this. If that becomes annoying, move to Google Cloud Run,
which cold-starts in seconds; the code needs no changes, only a small Dockerfile.

---

## Wire it to the LMS paywall

The console is a different origin with no access to a Supabase session, so linking students
straight to its URL would make the paywall decorative — anyone who saw the link could use it
forever. Instead:

1. Deploy the `rag-access` Edge Function (in `edge-functions/rag-access/`) with JWT verification
   left **ON**. Give it the secret `RAG_GATE_SECRET` — the **same value** as on Render.
2. Set `RAG_CONSOLE_URL` in `config.js` to your Render URL, no trailing slash.
3. Deploy the site.

Then `projects.html` asks the Edge Function whether the signed-in student has paid access. If
they do, it gets back a token signed with the shared secret and valid for 12 hours, and links to
`CONSOLE_URL/?t=<token>`. `server.py` verifies the signature and expiry itself — no database, no
Supabase call, no round trip.

Leave `RAG_GATE_SECRET` unset on Render and the gate is **off**: anyone with the URL can use the
console. That's a reasonable way to test the deploy, but don't leave it that way if projects are
meant to be paid-only.

---

## Testing it locally

```bash
cd rag-console
python server.py                 # gate off, open http://localhost:8000

RAG_GATE_SECRET=devsecret python server.py       # gate on
python -c "import server; print(server.mint_token())"   # with the same env var set
# then open http://localhost:8000/?t=<that token>
```

Verified behaviour: no token → 401, valid token → 200, tampered signature → 401, expired token
→ 401. The page itself always loads and shows a "this console is for enrolled students" panel,
so a stale link gives a readable explanation rather than a blank failure.

---

## Adding a fifth version later

Drop the folder in as `versions/v5/` (it needs `rag_engine.py`, `kb/`, `config.json`, and
`kb_poison/` if it has one) and add one line to `VERSIONS` at the top of `server.py`:

```python
("v5", "5.0  Whatever", "The one change this version makes."),
```

Nothing else changes. The UI builds its version picker from that list.

---

## Housekeeping worth doing in the repo

Noticed while packaging this, none of it breaking anything:

* The folder at `RAG project/tripsage-rag/` is a **byte-for-byte duplicate** of
  `application_code_poisoning_3.0/` — `diff -r` reports no differences at all. One of them can go.
* `__pycache__/*.pyc` and populated `logs/` (including `vectorstore.json`, `trace.jsonl` and
  `tripsage.log`) are committed. A `.gitignore` is included here for the copy under
  `rag-console/`; worth adding one at the repo root too.
* The version folders are named four different ways — `Application_code`, `Application_Code_1.0`,
  `application_code_2.0`, `application_code_poisoning_3.0` — and each nests redundantly as
  `X/TripSage_RAG/tripsage-rag/`. Renaming them `v1_baseline` … `v4_poisoning` would make the
  progression legible to a student browsing the repo.
* `config.json` in every version carries an empty `"openai_api_key"`. Nothing reads it — the
  engines are pure local TF-IDF. Worth deleting the key so nobody assumes an API key is needed,
  and so nobody ever commits one there.
