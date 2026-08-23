"""The GenAI Testing course page — the page that has to rank for the money terms.

Target queries, taken from real Google SERPs rather than guessed: "genai testing
course for qa testers", "generative ai for testers", "ai testing course", "llm
testing course", "agentic ai testing course", each of which also showed strong
"in india" and "free" modifiers in related searches. The competing results are
Udemy, Coursera, Testleaf, The Testing Academy and ISTQB CT-AI — all of which
have a full course page, which is why this page has to exist at all.
"""
from build_pages import SITE, BRAND, head, TAIL, crumbs, offers, ORG, WEBSITE, footer
from curriculum import genai_syllabus, genai_syllabus_ld

TITLE = "GenAI &amp; LLM Testing Course for QA Testers | GenAITesting"
DESC = ("Test LLM, RAG and AI agent applications: hallucination and prompt-injection "
        "testing, 16 modules, two hands-on projects. Module 1 free, then from ₹499.")

COURSE = {
    "@type": "Course",
    "@id": SITE + "/genai-testing-course.html#course",
    "name": "GenAI Testing",
    "alternateName": "GenAI Application Testing",
    "description": ("A practitioner track for software testers moving into "
                    "Generative AI. Covers LLM fundamentals, prompt engineering, "
                    "red-team testing, RAG and multi-agent systems, and automation "
                    "with Promptfoo, DeepEval and RAGAS, finishing with two capstone "
                    "projects and three levels of certification."),
    "url": SITE + "/genai-testing-course.html",
    "provider": {"@id": SITE + "/#org"},
    "inLanguage": "en",
    "educationalLevel": "Intermediate",
    "teaches": [
        "LLM output evaluation", "Hallucination detection", "Prompt engineering for testers",
        "Red-team testing of LLM applications", "Prompt injection testing",
        "RAG retrieval quality and knowledge-base poisoning",
        "Testing AI agents and multi-agent systems", "Model Context Protocol (MCP) tool testing",
        "Test automation with Promptfoo, DeepEval and RAGAS", "LLM observability and tracing",
    ],
    "audience": {"@type": "EducationalAudience", "educationalRole": "student",
                 "audienceType": "Manual testers, automation testers and SDETs"},
    "numberOfCredits": 16,
    "coursePrerequisites": ("Working knowledge of software testing. No machine-learning "
                            "background required; Python is taught in the companion track."),
    "offers": offers(SITE + "/genai-testing-course.html"),
    "hasCourseInstance": {
        "@type": "CourseInstance",
        "courseMode": ["online", "asynchronous"],
        "courseWorkload": "PT93H",
        "location": {"@type": "VirtualLocation", "url": SITE + "/app.html"},
    },
    "syllabusSections": genai_syllabus_ld(),
    "educationalCredentialAwarded": [
        {"@type": "EducationalOccupationalCredential", "name": "GenAI Testing — Basic Level"},
        {"@type": "EducationalOccupationalCredential", "name": "GenAI Testing — Advanced Level"},
        {"@type": "EducationalOccupationalCredential", "name": "GenAI Testing — Expert Level"},
    ],
}

LD = {"@context": "https://schema.org", "@graph": [
    ORG, WEBSITE, COURSE,
    crumbs([("Home", ""), ("GenAI Testing course", "genai-testing-course.html")]),
]}

