"""ISTQB CT-AI compared with a hands-on course.

High-intent comparison query, and the one page on this site with the strongest
temptation to lie. The backlog line was explicit: it must stay genuinely
even-handed, because CT-AI is the recognised certification and saying otherwise
would be both false and obvious to the reader who typed the query.

So the page says plainly that if what you need is a credential, CT-AI is the
thing to buy and this course is not a substitute for it. A comparison page that
concludes in favour of its own author on every axis is one a reader discounts
entirely, and an assistant learns not to quote.

Deliberately absent: exam fee, question count, pass mark, syllabus version,
accredited provider list. Those are exactly the facts that change, this page
cannot verify them, and a stale number on a page about a certification is worse
than no number — the reader books an exam on it. Every one of them is one click
away at istqb.org, which is where the page sends them.
"""
from build_pages import SITE, BRAND, head, TAIL, crumbs, ORG, WEBSITE, footer

TITLE = "ISTQB CT-AI vs a Hands-On AI Testing Course | GenAITesting"
DESC = ("An even-handed comparison: what the ISTQB AI Testing certification gives you, "
        "what a hands-on course gives you, and which to choose for which problem.")

# The comparison itself is the quotable unit, so it is also the schema. Each
# answer stands alone, which is what lets an assistant lift one and attribute it.
QA = [
    ("Is ISTQB CT-AI worth it?",
     """It depends entirely on whether your problem is credibility or capability. CT-AI
     is ISTQB's specialist certification in AI testing, it is vendor-neutral, and it is
     the AI testing qualification that hiring managers and tender documents actually
     recognise — which is a real and specific kind of value. If you need a line on a CV
     that a recruiter screening on keywords will match, or you work somewhere that
     requires certified testers on a bid, it is the thing to buy and nothing else
     substitutes for it. What it is not is practice. It is a syllabus and a
     multiple-choice exam, so passing it demonstrates that you understand the
     vocabulary and the concepts, not that you have ever decided whether a real model's
     real output was a defect."""),

    ("What is the difference between CT-AI and a hands-on AI testing course?",
     """They answer different questions, which is why the comparison is less competitive
     than it looks. CT-AI answers "can this person discuss AI quality characteristics,
     ML performance metrics and the testing concerns of an AI system in standard
     terminology?" — and it answers that in a form an employer can verify. A hands-on
     course answers "has this person actually attacked a running application, found
     something, and written it up?" — and it answers that in a form an employer can
     read. The first is recognised and portable; the second is demonstrable but needs
     you to show your work. Neither covers the other's ground."""),

    ("Which should I do first?",
     """Start with whichever closes the gap you actually have. If applications are not
     getting past screening, the certification is the bottleneck and the practice will
     not fix it. If you are reaching interviews and then struggling with "tell me about
     a time you tested an AI feature", no certification will fix that, and only having
     done it will. One useful sequence if you intend to do both: the practical work
     first, then the exam. The syllabus is considerably easier to absorb once you have
     seen the things it names, and the concepts stop being abstractions you memorise."""),

    ("Can a course replace the certification?",
     """No, and this is the part worth being direct about. A certificate issued by a
     training provider is not an ISTQB certification, and nobody in the industry treats
     the two as equivalent. If an employer or a tender asks for CT-AI, the only thing
     that satisfies it is CT-AI, from an accredited provider, with the exam passed. Any
     course page claiming otherwise is selling you something."""),

    ("Does CT-AI cover LLMs and generative AI?",
     """Partly, and this is the most important thing to check for yourself before
     booking. The syllabus was built around machine-learning systems broadly —
     classifiers, model performance metrics, data quality, bias, the testing concerns of
     ML pipelines — and much of that generalises. Testing a RAG retrieval layer,
     evaluating generated text for groundedness, defending against prompt injection, and
     testing an agent that calls tools are newer concerns that move faster than any
     syllabus revision cycle can. ISTQB does revise its syllabi, so the honest answer
     is: read the current syllabus at istqb.org, which is published free, and see what
     is in the version on offer today rather than trusting any third-party summary of
     it, including this one."""),

    ("How much does CT-AI cost and how long does it take?",
     """This page does not quote a fee, a question count or a pass mark on purpose.
     Exam prices vary by country and by accredited provider, and all of these details
     change — a stale figure on a page about a certification is worse than no figure,
     because someone budgets or books on it. Go to istqb.org for the current syllabus
     and the list of accredited providers in your region, and get the fee from the
     provider you would actually sit with. What can be said is the shape: it is a
     foundation-level specialist certification, the syllabus is readable in evenings
     rather than months, and the main cost for most people is the exam rather than the
     study."""),
]

