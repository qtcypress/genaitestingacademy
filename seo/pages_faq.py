"""The FAQ page — the AEO surface.

Every question here is one Google is already showing in a People-Also-Ask box for
the queries this site wants, copied from live SERPs rather than invented:

  "Which AI course is best for testers?"          "How to test your RAG system?"
  "Is there a GenAI course specifically for QA?"  "How can I detect hallucinations in an LLM?"
  "How to become an AI/QA tester?"                "How do I test and evaluate a RAG application?"
  "Where can I find an AI testing course in Hyderabad?"
  "Is manual testing a good career in 2026?"      "Which certification is best for GenAI?"
  "Which AI tool is best for QA tester?"

Answer-engine optimisation is not keyword stuffing with a question mark. An
assistant lifts one self-contained paragraph and attributes it, so each answer
here has to be true, useful on its own without the surrounding page, and specific
enough to be worth quoting. That also means answering the comparison questions
straight — including where this course is not the right choice. A page that says
"we are the best" on every question is the page an assistant learns to distrust,
and a reader can tell too.
"""
from build_pages import SITE, BRAND, head, TAIL, crumbs, ORG, WEBSITE, footer

TITLE = "AI Testing FAQ — Careers, RAG &amp; Certification | GenAITesting"
DESC = ("How to test a RAG system, detect LLM hallucinations, move from manual testing "
        "into AI testing, and how this compares with ISTQB CT-AI. Straight answers.")

