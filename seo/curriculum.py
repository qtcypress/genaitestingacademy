"""The module lists, read out of the live `modules` table rather than retyped.

Why these are baked into the HTML instead of fetched at runtime, even though the
table is readable by anon and a fetch would always be current: a guest is not the
only visitor who needs to see this. Googlebot renders JavaScript eventually, but
the assistant crawlers that matter for AEO mostly do not — they read the HTML they
are served. A syllabus that only exists after a fetch is a syllabus those crawlers
never see, and the whole point of publishing it is to be found and quoted.

Cost of that choice: this file goes stale if the syllabus changes in the database.
Re-run `python3 seo/build.py` after editing modules and the pages catch up.

Fetched 19 Aug 2026. GenAI Testing: 16 modules, module 1 free. Python Zero to Hero:
24 modules in six phases, Phase 1 (modules 1-4) free.
"""

# (number, title, summary, hours, free)
GENAI = [
    (1, "Introduction to Gen AI", "What generative AI is, how it differs from traditional software, and why it needs a different testing mindset.", 3, True),
    (2, "Basics of LLM", "How large language models actually work — tokens, context, parameters — and the failure modes that follow from the architecture.", 4, False),
    (3, "Prompt Engineering", "Designing, versioning and testing prompts as production artefacts rather than throwaway text.", 4, False),
    (4, "Red Team Testing", "Adversarial testing of GenAI applications — deliberately making a system misbehave, and documenting it responsibly.", 5, False),
    (5, "Capstone Project — Requirements PRD, Test Plan, Test Cases & Reports", "The complete manual-testing documentation set for a GenAI application, produced end to end.", 6, False),
    (6, "Promptfoo — Evaluation", "Automating prompt and model evaluation with Promptfoo: declarative test cases, assertions and CI integration.", 6, False),
    (7, "Promptfoo — Red Team Testing", "Using Promptfoo's red-team tooling to generate and run adversarial suites automatically.", 6, False),
    (8, "Python for Testers", "The Python a tester actually needs to drive an evaluation framework — no computer-science detour.", 5, False),
    (9, "Pytest", "Turning GenAI evaluations into a real test suite with pytest — fixtures, parametrisation and CI reporting.", 5, False),
    (10, "RAG Development", "Building a retrieval-augmented generation pipeline so you understand every seam where it can fail.", 6, False),
    (11, "MCP with Multi-Agent Development", "Model Context Protocol and multi-agent systems — how agents get tools, and how coordination fails.", 7, False),
    (12, "RAGAS Metrics for RAG", "Measuring RAG quality objectively with RAGAS — faithfulness, relevancy and the retrieval metrics.", 5, False),
    (13, "DeepEval for Agents", "Unit-test style evaluation of LLM and agent behaviour with DeepEval, integrated into pytest.", 5, False),
    (14, "Observability with LangSmith", "Tracing, monitoring and debugging LLM and agent applications in development and production.", 4, False),
    (15, "Capstone Project #1 — RAG-based", "Build, test and report on a complete RAG application, applying everything from modules 1–14.", 10, False),
    (16, "Capstone Project #2 — MCP with Multi-Agents", "Build, test and report on a multi-agent system over MCP, the hardest thing in the course.", 12, False),
]

PY_PHASES = [
    (1, "Foundations", "Variables and types, operators, strings, conditionals, loops, lists and tuples, dictionaries and sets, functions.", True),
    (2, "Intermediate Python", "Object-oriented programming, modules and packages, file I/O and error handling, comprehensions, generators and decorators.", False),
    (3, "DSA Foundations", "Complexity analysis, array and string problems, linked lists, stacks and queues with recursion.", False),
    (4, "DSA Core", "Trees, graphs, hashing, sorting and searching algorithms.", False),
    (5, "DSA Advanced", "Dynamic programming, greedy algorithms, backtracking, advanced graph algorithms.", False),
    (6, "Expert", "Concurrency, testing with pytest, packaging, design patterns, performance and a capstone.", False),
]

# (number, title, free, phase)
PYTHON = [
    (1, "First Contact — Values, Operators, Strings & Decisions", True, 1),
    (2, "Collections & Repetition — Lists, Tuples & Loops", True, 1),
    (3, "Dictionaries, Sets & Functions", True, 1),
    (4, "Files, Errors & a First Look at OOP", True, 1),
    (5, "OOP Deep Dive — Inheritance & Special Methods", False, 2),
    (6, "Modules, Packages & the Python Ecosystem", False, 2),
    (7, "Comprehensions, Generators & Decorators", False, 2),
    (8, "Regex & Testing with pytest-style Tests", False, 2),
    (9, "Complexity Analysis — Big-O", False, 3),
    (10, "Arrays & Strings — Core Interview Patterns", False, 3),
    (11, "Linked Lists — Your First Real Data Structure", False, 3),
    (12, "Stacks, Queues & Recursion", False, 3),
    (13, "Trees", False, 4),
    (14, "Graphs", False, 4),
    (15, "Hashing, Sets & Counting", False, 4),
    (16, "Sorting, Searching & Heaps", False, 4),
    (17, "Dynamic Programming", False, 5),
    (18, "Greedy Algorithms", False, 5),
    (19, "Backtracking", False, 5),
    (20, "Advanced Graph Algorithms", False, 5),
    (21, "Concurrency & Async", False, 6),
    (22, "Testing & Quality with pytest", False, 6),
    (23, "Packaging, Tooling & Design Patterns", False, 6),
    (24, "Performance, and the Final Capstone", False, 6),
]

