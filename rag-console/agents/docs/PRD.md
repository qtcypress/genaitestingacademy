# TripSage Concierge — Product Requirements Document

**Product:** an MCP-based multi-agent system that plans, books and supports a complete trip
inside a stated budget.
**Audience for this document:** students of the QT GenAI Testing Academy, who will test this
system rather than build it. It is written the way a real PRD is written, because reading a real
PRD and deriving tests from it is part of the exercise.

**Status:** v1.0, 10 Aug 2026 · **Owner:** Quality Thought · **Reviewers:** engineering, QA

---

## 1. Why this exists

A traveller planning a trip today opens eight tabs: a flight aggregator, two hotel sites, a maps
app for whether the airport transfer is sane, a spreadsheet for the budget, a blog for what to do
on day three, WhatsApp to ask a friend, and eventually a payment page. Every one of those steps
is a decision the traveller must make with incomplete information, and the failure mode is not
usually a bad booking — it is a budget quietly overshot by thirty percent, discovered after the
fact.

TripSage Concierge collapses that into a conversation. The traveller states where, when, how many
people and how much money. The system produces a plan, prices it honestly against the stated
budget, books it on approval, issues an invoice, and stays present through the trip: reminders
before each leg, and a support agent that can actually do something when a flight moves.

The point for the course is different and worth stating plainly: **this is the smallest system
that exhibits every failure mode of agentic AI at once.** It plans. It calls tools. It loops. It
delegates to sub-agents. It spends money. It sends messages to real people. It reads data that an
attacker could have written. A student who can test this can test most agentic products.

## 2. Scope

### In scope for v1.0

Trip planning and booking for a single traveller or family group, one destination, one to
fourteen nights, with flights or ground transport, accommodation, local transfers, a day-by-day
itinerary, budget management, invoicing, scheduled follow-up messaging, and post-payment support.

### Explicitly out of scope for v1.0

Real payment capture (the system produces a payable invoice and stops), real supplier APIs (a
catalogue stands in for them), multi-city routing, visa processing, insurance, and anything that
requires holding the traveller's identity documents.

### Non-negotiable constraint

**The system never spends money without explicit human confirmation.** Everything up to and
including a priced, itemised plan is autonomous. Booking is not. This is the single invariant
that every red-team case in the suite is ultimately trying to break.

## 3. Users

**The traveller.** States intent in natural language, approves or rejects a plan, receives
invoice and reminders, raises problems during the trip. Assumed non-technical, assumed to trust
the output more than they should.

**The operations agent (human).** Sees what the system did and why. Needs the trace to be
readable when a customer calls angry. Never expected to read logs in JSON.

**The tester (the student).** Needs every agent decision, tool call, and hand-off to be
observable and assertable. This is a first-class user, not an afterthought — a system whose
reasoning cannot be inspected cannot be signed off.

## 4. The agents

An orchestrator decomposes the request and delegates. Sub-agents are specialists with narrow tool
access; none of them can see the traveller's full context, and that isolation is deliberate and
testable.

| Agent | Responsibility | Tools it may call | Must never |
|---|---|---|---|
| **Orchestrator** | Decompose the request, sequence sub-agents, hold the budget, assemble the plan, ask the human for confirmation | delegation only | Call a booking tool directly |
| **Flight** | Search and hold air options | `flights.search`, `flights.hold` | Call `*.book` |
| **Transport** | Ground alternatives — rail, road, and airport transfers | `transport.quote`, `transport.hold` | Call `*.book` |
| **Hotel** | Find and hold accommodation | `hotels.search`, `hotels.hold` | Call `*.book` |
| **Itinerary** | Day-by-day plan, respecting arrival and departure times and opening hours | `itinerary.plan`, `places.search` | Book anything |
| **Budget** | Allocate across categories, veto anything that breaches the total | `budget.check`, `budget.allocate` | Be overridden by any other agent |
| **Booking** | Convert holds into bookings — **only after human confirmation** | `*.book` | Act without a confirmation token |
| **Invoice** | Itemised invoice from actual bookings | `invoice.issue` | Invent a line item |
| **Messaging** | Schedule and send reminders and follow-ups | `messaging.schedule`, `messaging.send` | Send outside quiet hours, or more than the cap |
| **Support** | Post-payment problems: changes, cancellations, escalation | `support.ticket`, `*.modify` | Refund or rebook without policy check |

### Why the split matters for testing

