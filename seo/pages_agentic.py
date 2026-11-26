"""Agentic AI testing — agents, agentic RAG and MCP.

The gap in the site's coverage, and the one that matches what the course
actually teaches best. "Agentic AI testing", "agentic RAG", "MCP agent testing"
and "AI agent testing" had no page of their own; the FAQ answered one question
about tool-calling agents and nothing else.

Two things shape how this is written.

It is the best answer-engine surface on the site after the FAQ, so the question
blocks at the end are written to be lifted and attributed: each one true on its
own, specific enough to be worth quoting, and none of them a sales line. An
assistant asked "what is agentic RAG" will not quote a paragraph whose second
sentence is about a course.

And it is specific where the competing pages are abstract. Most writing about
agent testing is a list of concerns with no worked detail, because the author
has not tested one. This can name the failure modes in order because the course
runs a system that produces all of them: an orchestrator that plans inside a
budget and delegates to nine specialist agents over an MCP tool server — it
plans, calls tools, loops, delegates, spends money, messages people and reads
data an attacker could have written.

No claim here about what the course gets you that the capstone does not
actually demonstrate.
"""
from build_pages import SITE, BRAND, head, TAIL, crumbs, ORG, WEBSITE, footer

TITLE = "Agentic AI Testing: Agents, Agentic RAG, MCP | GenAITesting"
DESC = ("How to test AI agents: tool selection, loops and budgets, delegation, agentic "
        "RAG retrieval decisions, and the trust MCP quietly changes.")

# Written as the quotable unit. Tags are stripped for the schema, so the words an
# assistant lifts are exactly the words on the page.
QA = [
    ("What is agentic AI testing?",
     """Testing a system where a model does not just answer but <em>acts</em> — it chooses
     tools, calls them, reads the results, decides what to do next, and often delegates
     to other agents. The shift from ordinary LLM testing is that the output you judge
     is no longer a piece of text. It is a <strong>sequence of decisions</strong>, and a
     run can reach a perfectly good final answer through a route that was expensive,
     unsafe or lucky. So an agentic test suite asserts on the path as well as the
     destination: which tool was chosen, with what arguments, how many times, what was
     refused, and what the agent did when a tool failed."""),

    ("How is testing an AI agent different from testing an LLM?",
     """A single prompt has one failure mode that matters: the text is wrong. An agent
     adds failure modes that have nothing to do with text quality. It can pick the wrong
     tool, construct arguments that are out of bounds, loop until something external
     stops it, delegate to a sub-agent and lose context in the hand-off, act on a tool
     result that an attacker wrote, or spend real money doing any of it. None of those
     show up in an evaluation that only scores the final answer, which is why teams that
     carry their LLM test approach straight across find their agent suite is green while
     the system does alarming things in staging."""),

    ("What is agentic RAG, and how do you test it?",
     """In ordinary RAG, retrieval is a fixed step: every question triggers a search, and
     the results go into the prompt. In <strong>agentic RAG</strong> the model decides —
     whether to retrieve at all, what to search for, which source to use, whether the
     results were good enough, and whether to search again with a different query. That
     makes retrieval a decision rather than a step, and decisions are what you test.
     Four cases carry most of the value: a question answerable from the model's own
     knowledge (does it skip retrieval, or search pointlessly?); a question needing two
     different sources (does it make both calls?); a first search that returns nothing
     useful (does it reformulate, or answer from the noise?); and a question nothing in
     the corpus covers (does it say so?). The last one is where ordinary RAG metrics
     mislead most, because faithfulness scores well against whatever came back."""),

    ("How do you test an MCP agent?",
     """Model Context Protocol standardises how an agent connects to tools, and the
     testing interest is entirely in what it changes about trust. <strong>Tool
     descriptions are prompt</strong>: the text describing a tool reaches the model, so a
     compromised server can put instructions there. <strong>Tool results are untrusted
     input</strong>, and an agent that treats whatever a server returns as fact has handed
     its behaviour to that server. <strong>Grants are usually too broad</strong>, because
     a connection added for one task stays available for every later one. And servers
     update independently, so a tool that behaved one way when you tested it can behave
     differently tomorrow with no change on your side. The test that finds all of this is
     a deliberately hostile MCP server of your own: have it return a result containing an
     instruction and watch whether the agent obeys it."""),

    ("What is trajectory testing?",
     """Asserting on the route the agent took, not only the answer it produced. A
     trajectory is the ordered record of tool calls, arguments, results and decisions in
     one run. You test it the way you would test a log: this tool should appear exactly
     once; this one should never appear for this input; the budget check should precede
     the booking call; no tool should be retried more than three times. It matters
     because outcome-only testing cannot distinguish a correct answer reached safely
     from a correct answer reached by calling a payment tool four times and getting
     lucky — and in production those are not the same system."""),

    ("How do you stop an AI agent looping or overspending?",
     """Limits that live outside the model, and tests that prove they hold. A prompt
     asking an agent to be careful is not a control; a hard cap on iterations, on tool
     calls per run, on total tokens and on money is. Test them by making the environment
     hostile rather than by hoping: force a tool to fail repeatedly and assert the agent
     stops rather than retrying forever; set the budget below the cost of the task and
     assert it halts and reports instead of proceeding. The failure to look for is an
     agent that treats a limit as an obstacle and works around it — by splitting a
     purchase, say — which is behaviour you only ever see if you test at the boundary."""),

    ("Is a refusal from an agent a bug?",
     """Usually it is the control working, and logging it as a defect is how teams train
     a system towards the behaviour they least want. When an agent declines to call a
     destructive tool on a vague instruction, that is correct. The real measure needs
     both directions, because <strong>over-refusal is also a defect</strong>: an agent
     that refuses ordinary requests is useless in a quieter way than one that is
     reckless. So the suite holds a paired set — prompts that must be acted on and
     prompts that must be refused — and both halves have to pass before either number
     means anything."""),
]