BODY = """
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Course</p>
    <h1>GenAI Testing<br><span class="accent">for QA engineers and automation testers</span></h1>
    <p>
      Testing a GenAI application is not testing a form. The same input can give a
      different answer twice, "correct" is a judgement rather than an assertion, and
      the failure you most need to catch — a confident, well-written, entirely false
      answer — passes every check a traditional suite makes. This course is about the
      testing techniques that do catch it.
    </p>
    <p style="margin-top:18px">
      <a class="btn btn-primary" href="index.html?next=app.html">Start Module 1 free</a>
      <a class="btn btn-ghost" style="background:rgba(255,255,255,.08);color:#fff;border-color:rgba(255,255,255,.4)" href="pricing.html">See plans from &#8377;499</a>
    </p>
  </div>
</header>

<main class="wrap section">

  <section class="section">
    <h2>Who this course is for</h2>
    <p class="lead">
      Manual testers who want to stay employable as their product grows an AI feature,
      automation testers and SDETs who need to write assertions against a model's
      output, and QA leads who have been handed an LLM feature and asked for a test
      plan. You need working knowledge of software testing. You do not need a
      machine-learning background, and Python is taught from zero in the
      <a href="python-dsa-course.html">companion Python and DSA track</a>, which the
      same subscription covers.
    </p>
  </section>

  <section class="section">
    <h2>What the 16 modules cover</h2>
    <div class="grid grid-2">
      <div class="card">
        <h3>Foundations and evaluation</h3>
        <p class="muted">What a large language model actually does, why the same prompt
        gives different answers, and how to score an answer you cannot diff. Prompt
        engineering from a tester's point of view, and building a ground-truth set you
        can measure against.</p>
      </div>
      <div class="card">
        <h3>Red-team and safety testing</h3>
        <p class="muted">Hallucination detection, prompt injection and jailbreaks, data
        leakage, bias and toxicity. Writing adversarial cases on purpose, and deciding
        what counts as a defect rather than a model being a model.</p>
      </div>
      <div class="card">
        <h3>RAG systems</h3>
        <p class="muted">Retrieval quality, chunking and embedding choices, citation
        faithfulness, and knowledge-base poisoning — where a single planted document
        changes what the system tells every user.</p>
      </div>
      <div class="card">
        <h3>Agents, multi-agent systems and MCP</h3>
        <p class="muted">Testing a system that decides its own next step: tool selection,
        refusals, budget and loop limits, hand-offs between agents, and Model Context
        Protocol tool calls.</p>
      </div>
      <div class="card">
        <h3>Automation</h3>
        <p class="muted">Promptfoo, DeepEval and RAGAS wired into a suite that runs in
        CI, plus observability and tracing so a failure in production is diagnosable
        rather than just reported.</p>
      </div>
      <div class="card">
        <h3>Two capstone projects</h3>
        <p class="muted">Not a walkthrough video — a running application you attack. See
        the projects section below.</p>
      </div>
    </div>
  </section>

  {{SYLLABUS}}

  <section class="section">
    <h2 id="projects">You test real running applications, not slides</h2>
    <p class="lead">
      Two applications are hosted for you, and you work them from a browser with no
      installation. This is the part that separates the course from a video playlist:
      you are looking at a real system's actual output when you decide whether it is
      a defect.
    </p>
    <div class="grid grid-2">
      <div class="card">
        <h3>Project 1 — the RAG application</h3>
        <p class="muted">A travel-planning assistant in five versions, each one broken
        in a different, deliberate way. You run the retrieval, inspect the vector
        store, plant a poisoned document and watch it change the answers, then run
        red- and blue-team suites against it and read the trace of everything you did.</p>
      </div>
      <div class="card">
        <h3>Project 2 — the multi-agent application</h3>
        <p class="muted">A booking system built from several agents with real tool calls
        over MCP. You test hand-offs, watch an agent refuse a call it is not allowed to
        make, break the budget check, and tell the difference between a control working
        and a component failing.</p>
      </div>
    </div>
  </section>

  <section class="section">
    <h2>Certification</h2>
    <p class="lead">
      Three separate exams — Basic, Advanced and Expert. Each one you pass earns its own
      certificate carrying a unique number, and
      <a href="verify.html">anyone can check that number</a> against this site without
      an account, which is what makes it worth putting on a CV. Nothing is awarded for
      finishing the videos; the exams are the bar.
    </p>
  </section>

  <section class="section">
    <h2>What it costs</h2>
    <p class="lead">
      <strong>Module 1 is free</strong> once you have an account — no card, nothing else
      to set up. After that one subscription unlocks the rest of this course
      <em>and</em> the whole Python and DSA track: &#8377;499 for a month, &#8377;1,199
      for three months, &#8377;3,999 for a year. Nothing renews on its own, and buying
      again while you still have time left adds days rather than replacing them.
      <a href="pricing.html">Full pricing</a>.
    </p>
  </section>

  <section class="section">
    <h2>Common questions</h2>
    <p class="lead">
      How this compares with ISTQB CT-AI, whether you need Python first, and what an
      AI testing career actually looks like are all answered on the
      <a href="faq.html">FAQ page</a>.
    </p>
  </section>

</main>
"""


def build():
    return (head(path="genai-testing-course.html", title=TITLE, desc=DESC,
                og_title="GenAI Testing course — LLM, RAG and AI agent testing for QA engineers",
                 ld=LD)
            + BODY.replace("{{SYLLABUS}}", genai_syllabus())
            + footer() + (TAIL % "genai"))