# (question, answer_html). The answer_html is reused verbatim in the FAQPage
# schema with tags stripped, so the two can never drift apart.
QA = [
    ("Is there a GenAI testing course specifically for QA engineers?",
     """Yes, and the distinction matters. Most Generative AI courses teach you to
     <em>build</em> with a model — prompt it, chain it, ship a feature. A testing course
     starts from the opposite question: this thing already exists, how do I decide
     whether it is broken? That means evaluation instead of generation, adversarial
     cases instead of happy paths, and a definition of "correct" you can defend in a
     bug report. <a href="genai-testing-course.html">This course</a> is written for
     manual testers, automation testers and SDETs, and assumes no machine-learning
     background."""),

    ("Which AI testing course is best for testers?",
     """It depends on what you are missing, and it is worth being honest about the
     three different things on offer. If you need a recognised line on your CV,
     <strong>ISTQB CT-AI</strong> is the vendor-neutral certification hiring managers
     recognise, though it is an exam syllabus rather than hands-on practice. If you
     want breadth cheaply, the large marketplaces (Udemy, Coursera) have inexpensive
     video courses, but you are mostly watching someone else test. If what you lack is
     practice — actually deciding whether a real model's real output is a defect — then
     what you need is a course with a running application you can attack, because that
     judgement is the skill that does not transfer from video. Pick for the gap you
     actually have, and there is no reason not to combine a certification exam with a
     hands-on course."""),

    ("How do I test and evaluate a RAG application?",
     """Test the two halves separately before you test the whole, because a RAG system
     has two independent failure modes that look identical from the outside. First
     <strong>retrieval</strong>: for a set of questions with known-correct source
     documents, did the right chunks come back, and in what rank? That is measurable
     with ordinary precision and recall — no model judgement needed. Then
     <strong>generation</strong>: given the chunks that were retrieved, is the answer
     actually supported by them? This is faithfulness or groundedness, and it is where
     you check every claim in the answer against the cited text. The reason to split
     them is diagnostic: a wrong answer from good retrieval is a generation problem you
     fix with prompting, while a wrong answer from bad retrieval is a chunking,
     embedding or indexing problem, and prompt changes will never fix it. Then test the
     cases only a full system has: no relevant document exists (does it say so, or
     invent something?), contradictory sources, and a deliberately poisoned document in
     the knowledge base."""),

    ("How can I detect hallucinations in an LLM?",
     """There is no single check, so use layers. The strongest and cheapest is
     <strong>grounding</strong>: if the system is supposed to answer from provided
     documents, verify every factual claim in the output appears in those documents,
     and treat anything unsupported as a hallucination regardless of how plausible it
     reads. Where there is no source text, <strong>self-consistency</strong> is the
     practical substitute — ask the same question several times at non-zero
     temperature, and answers that change on facts that should not change are a signal,
     because a model's fabrications are far less stable than the things it actually
     knows. Third, an <strong>LLM-as-judge</strong> check scores the answer against a
     reference, which scales well but inherits the judge model's own blind spots, so it
     needs spot-checking by a human rather than being trusted outright. Finally, plant
     questions whose true answer is "I don't know" — questions about entities that do
     not exist. A system that confidently answers those will confidently answer
     anything, and that single test finds more real problems than any score."""),

    ("How do I red-team a RAG or LLM application?",
     """Attack the four surfaces separately. <strong>Prompt injection</strong> in the
     user's input: instructions telling the model to ignore its own rules. Then
     <strong>indirect injection</strong>, which is the one teams miss — the malicious
     instruction lives inside a document the system retrieves, so the attacker never
     talks to your application at all and nothing in your input validation ever sees
     it. Then <strong>data leakage</strong>: can you get the system to reveal its system
     prompt, another user's content, or a document you should not have access to? Then
     <strong>knowledge-base poisoning</strong>: add one plausible but false document and
     see how many users' answers change. Write these as ordinary test cases with
     expected results, and note that a refusal is a pass, not a failure — a lot of
     red-team reports are wrong because the tester recorded a working control as a
     bug."""),

    ("How do I become an AI testing engineer, coming from manual testing?",
     """The realistic order is: keep the testing judgement you already have, then add
     the three things that are missing. First <strong>enough Python to write an
     assertion</strong> — you do not need to be a developer, but every evaluation tool
     in this space is a Python library. Second <strong>evaluation technique</strong>:
     how to score an output that has no single right answer, how to build a ground-truth
     set, and what precision, recall and faithfulness mean in practice. Third
     <strong>the specific failure modes</strong> of these systems: hallucination,
     injection, retrieval failure, and agents that loop or call the wrong tool. Your
     existing instinct for where software breaks is the part that takes years and you
     already have it; the AI-specific layer on top is a matter of months, not years.
     Build something you can show — a small evaluation suite against a real
     application is worth more in an interview than any certificate on its own."""),

    ("Is manual testing still a good career in 2026?",
     """Manual testing as "execute this documented script by hand" has been shrinking
     for years and AI has accelerated that, because generating and running routine
     checks is exactly what these tools are good at. But the judgement underneath
     manual testing — deciding what is worth testing, recognising that an output is
     wrong in a way no specification anticipated, knowing which bug actually matters —
     has become <em>more</em> valuable, not less, precisely because AI systems fail in
     ways that require a human to notice. The honest answer is that the job title is at
     risk and the skill is not. Testers who add evaluation technique and enough coding
     to automate their own checks are in demand; testers who only run scripts by hand
     are competing with software that does it for free."""),

    ("Which certification is best for GenAI testing?",
     """For vendor-neutral recognition, <strong>ISTQB's Certified Tester AI Testing
     (CT-AI)</strong> is the one most widely recognised by employers and the one to
     name if a job description asks for a certification. Cloud providers also offer AI
     certifications, but those are oriented to building and deploying on their own
     platform rather than testing. Certificates from a specific course, including
     <a href="verify.html">the three levels awarded here</a>, are evidence you did the
     work rather than an industry credential, which is why the number on ours is
     publicly checkable — it is worth exactly as much as the work behind it, and no
     more. In practice, most people who get hired have both a recognised certification
     and something they built that they can talk through."""),

    ("Where can I find an AI testing course in Hyderabad?",
     """Several institutes in Hyderabad run classroom AI testing courses, and it is
     worth asking any of them one question before paying: do you test a real running
     AI application during the course, or only watch demonstrations? That single
     question separates the useful ones from the rest.
     <a href="genai-testing-course.html">This course</a> is run from Hyderabad and is
     delivered entirely online, so it is the same material whether you are in the city
     or not — you work two hosted applications from your browser, at your own pace,
     with nothing to install. Pricing is in rupees and Phase 1 is free, so you can see
     the material before deciding."""),

    ("Do I need to know Python before starting AI testing?",
     """Not to start, but you will need some. The first modules are conceptual and
     hands-on through a browser interface, so you can begin with no code at all. By the
     time you reach automation, every tool in this space — Promptfoo, DeepEval, RAGAS —
     is driven from Python, and you will need to read and write functions, loops and
     assertions. You do not need object-oriented design, algorithms or a computer
     science degree. That is why the
     <a href="python-dsa-course.html">Python and DSA track</a> is included in the same
     subscription rather than sold separately: the amount of Python a tester needs is
     roughly the first two phases of it."""),

    ("Is any of the course free?",
     """Yes, and it is a real free tier rather than a trailer. <strong>Module 1 of the
     GenAI Testing course</strong> and the <strong>whole of Phase 1 of the Python and
     DSA course</strong> (modules 1 to 4) are free once you create an account — no card,
     nothing to cancel. Everything after that needs a subscription: &#8377;499 for a
     month, &#8377;1,199 for three months or &#8377;3,999 for a year, and one
     subscription covers both courses. Nothing renews automatically, and buying again
     while you still have time left adds days rather than replacing them."""),

    ("Is the certificate verifiable by an employer?",
     """Yes. Each certificate carries a unique number, and anyone — an employer, a
     recruiter, anyone you send the link to — can type that number into
     <a href="verify.html">the verification page</a> and see whether it is real,
     without an account and without contacting us. This matters because an image file
     proves nothing; a number someone else can independently check is the only form of
     certificate that carries weight."""),

    ("Which AI tool is best for a QA tester to learn first?",
     """If you are testing AI systems, learn an <strong>evaluation framework</strong>
     before anything else — Promptfoo is the easiest starting point because its test
     cases are readable YAML, while DeepEval and RAGAS go deeper on RAG-specific
     metrics like faithfulness and context precision. If instead you mean using AI to
     help with ordinary testing work, the highest-value habit is using a coding
     assistant to draft and maintain your test code, with the discipline of reviewing
     every line it produces — an unreviewed generated test that passes for the wrong
     reason is worse than no test, because it reports safety you do not have. Learn the
     evaluation framework first either way: it is the skill that is specific to this
     work and hardest to pick up on the job."""),
]