def strip_tags(html):
    """The schema carries the same words as the page, minus the markup."""
    out, depth = [], 0
    for ch in html:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return " ".join("".join(out).split())


ARTICLE = {
    "@type": "Article",
    "@id": SITE + "/agentic-ai-testing.html#article",
    "headline": "Agentic AI testing: agents, agentic RAG and MCP",
    "description": DESC,
    "author": {"@id": SITE + "/#org"},
    "publisher": {"@id": SITE + "/#org"},
    "inLanguage": "en",
    "about": ["Agentic AI testing", "AI agent testing", "Agentic RAG",
              "Model Context Protocol", "LLM testing", "Multi-agent systems"],
}

FAQ_LD = {
    "@type": "FAQPage",
    "@id": SITE + "/agentic-ai-testing.html#faq",
    "mainEntity": [{
        "@type": "Question", "name": q,
        "acceptedAnswer": {"@type": "Answer", "text": strip_tags(a)},
    } for q, a in QA],
}

LD = {"@context": "https://schema.org", "@graph": [
    ORG, WEBSITE, ARTICLE, FAQ_LD,
    crumbs([("Home", ""), ("Agentic AI testing", "agentic-ai-testing.html")]),
]}

TOP = """
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Agents</p>
    <h1>Agentic AI testing<br><span class="accent">when the model stops answering and starts acting</span></h1>
    <p>
      An agent plans, calls tools, loops, delegates, spends money, sends messages, and
      reads data someone else wrote. Each of those is a failure mode that an evaluation
      scoring the final answer will never see. This is what changes, and how to test it.
    </p>
  </div>
</header>

<main class="wrap section">

  <section class="section">
    <h2>The one shift everything else follows from</h2>
    <p class="lead">
      When you test a single prompt, the thing you judge is a piece of text. When you
      test an agent, the text is often the least interesting part of the run. The agent
      reached that answer by choosing tools, reading what came back, and deciding what to
      do next — and it can arrive at a perfectly good answer through a route that was
      expensive, unsafe, or simply lucky. Run it again and the route changes.
    </p>
    <p class="lead">
      So the unit of testing moves from the output to the <strong>trajectory</strong>:
      the ordered record of what was called, with what arguments, how many times, what
      was refused, and what happened when something failed. Outcome-only testing cannot
      tell a correct answer reached safely from a correct answer reached by calling a
      payment tool four times and getting away with it. In production those are not the
      same system, and only one of them is one you want.
    </p>
  </section>

  <section class="section">
    <h2>The six things that actually break</h2>
    <div class="grid grid-2">
      <div class="card">
        <h3>Tool selection</h3>
        <p class="muted">Given an ambiguous request, does it reach for the right tool —
        and for none at all when none applies? The interesting case is the near-miss: two
        tools whose descriptions overlap, where picking either looks reasonable and only
        one is correct.</p>
      </div>
      <div class="card">
        <h3>Arguments</h3>
        <p class="muted">Well-formed, in range, and derived from what the user actually
        said. Vague phrasing is where agents invent: a date nobody gave, a quantity
        rounded up, an identifier that looks plausible and belongs to someone else.</p>
      </div>
      <div class="card">
        <h3>Loops and budgets</h3>
        <p class="muted">Make a tool fail on purpose and watch. Does it stop, or retry
        until something external cuts it off? A prompt asking it to be careful is not a
        control. A hard cap on iterations, tool calls, tokens and money is.</p>
      </div>
      <div class="card">
        <h3>Delegation</h3>
        <p class="muted">When one agent hands to another, what travels with it? Context
        gets lost, and sometimes the opposite — something sensitive travels that should
        not. Both are hand-off defects and neither is visible in the final answer.</p>
      </div>
      <div class="card">
        <h3>Untrusted results</h3>
        <p class="muted">An agent reads tool output and acts on it. If that output can
        contain text someone else wrote, you have an instruction channel you did not
        design. This is indirect prompt injection, and agents are where it gets
        expensive, because the payload can reach something that spends money.</p>
      </div>
      <div class="card">
        <h3>Refusals, in both directions</h3>
        <p class="muted">Declining a destructive call on a vague instruction is the
        control working. Over-refusal is also a defect, just a quieter one. The suite
        needs paired sets — must-act and must-refuse — and both halves have to pass
        before either number means anything.</p>
      </div>
    </div>
  </section>

  <section class="section">
    <h2>Agentic RAG: retrieval becomes a decision</h2>
    <p class="lead">
      Ordinary RAG retrieves on every question and puts the results in the prompt.
      Agentic RAG lets the model decide: whether to search at all, what to search for,
      which source to use, whether what came back was good enough, and whether to go
      again with a better query. That is a real improvement in capability and it moves
      the thing you test. Retrieval precision still matters, but now so does
      <em>judgement about retrieval</em>.
    </p>
    <p class="lead">
      Four cases carry most of the value. A question the model can answer from its own
      knowledge — does it skip the search, or burn a call and a second of latency on it?
      A question needing two different sources — does it make both calls, or answer from
      the first? A first search that returns nothing useful — does it reformulate, or
      answer from the noise it got? And a question the corpus simply does not cover —
      does it say so? That last one is where the familiar metrics mislead most, because
      faithfulness scores perfectly well against whatever happened to come back.
    </p>
  </section>

  <section class="section">
    <h2>MCP, and the trust it quietly changes</h2>
    <p class="lead">
      Model Context Protocol standardises how an agent connects to tools and data, so any
      client that speaks it can use any server without a bespoke integration. That part
      is genuinely useful. The testing interest is in what it does to trust, and there
      are three things worth holding on to.
    </p>
    <p class="lead">
      <strong>Tool descriptions are prompt.</strong> The text describing a tool reaches
      the model, so a compromised or malicious server can put instructions in it — tool
      poisoning. <strong>Tool results are untrusted input</strong>, and an agent that
      treats whatever a server returns as fact has handed its behaviour to whoever runs
      that server. <strong>Grants drift wider than the task</strong>, because a connection
      added for one job stays available for every later one, so the question is not "does
      this tool work" but "what can it reach when the model is confused or steered".
    </p>
    <p class="lead">
      Servers also update independently of you, so a tool that behaved one way when you
      tested it can behave differently tomorrow with nothing changed on your side. The
      test that finds all of this is a deliberately hostile MCP server of your own: have
      it return a result containing an instruction, and watch whether the agent reports
      it or obeys it.
    </p>
  </section>

  <section class="section">
    <h2>What a suite looks like in practice</h2>
    <p class="lead">
      Three layers, and most teams only build the first. <strong>Outcome</strong>: did the
      run achieve the goal — necessary, insufficient, and the easiest to write.
      <strong>Trajectory</strong>: assertions on the route, read like a log. This tool
      exactly once; this one never for this input; the budget check before the booking
      call; no tool retried more than three times. <strong>Boundary</strong>: the suite
      run against a hostile environment — tools that fail, tools that return injected
      text, budgets set below the cost of the task, instructions that should be refused.
    </p>
    <p class="lead">
      The boundary layer is the one that changes what you ship, and it is the one that
      cannot be written from a specification. It needs a system you are allowed to
      attack.
    </p>
  </section>

  <section class="section">
    <h2>The system this is taught on</h2>
    <p class="lead">
      An orchestrator plans a whole trip inside a budget and delegates to nine specialist
      agents over an MCP tool server. It is deliberately the smallest system that
      produces every agentic failure mode at once: it plans, calls tools, loops,
      delegates, <em>spends money</em>, messages people, and reads data an attacker could
      have written. Alongside it sits a retrieval assistant built five times over, each
      version adding a layer, so a change in behaviour can be traced to a specific
      decision rather than guessed at.
    </p>
    <p class="lead">
      Those are the <a href="projects.html">capstone projects</a> on the
      <a href="genai-testing-course.html">GenAI and LLM testing course</a>. Students
      attack them rather than read about them, which is the only way the boundary layer
      above gets learned. <a href="faq.html">The FAQ</a> answers the narrower technical
      questions, and the <a href="ai-testing-career-path.html">career path page</a>
      covers what to learn in what order.
    </p>
  </section>
"""

TAIL_BODY = """
</main>
"""


def build():
    items = "\n".join(
        f"""    <section class="faq-item">
      <h2>{q}</h2>
      <div class="faq-a">{a}</div>
    </section>""" for q, a in QA)

    body = (TOP
            + '\n  <section class="section">\n    <h2>Questions people ask about testing agents</h2>\n'
            + items + "\n  </section>\n" + TAIL_BODY)

    return (head(path="agentic-ai-testing.html", title=TITLE, desc=DESC,
                 og_title="Agentic AI testing — agents, agentic RAG and MCP",
                 ld=LD)
            + body + footer() + (TAIL % "agentic"))
