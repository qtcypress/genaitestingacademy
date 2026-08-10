# Test Plan and Strategy — TripSage RAG and TripSage Concierge

**Covers:** the four RAG versions already in the console, the fifth version running on a real LLM,
and the MCP multi-agent Concierge.
**Status:** v1.0, 10 Aug 2026 · **Owner:** QA · **Referenced by:** the blue, red and observability
suites in `agents/tests/`

---

## 1. What makes this hard, stated up front

A test plan for a deterministic system asserts on outputs. Neither system here is deterministic.
The RAG versions 1–4 are — they use local TF-IDF and produce the same answer every time — but
version 5 and the entire Concierge run on a language model, so the same input produces different
prose on every run, and sometimes a different route through the system.

Pretending otherwise produces a suite that fails randomly, gets ignored within a fortnight, and
is eventually deleted. So this plan does two things differently from a conventional one.

**It asserts on invariants and traces, not on wording.** "The answer mentions 23 kg" is a brittle
assertion. "No `*.book` tool was called without a confirmation token in scope" is a property of
the run that either held or did not, and it is checkable in the trace regardless of how the model
phrased itself.

**It reports weak passes.** A case can avoid misbehaving for the wrong reason — a PII extraction
that returned nothing because retrieval was empty, rather than because a guardrail fired. A
binary pass/fail hides that; the suites here report `pass`, `weak` and `fail`, and a `weak` is a
prompt to investigate rather than a green tick.

## 2. Scope

**In scope.** Retrieval quality and grounding; guardrails against injection, jailbreak, PII
extraction and bias; knowledge-base poisoning and indirect prompt injection; LLM provider
integration and fallback; agent planning quality; orchestration and delegation; tool-call
correctness and least privilege; budget adherence; the confirmation gate; invoicing accuracy;
messaging policy; ReAct loop behaviour and termination; observability and trace completeness.

**Out of scope.** Real supplier integrations, payment capture, load and soak testing, penetration
testing of the hosting platform, and model-level alignment research. We are testing a product
built on a model, not the model.

## 3. Risk assessment — what drives the effort allocation

| # | Risk | Impact | Likelihood | Where it is covered |
|---|---|---|---|---|
| R1 | Agent books and spends without confirmation | Severe — real money, real trust | Medium | RT-AG-01..05, INV-1 |
| R2 | Budget silently exceeded | High — the core promise broken | High | RT-AG-06..08, INV-2 |
| R3 | Injection via tool results or tool descriptions | Severe — full control of agent behaviour | Medium | RT-MCP-01..06, INV-8 |
| R4 | Knowledge-base poisoning feeds false facts | High — acted on at an airport counter | High | RT-RP-\*, INV covered in RAG suites |
| R5 | Runaway loop burns tokens and time | Medium — cost, not safety | High | RT-LOOP-01..04, INV-5 |
| R6 | Cross-agent data leakage | Severe — regulatory | Low | RT-AG-09, INV-4 |
| R7 | Invoice does not match bookings | High — finance and disputes | Medium | BT-INV-\*, INV-6 |
| R8 | Messaging spams or wakes the traveller | Medium — churn | Medium | BT-MSG-\*, RT-MSG-\*, INV-7 |
| R9 | Trace incomplete, failures undiagnosable | High — everything else becomes unfalsifiable | Medium | OB-\* |
| R10 | Hallucinated flights, hotels or prices | High | Medium | BT-AG-\*, NFR-5 |

Effort follows this table. Roughly half the red-team cases target R1–R3, because those are the
ones where a failure is a headline rather than a bug report.

## 4. Test levels

**Component.** Individual tools behave: `budget.check` rejects an over-budget allocation,
`flights.search` returns only real catalogue entries, `messaging.schedule` refuses quiet hours.
Deterministic, fast, run on every change.

**Agent.** A single agent with its allow-list, given a task, calls the right tools and stays
inside its privileges. Deterministic in the tool dimension even when the prose varies.

**Orchestration.** The full multi-agent run: plan produced, sub-agents sequenced, budget held,
confirmation gate respected, invoice reconciled. Non-deterministic; asserted on invariants.

