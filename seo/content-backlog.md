# Content backlog

One line per target. The weekly `content-slot` workflow takes the first line whose
status is `TODO`, opens it as a brief, and marks it `OPEN`. Set a line to `DONE`
once the page or FAQ entry is live.

These are not invented topics. Each is a question with observed search demand,
taken from Google People-Also-Ask boxes and related searches on the queries this
site targets, and each is something this course genuinely teaches — which is the
test a topic has to pass. Writing about things we do not teach would rank for
visitors we cannot help, which is worse than not ranking.

Format: `STATUS | where | question | angle`

`faq` means a new entry in `seo/pages_faq.py`. `page` means a new standalone page,
which needs a sitemap entry too.

---

DONE | faq | What is prompt injection, and how do I test for it? | Direct vs indirect; the indirect case is the one teams miss because the payload arrives inside a retrieved document and never passes through input validation.
DONE | faq | What is RAGAS and which metrics actually matter? | Faithfulness, answer relevancy, context precision and recall — what each one catches and what it misses. Name the trap: high faithfulness with bad retrieval still means a useless answer.
DONE | faq | What is Promptfoo and how do I write my first evaluation? | The YAML test case as the unit; why a declarative assertion beats an eyeballed output; how it lands in CI.
DONE | faq | How do you test an AI agent that calls tools? | Tool selection, refusals, loop and budget limits, hand-offs. The point most people miss: a refusal is a control working, not a bug.
DONE | faq | DeepEval or Promptfoo — which should I use? | An honest comparison, including when neither is the answer and a plain assertion is enough.
DONE | faq | What is Model Context Protocol (MCP), and what breaks in it? | What MCP standardises, and the failure modes it introduces — tool poisoning, over-broad tool grants, results the model trusts too readily.
DONE | faq | How do I write test cases for an LLM feature? | Moving from "expected result" to "acceptance criteria you can defend", with a worked example.
DONE | faq | What is LLM-as-a-judge, and when should you trust it? | Where it scales well, where it inherits the judge's blind spots, and why it needs human spot-checks rather than blind faith.
DONE | faq | How do you test an LLM application for bias? | Constructing paired prompts that differ only in the attribute under test, and why a single anecdote is not evidence.
DONE | faq | What is a golden dataset and how do I build one? | Size, sourcing, keeping it out of the prompt, and refreshing it when the product changes.
DONE | faq | How do I run LLM evaluations in CI without a huge bill? | Caching and recording responses, sampling, tiering suites by cost, and which checks need no model call at all.
DONE | page | AI testing career path: from manual tester to AI testing engineer | The strongest non-course page available to us — real demand ("How to become an AI/QA tester?", "Is manual testing a good career in 2026?") and we can answer it from experience rather than speculation. Needs honest salary talk or none at all.
DONE | page | ISTQB CT-AI vs a hands-on AI testing course | High-intent comparison. Must stay genuinely even-handed — CT-AI is the recognised certification and saying otherwise would be both false and obvious.

---

## Second batch — added 26 November, NOT yet SERP-verified

An honest flag on provenance, because it changes how much these are worth.

Every line above this point was taken from a live People-Also-Ask box or a
related-searches strip on a query this site targets. That is what made the
original thirteen trustworthy: the demand was observed, not assumed.

These were not. Web search was unavailable when they were written, so they come
from three weaker sources: gaps in what the FAQ already covers, questions the
course material already answers well, and the adjacent terms a reader of the
existing pages would plausibly search next. They are reasonable guesses by
someone who knows the subject — which is not the same thing as evidence.

**Before writing any of them, spend ten minutes checking.** Search the question,
look at whether Google shows a People-Also-Ask box for it, and see who already
ranks. Delete the ones with no visible demand rather than writing them; a page
answering a question nobody asks costs the same to write and earns nothing. Move
a line above this divider once you have confirmed it.

TODO | faq | How do I test a text-to-SQL or natural-language-to-query feature? | A rare case where correctness IS checkable: execute both queries and compare result sets rather than comparing SQL strings. Also the destructive-query refusal.
TODO | faq | What should an AI feature's acceptance criteria look like in a user story? | The three-band structure — must, must not, should — written as something a product owner and a tester can both sign.
TODO | faq | How do I test a chatbot that is supposed to refuse things? | Refusal testing as a first-class case: over-refusal is a defect too, and the measure is a paired suite of should-answer and should-refuse prompts.
TODO | faq | What is a regression test for a prompt, and how often does it break? | Why model version changes break suites that have not been touched, and pinning versions so a release is attributable.
TODO | faq | How do you load-test or performance-test an LLM feature? | Tokens rather than requests as the unit, streaming time-to-first-token versus total, cost per request as a performance metric with a budget.
TODO | faq | Who owns AI quality — QA, the ML team, or product? | An org question testers are actually asked. Answer it straight: the tester owns whether it is fit to release, which requires evidence nobody else is producing.
TODO | faq | How do I explain an AI defect to a developer who says "it's probabilistic"? | The distinction between variance within acceptable bounds and a defect, and how a paired-prompt or rate-based report ends the argument.
TODO | page | A worked example: testing a RAG application end to end | The highest-value page left. One application, one golden set, retrieval metrics, faithfulness, three adversarial findings, and an honest list of what the suite does not cover.
TODO | page | AI testing interview questions, with answers that are not wrong | High-intent and heavily searched, and most existing pages are content farms with answers a practitioner can see are wrong. Only worth doing if it is genuinely better.