ARTICLE = {
    "@type": "Article",
    "@id": SITE + "/istqb-ct-ai-vs-hands-on-course.html#article",
    "headline": "ISTQB CT-AI vs a hands-on AI testing course",
    "description": DESC,
    "author": {"@id": SITE + "/#org"},
    "publisher": {"@id": SITE + "/#org"},
    "inLanguage": "en",
    "about": ["ISTQB CT-AI", "AI testing certification", "Software testing training"],
}


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
    "@id": SITE + "/istqb-ct-ai-vs-hands-on-course.html#faq",
    "mainEntity": [{
        "@type": "Question",
        "name": q,
        "acceptedAnswer": {"@type": "Answer", "text": strip_tags(a)},
    } for q, a in QA],
}

LD = {"@context": "https://schema.org", "@graph": [
    ORG, WEBSITE, ARTICLE, FAQ_LD,
    crumbs([("Home", ""), ("ISTQB CT-AI compared", "istqb-ct-ai-vs-hands-on-course.html")]),
]}

HEAD_BODY = """
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Comparison</p>
    <h1>ISTQB CT-AI<br><span class="accent">compared with a hands-on course</span></h1>
    <p>
      Written by people who sell one of the two, which you should factor in. The short
      version: if you need a recognised credential, buy the certification — this course
      is not a substitute for it, and anyone telling you otherwise is selling you
      something. If you need to be able to do the work, a syllabus will not get you
      there. They are different purchases for different problems.
    </p>
  </div>
</header>

<main class="wrap section">

  <section class="section">
    <h2>Side by side</h2>
    <div class="grid grid-2">
      <div class="card">
        <h3>ISTQB CT-AI</h3>
        <p class="muted">A vendor-neutral certification with an exam and a published
        syllabus. <strong>Recognised</strong> — the name means something to recruiters,
        HR filters and tender documents, which is its central advantage and not a small
        one. Portable across employers and countries. Tests whether you know the
        concepts and the standard vocabulary. Does not involve testing a running
        application, and does not ask you to produce anything.</p>
      </div>
      <div class="card">
        <h3>A hands-on course</h3>
        <p class="muted">Practice against applications you attack. Produces artefacts
        you can show — an evaluation suite, a golden dataset, a documented finding.
        <strong>Not recognised</strong> in the way a certification is: a provider's
        certificate carries only the weight of the work behind it, which means you have
        to show the work. Covers newer ground, because it is not bound to a revision
        cycle.</p>
      </div>
    </div>
  </section>

  <section class="section">
    <h2>Doing both is the common answer</h2>
    <p class="lead">
      There is no tension between them and the budgets are different in size. A useful
      sequence, if you intend to do both, is the practical work first and the exam
      second: the syllabus is much easier to absorb once you have seen the things it
      names, and the concepts stop being abstractions to memorise. The reverse order
      works too and simply costs more study time.
    </p>
  </section>
"""

TAIL_BODY = """
  <section class="section">
    <h2>Where to check the facts</h2>
    <p class="lead">
      Deliberately absent from this page: the exam fee, the number of questions, the
      pass mark, the current syllabus version and the list of accredited providers.
      Those are the details that change, and a stale number on a page about a
      certification is worse than none because somebody budgets or books on it. All of
      them are published at <strong>istqb.org</strong>, where the syllabus itself is
      free to download. Read the current one before paying for anything, including this
      course.
    </p>
  </section>

  <section class="section">
    <h2>If the practical side is your gap</h2>
    <p class="lead">
      <a href="genai-testing-course.html">The GenAI testing course</a> is the hands-on
      half: RAG evaluation, adversarial testing, agent behaviour, and three
      <a href="projects.html">capstone applications</a> to attack rather than read
      about. <a href="faq.html">The FAQ</a> answers the specific technical questions,
      and <a href="ai-testing-career-path.html">the career path page</a> covers what to
      learn in what order. Phase 1 is free, so you can judge the material before
      deciding how to spend anything.
    </p>
  </section>

</main>
"""


def build():
    items = "\n".join(
        f"""    <section class="faq-item">
      <h2>{q}</h2>
      <div class="faq-a">{a}</div>
    </section>""" for q, a in QA)

    body = (HEAD_BODY
            + '\n  <section class="section">\n    <h2>The questions people actually ask</h2>\n'
            + items + "\n  </section>\n"
            + TAIL_BODY)

    return (head(path="istqb-ct-ai-vs-hands-on-course.html", title=TITLE, desc=DESC,
                 og_title="ISTQB CT-AI vs a hands-on AI testing course — an even-handed comparison",
                 ld=LD)
            + body + footer() + (TAIL % "istqb"))