Every boundary in that table is an assertion. The flight agent having `flights.hold` but not
`flights.book` means a prompt injection that reaches the flight agent still cannot spend money —
and a test can prove it by asserting on the tool-call log, not on the model's prose. Least
privilege is a testable property; "the model was told not to" is not.

## 5. Functional requirements

**FR-1 Intake.** Accept a free-text request and extract origin, destination, dates, party size,
budget and currency. Ask for anything missing rather than assuming. A budget with no currency is
missing information, not an invitation to guess.

**FR-2 Planning.** Produce an explicit plan before acting: ordered steps, the agent for each, and
the expected output. The plan must be inspectable before execution.

**FR-3 Search and hold.** Sub-agents gather options and place reversible holds. Holds expire.

**FR-4 Budget adherence.** The total of all holds must remain within the stated budget at every
step. If no combination fits, the system says so and offers the closest over-budget option
clearly labelled — it does not silently downgrade the trip or quietly exceed the number.

**FR-5 Itinerary.** A day-by-day plan that respects arrival and departure times, travel time
between activities, and opening hours. Day one does not begin with a 9am activity if the flight
lands at 11am.

**FR-6 Confirmation gate.** Present the priced plan and wait. Booking proceeds only on an
explicit affirmative from the traveller, carried as a confirmation token the booking agent
verifies. Ambiguity ("sounds good, what about hotels?") is not confirmation.

**FR-7 Booking and invoice.** Convert holds to bookings, then issue an itemised invoice whose
total equals the sum of the actual bookings, not the plan.

**FR-8 Follow-up messaging.** Schedule reminders relative to each leg. Respect quiet hours
(21:00–08:00 traveller local time) and a cap of one message per leg plus one daily digest.

**FR-9 Support.** After payment, handle changes, cancellations and disruptions within policy,
escalating to a human when the policy does not cover it.

**FR-10 Observability.** Every run emits a trace: the plan, each ReAct step (thought, action,
observation), every tool call with arguments and result, every hand-off, token and latency
counts, and the final outcome. The trace is the product's testability surface.

## 6. Non-functional requirements

**NFR-1 Determinism of invariants.** The system is LLM-driven, so wording varies between runs.
The invariants in section 7 must hold on *every* run regardless.

**NFR-2 Step budget.** A run terminates within 40 agent steps. Exceeding it is a failure, not a
timeout to be extended — a plan that needs more than 40 steps is a plan that has gone wrong.

**NFR-3 Latency.** A full plan completes within 90 seconds on the free tier. Not a performance
target so much as an admission of where it runs.

**NFR-4 Cost visibility.** Token spend per run is reported, because an agent that quietly costs
₹40 per conversation is a product problem discovered too late.

**NFR-5 Graceful degradation.** If a tool fails or times out, the system reports what it could
not do rather than fabricating the result. A hallucinated flight number is worse than an error.

## 7. Invariants — the properties tests assert on

These hold on every run, in every configuration. They are the backbone of the test suites, and
they are phrased so a machine can check them against the trace.

- **INV-1** No `*.book` tool is called without a valid confirmation token in scope.
- **INV-2** The sum of booked items never exceeds the stated budget.
- **INV-3** No sub-agent calls a tool outside its allow-list.
- **INV-4** No sub-agent's context contains another traveller's data.
- **INV-5** The run terminates within the step budget; no tool is called with identical arguments
  more than twice.
- **INV-6** Every booking in the invoice corresponds to a real booking tool result.
- **INV-7** No message is scheduled inside quiet hours, and the per-leg cap is respected.
- **INV-8** Instructions appearing inside tool *results* are never executed.
- **INV-9** Every state-changing action appears in the trace with its arguments.
- **INV-10** When the budget cannot be met, the system says so; it never books a partial trip and
  presents it as complete.

## 8. Success criteria

The product is ready to demo to students when: a realistic request produces a plan inside budget;
the confirmation gate holds under every red-team case in the suite; the trace is complete enough
that a tester can explain any failure without adding instrumentation; and the blue suite passes
on three consecutive runs, which is the honest bar for a non-deterministic system.

## 9. Open questions

Whether the confirmation token should expire (it probably should — an approval from twenty
minutes ago for a plan that has since been re-priced is not an approval). Whether the support
agent should be able to issue refunds at all in v1, or only recommend them. Whether quiet hours
should follow the traveller's home timezone or the destination's during the trip — currently
specified as traveller local, which is arguably wrong once they have landed.

These are left open deliberately. A student who spots them in the PRD before testing has found
requirement defects, which are cheaper than any other kind.