**System with a human in the loop.** The confirmation gate specifically, including the ambiguous
replies that must *not* count as approval.

**Adversarial.** The red-team suite, run against every level.

## 5. Test strategy by area

### 5.1 Retrieval and grounding (RAG v1–v5)

Already implemented in the console. Blue suite covers positive, negative, edge, relevancy,
accuracy, factuality and faithfulness. Red suite covers injection, jailbreak, hallucination, PII,
bias and poisoning. Retrieval is scored separately with Hit@1, Hit@k and MRR against a labelled
set, because a retrieval failure and a generation failure need different fixes and a single
end-to-end pass rate hides which one you have.

Poisoning cases are always run twice — clean and poisoned — because the clean run is the ground
truth against which the poisoned run is judged.

### 5.2 LLM provider integration (v5)

Provider selection, key handling, fallback and failure. Explicit cases for: no key configured;
invalid key; provider returns 429; provider returns a malformed response; provider times out;
local Ollama unreachable. In every one the required behaviour is an honest error, never a
fabricated answer. Additionally: the same question asked five times must stay factually
consistent even though the wording changes — inconsistency across runs is a defect worth
reporting even when each individual answer looks fine.

### 5.3 Agent planning

Assert the plan exists before execution, decomposes into steps that map to real capabilities,
orders dependencies correctly (accommodation cannot be planned before dates are known), and does
not include steps for information it already has. Plan quality is scored by rubric rather than
exact match, and the rubric is published so a student can disagree with it.

### 5.4 Orchestration and delegation

Assert each sub-agent is invoked with the context it needs and nothing more; results flow back;
the orchestrator does not do sub-agent work itself; and no sub-agent calls a tool outside its
allow-list. Least privilege is checked against the tool-call log, which cannot be talked out of.

### 5.5 ReAct behaviour

Every step must have a thought, an action and an observation, in that order. Assert: no action
without a preceding thought; no fabricated observation (every observation traces to a real tool
result); the agent revises its plan when an observation contradicts it, rather than continuing;
and repeated identical actions are detected and stopped.

### 5.6 Loop and termination

The step budget is a hard limit. Assert termination within it, detection of identical repeated
tool calls, and sane behaviour when a tool consistently fails — retry with backoff a bounded
number of times, then report, never retry forever.

### 5.7 Observability

Assert the trace contains the plan, every step, every tool call with arguments and results, every
hand-off, token and latency counts, and the terminal outcome. A run that succeeds but produces an
incomplete trace fails the observability suite, because an unobservable success is indistinguishable
from luck.

## 6. Entry and exit criteria

**Entry.** The service is deployed and healthy; the catalogue is seeded; at least one LLM provider
is reachable; the trace endpoint returns a well-formed trace for a trivial request.

**Exit.** All blue-team cases pass on **three consecutive runs** — the honest bar for a
non-deterministic system, since a single green run proves less than it appears to. Every red-team
case is either passed or has an accepted, documented risk with a named owner. No invariant in PRD
section 7 is violated in any run. Observability cases pass at 100%, because they are deterministic
and there is no excuse.

## 7. Environments and data

Testing runs against the deployed Render service. The catalogue is synthetic and fixed, so
prices and availability do not drift underneath a test run. Poisoned documents live in a separate
folder that is only loaded when poisoned mode is selected, and are prefixed `POISON_` so
provenance is visible in every trace.

No real personal data is used anywhere. The PII cases use obviously fictional identities, because
a test suite that contains real personal data has itself become a data-protection problem.

## 8. What we are choosing not to do, and why

We are not asserting exact answer text anywhere in the LLM-driven suites. We are not chasing 100%
on the red suite — several failures are genuine, known properties of the design being taught, and
"fixing" them by tightening thresholds would remove the lesson. We are not running the agent
suites on every commit; they cost tokens and time, so they run on demand and before a release.

## 9. Reporting

Each run produces the pass/weak/fail tally, the invariant violations if any, the trace for every
failure, and token and latency totals. A failure without its trace is not a reportable defect —
the trace is what turns "the agent did something odd" into a bug someone can fix.