def strip_tags(html):
    """The schema needs the same words as the page, without the markup."""
    out, depth = [], 0
    for ch in html:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return " ".join("".join(out).split())


FAQ_LD = {
    "@type": "FAQPage",
    "@id": SITE + "/faq.html#faq",
    "mainEntity": [{
        "@type": "Question",
        "name": q,
        "acceptedAnswer": {"@type": "Answer", "text": strip_tags(a)},
    } for q, a in QA],
}

LD = {"@context": "https://schema.org", "@graph": [
    ORG, WEBSITE, FAQ_LD,
    crumbs([("Home", ""), ("FAQ", "faq.html")]),
]}


def build():
    items = "\n".join(
        f"""    <section class="faq-item">
      <h2>{q}</h2>
      <div class="faq-a">{a}</div>
    </section>""" for q, a in QA)

    body = f"""
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Questions</p>
    <h1>AI and GenAI testing<br><span class="accent">questions, answered straight</span></h1>
    <p>
      These are the questions people actually search for before they choose a course,
      including the ones where the honest answer is "not this one". Where a comparison
      comes up, it is a real comparison.
    </p>
  </div>
</header>

<main class="wrap section">
{items}

  <section class="section card" style="margin-top:32px">
    <h2 style="margin-top:0">Still deciding?</h2>
    <p class="muted">
      Both courses have a free part you can work through before paying anything:
      <a href="genai-testing-course.html">GenAI Testing</a> opens Module 1, and
      <a href="python-dsa-course.html">Python &amp; DSA</a> opens all of Phase 1.
      An account is all that is needed.
    </p>
    <p style="margin-bottom:0"><a class="btn btn-primary" href="index.html?next=app.html">Create a free account</a></p>
  </section>
</main>
"""
    return head(path="faq.html", title=TITLE, desc=DESC,
                og_title="AI & GenAI testing FAQ — careers, RAG testing, certification",
                ld=LD) + body + footer() + (TAIL % "faq")