# Where a guest goes when they want to actually open something. index.html carries
# the GitHub, Google and email sign-in, and ?next= brings them back to the course
# rather than dumping them on a dashboard they did not ask for.
# start=free tells index.html this visitor arrived from a free-content link, so it
# can open the Create-account tab and say why they are there, rather than showing a
# bare Sign-in form to somebody who has no account yet.
SIGNIN = "index.html?next=app.html&start=free"


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def module_row(num, title, summary, hours, free, label="Module"):
    """One row of the public syllabus.

    A free row is a link, because it leads somewhere. A paid row is not, because a
    link that only tells you that you cannot have the thing is a small
    disappointment repeated twenty times down a page. It carries a lock and the
    pricing link sits once at the bottom of the section instead.
    """
    meta = []
    if hours:
        meta.append(f"{hours}h")
    meta_html = f'<span class="mod-meta">{" · ".join(meta)}</span>' if meta else ""
    if free:
        return f"""        <a class="mod mod-free" href="{SIGNIN}">
          <span class="mod-n">{label} {num}</span>
          <span class="mod-t">{esc(title)}</span>
          {f'<span class="mod-s">{esc(summary)}</span>' if summary else ""}
          <span class="mod-tag mod-tag-free">Free — start now</span>{meta_html}
        </a>"""
    return f"""        <div class="mod">
          <span class="mod-n">{label} {num}</span>
          <span class="mod-t">{esc(title)}</span>
          {f'<span class="mod-s">{esc(summary)}</span>' if summary else ""}
          <span class="mod-tag">Subscribers</span>{meta_html}
        </div>"""


def genai_syllabus():
    rows = "\n".join(module_row(n, t, s, h, f) for n, t, s, h, f in GENAI)
    free_n = sum(1 for m in GENAI if m[4])
    total_h = sum(m[3] for m in GENAI if m[3])
    return f"""
  <section class="section" id="syllabus">
    <h2>All 16 modules, in order</h2>
    <p class="lead">
      The whole syllabus is here to read before you decide anything — no sign-up, no
      email, no "request the curriculum". Module 1 is free to work through in full;
      the rest need a subscription. About {total_h} hours of material in total.
    </p>
    <div class="modlist">
{rows}
    </div>
    <p class="lead" style="margin-top:18px">
      <a class="btn btn-primary" href="{SIGNIN}">Start Module 1 free</a>
      <a class="btn btn-ghost" href="pricing.html">Unlock the rest from &#8377;499</a>
    </p>
  </section>
"""


def python_syllabus():
    blocks = []
    for pn, pname, pblurb, pfree in PY_PHASES:
        mods = [m for m in PYTHON if m[3] == pn]
        rows = "\n".join(module_row(n, t, "", None, f) for n, t, f, _ in mods)
        tag = '<span class="mod-tag mod-tag-free">Free</span>' if pfree else ""
        blocks.append(f"""      <div class="phase">
        <h3>Phase {pn} — {esc(pname)} {tag}</h3>
        <p class="muted" style="margin:0 0 10px;font-size:13.5px">{esc(pblurb)}</p>
        <div class="modlist">
{rows}
        </div>
      </div>""")
    return f"""
  <section class="section" id="syllabus">
    <h2>All 24 modules, phase by phase</h2>
    <p class="lead">
      Read the entire syllabus before signing up for anything. Phase 1 — four modules,
      twenty lessons — is free in full once you have an account, and every code sample
      in it runs in your browser with nothing to install.
    </p>
    <div class="phases">
{chr(10).join(blocks)}
    </div>
    <p class="lead" style="margin-top:18px">
      <a class="btn btn-primary" href="{SIGNIN}">Start Phase 1 free</a>
      <a class="btn btn-ghost" href="pricing.html">Unlock Phases 2–6 from &#8377;499</a>
    </p>
  </section>
"""


def genai_syllabus_ld():
    """schema.org syllabusSections, so the module list is machine-readable and an
    assistant asked "what does the GenAI testing course cover" has structured facts
    rather than having to summarise prose."""
    out = []
    for n, t, s, h, f in GENAI:
        node = {"@type": "Syllabus", "name": f"Module {n} — {t}", "description": s,
                "isAccessibleForFree": bool(f)}
        # omit rather than emit null: a validator reads an explicit null as a
        # declared-but-empty value, which is worse than saying nothing
        if h:
            node["timeRequired"] = f"PT{h}H"
        out.append(node)
    return out


def python_syllabus_ld():
    out = []
    for pn, pname, pblurb, pfree in PY_PHASES:
        mods = ", ".join(t for n, t, f, p in PYTHON if p == pn)
        out.append({"@type": "Syllabus",
                    "name": f"Phase {pn} — {pname}",
                    "description": pblurb + " Modules: " + mods + ".",
                    "isAccessibleForFree": bool(pfree)})
    return out
