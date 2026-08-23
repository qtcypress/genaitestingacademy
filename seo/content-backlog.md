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

TODO | faq | What is prompt injection, and how do I test for it? | Direct vs indirect; the indirect case is the one teams miss because the payload arrives inside a retrieved document and never passes through input validation.
TODO | faq | What is RAGAS and which metrics actually matter? | Faithfulness, answer relevancy, context precision and recall — what each one catches and what it misses. Name the trap: high faithfulness with bad retrieval still means a useless answer.
TODO | faq | What is Promptfoo and how do I write my first evaluation? | The YAML test case as the unit; why a declarative assertion beats an eyeballed output; how it lands in CI.
TODO | faq | How do you test an AI agent that calls tools? | Tool selection, refusals, loop and budget limits, hand-offs. The point most people miss: a refusal is a control working, not a bug.
TODO | faq | DeepEval or Promptfoo — which should I use? | An honest comparison, including when neither is the answer and a plain assertion is enough.
TODO | faq | What is Model Context Protocol (MCP), and what breaks in it? | What MCP standardises, and the failure modes it introduces — tool poisoning, over-broad tool grants, results the model trusts too readily.
TODO | faq | How do I write test cases for an LLM feature? | Moving from "expected result" to "acceptance criteria you can defend", with a worked example.
TODO | faq | What is LLM-as-a-judge, and when should you trust it? | Where it scales well, where it inherits the judge's blind spots, and why it needs human spot-checks rather than blind faith.
TODO | faq | How do you test an LLM application for bias? | Constructing paired prompts that differ only in the attribute under test, and why a single anecdote is not evidence.
TODO | faq | What is a golden dataset and how do I build one? | Size, sourcing, keeping it out of the prompt, and refreshing it when the product changes.
TODO | faq | How do I run LLM evaluations in CI without a huge bill? | Caching and recording responses, sampling, tiering suites by cost, and which checks need no model call at all.
TODO | page | AI testing career path: from manual tester to AI testing engineer | The strongest non-course page available to us — real demand ("How to become an AI/QA tester?", "Is manual testing a good career in 2026?") and we can answer it from experience rather than speculation. Needs honest salary talk or none at all.
TODO | page | ISTQB CT-AI vs a hands-on AI testing course | High-intent comparison. Must stay genuinely even-handed — CT-AI is the recognised certification and saying otherwise would be both false and obvious.
