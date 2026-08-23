"""The Python + DSA course page.

Target queries from the real SERP: "DSA with Python", "python dsa course with
certificate", "data structures and algorithms with python", plus the heavy "free"
and "interview / placement / LeetCode" modifiers that dominate related searches.
Competing pages are GeeksforGeeks, PW, CampusX and a wall of Udemy listings, so
the differentiators worth leading on are the two things they mostly do not have:
code that runs in the browser with nothing to install, and a genuinely free first
phase rather than a free trailer.
"""
from build_pages import SITE, BRAND, head, TAIL, crumbs, offers, ORG, WEBSITE, footer
from curriculum import python_syllabus, python_syllabus_ld

TITLE = "Python &amp; DSA Course: 24 Modules, Phase 1 Free | GenAITesting"
DESC = ("Python and DSA in 24 modules, variables to dynamic programming. Every example "
        "runs in your browser — nothing to install. Phase 1 free, then from ₹499.")

COURSE = {
    "@type": "Course",
    "@id": SITE + "/python-dsa-course.html#course",
    "name": "Python Zero to Hero",
    "alternateName": "Python and Data Structures & Algorithms",
    "description": ("Twenty-four modules from variables to dynamic programming, five "
                    "lessons each, with every code sample runnable in the browser. "
                    "Phase 1 is free with an account; Phase 2 onwards needs an active "
                    "subscription."),
    "url": SITE + "/python-dsa-course.html",
    "provider": {"@id": SITE + "/#org"},
    "inLanguage": "en",
    "educationalLevel": "Beginner to Advanced",
    "teaches": [
        "Python variables, types and operators", "Strings, conditionals and loops",
        "Lists, tuples, dictionaries and sets", "Functions and scope",
        "Object-oriented programming in Python", "Modules, packages and file I/O",
        "Comprehensions, generators and decorators",
        "Time and space complexity analysis (Big O)",
        "Arrays and string algorithms", "Linked lists", "Stacks, queues and recursion",
        "Trees and graphs", "Hashing", "Sorting and searching algorithms",
        "Dynamic programming", "Greedy algorithms", "Backtracking",
        "Advanced graph algorithms", "Concurrency in Python",
        "Testing with pytest", "Packaging", "Design patterns and performance",
    ],
    "audience": {"@type": "EducationalAudience", "educationalRole": "student",
                 "audienceType": "Beginners, testers learning to code, and candidates preparing for coding interviews"},
    "numberOfCredits": 24,
    "coursePrerequisites": "None. The course starts at variables and assumes no prior programming.",
    "isAccessibleForFree": False,   # only Phase 1 is; the course as a whole is not
    "offers": offers(SITE + "/python-dsa-course.html"),
    "hasCourseInstance": {
        "@type": "CourseInstance",
        "courseMode": ["online", "asynchronous"],
        "location": {"@type": "VirtualLocation", "url": SITE + "/app.html"},
    },
    "syllabusSections": python_syllabus_ld(),
}

LD = {"@context": "https://schema.org", "@graph": [
    ORG, WEBSITE, COURSE,
    crumbs([("Home", ""), ("Python & DSA course", "python-dsa-course.html")]),
]}

BODY = """
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Course</p>
    <h1>Python Zero to Hero<br><span class="accent">with Data Structures &amp; Algorithms</span></h1>
    <p>
      Twenty-four modules, six phases, five lessons in each. Every code sample on every
      page has a Run button and executes in your browser — there is no Python to install,
      no virtual environment to get wrong, and nothing to configure before your first
      line runs. Open a lesson on a phone on the bus and the code still runs.
    </p>
    <p style="margin-top:18px">
      <a class="btn btn-primary" href="index.html?next=app.html">Start Phase 1 free</a>
      <a class="btn btn-ghost" style="background:rgba(255,255,255,.08);color:#fff;border-color:rgba(255,255,255,.4)" href="pricing.html">See plans from &#8377;499</a>
    </p>
  </div>
</header>

<main class="wrap section">

  <section class="section">
    <h2>The six phases</h2>
    <p class="lead">
      A lesson is a thing you finish, so the course is measured in lessons rather than
      weeks — there is no calendar to fall behind.
    </p>
    <div class="grid grid-2">
      <div class="card">
        <h3>Phase 1 — Foundations <span class="pill pill-done">Free</span></h3>
        <p class="muted">Modules 1–4. Variables and types, operators, strings, conditionals
        and loops, lists and tuples, dictionaries and sets, functions. Free with an
        account, in full — not a preview.</p>
      </div>
      <div class="card">
        <h3>Phase 2 — Intermediate Python</h3>
        <p class="muted">Modules 5–8. Object-oriented programming, modules and packages,
        file I/O and error handling, comprehensions, generators and decorators.</p>
      </div>
      <div class="card">
        <h3>Phase 3 — DSA Foundations</h3>
        <p class="muted">Modules 9–12. Complexity analysis and Big O, array and string
        problems, linked lists, stacks and queues with recursion.</p>
      </div>
      <div class="card">
        <h3>Phase 4 — DSA Core</h3>
        <p class="muted">Modules 13–16. Trees, graphs, hashing, sorting and searching
        algorithms.</p>
      </div>
      <div class="card">
        <h3>Phase 5 — DSA Advanced</h3>
        <p class="muted">Modules 17–20. Dynamic programming, greedy algorithms,
        backtracking, advanced graph algorithms.</p>
      </div>
      <div class="card">
        <h3>Phase 6 — Expert</h3>
        <p class="muted">Modules 21–24. Concurrency, testing with pytest, packaging,
        design patterns, performance, and a capstone project.</p>
      </div>
    </div>
  </section>

  {{SYLLABUS}}

  <section class="section">
    <h2>Why the code runs in the browser</h2>
    <p class="lead">
      Most people who quit a programming course quit during setup, before they have
      written anything. Here the Python interpreter is compiled to WebAssembly and loads
      with the page, so every example is editable and runnable where you are reading it.
      Change a line, press Run, see what breaks — which is how the material is meant to
      be used. Two honest limits: because it runs inside the browser tab there are no
      real operating-system threads and no <code>pip install</code>, so the few lessons
      that need those say so and show you how to run them on your own machine instead.
    </p>
  </section>

  <section class="section">
    <h2>If you are preparing for interviews</h2>
    <p class="lead">
      Phases 3 to 5 are the interview material — complexity analysis, the classic data
      structures, then dynamic programming, greedy and backtracking. The value of doing
      them here rather than grinding a problem list is that each pattern is explained
      before you are asked to apply it, so you learn why a solution works rather than
      memorising that it does.
    </p>
  </section>

  <section class="section">
    <h2>What it costs</h2>
    <p class="lead">
      <strong>Phase 1 is free</strong> with an account. One subscription then unlocks
      Phases 2–6 <em>and</em> the whole
      <a href="genai-testing-course.html">GenAI Testing course</a>: &#8377;499 for a
      month, &#8377;1,199 for three months, &#8377;3,999 for a year. Nothing renews
      automatically. <a href="pricing.html">Full pricing</a>.
    </p>
  </section>

</main>
"""


def build():
    return (head(path="python-dsa-course.html", title=TITLE, desc=DESC,
                og_title="Python & DSA course — 24 modules, code runs in your browser, Phase 1 free",
                 ld=LD)
            + BODY.replace("{{SYLLABUS}}", python_syllabus())
            + footer() + (TAIL % "python"))
