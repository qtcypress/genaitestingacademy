-- ============================================================
-- GenAITesting — Migration 03
-- Seeds the "GenAI Testing" course, its 16 modules with lesson
-- plans, and re-files the existing materials into those modules.
-- Safe to re-run (upserts on stable ids).
-- ============================================================

insert into public.courses (id, code, title, subtitle, description, sort_order, published)
values ('c0000000-0000-4000-8000-000000000001', 'GENAI-TESTING',
  'GenAI Testing',
  'Manual & automation testing for LLM, RAG, agent and multi-agent applications',
  'A complete practitioner track for software testers moving into Generative AI. Covers LLM fundamentals, prompt engineering, red-team testing, RAG and multi-agent systems, and automation with Promptfoo, DeepEval and RAGAS — finishing with two capstone projects and three levels of certification.',
  10, true)
on conflict (id) do update set
  code=excluded.code, title=excluded.title, subtitle=excluded.subtitle,
  description=excluded.description, published=excluded.published;

-- ---------- 16 MODULES, each with objectives + lesson-plan topics ----------
insert into public.modules (course_id, number, title, summary, objectives, topics, duration_hours, sort_order, published) values

('c0000000-0000-4000-8000-000000000001', 1, 'Introduction to Gen AI',
 'What generative AI is, how it differs from traditional software, and why it needs a different testing mindset.',
 '["Explain what generative AI is in plain language to a non-technical stakeholder","Describe how GenAI differs from deterministic software and what that means for testing","Identify the main GenAI application types a tester will encounter","Recognise where GenAI adds risk as well as value"]'::jsonb,
 '["AI, ML, deep learning and generative AI — how the terms nest","Discriminative vs generative models, with examples","The six common GenAI application shapes: chat, summarise, extract, classify, generate, agent","Why non-determinism breaks traditional test design","Benefits, limitations and real-world failure stories","Responsible AI: bias, privacy, transparency, accountability"]'::jsonb,
 3, 10, true),

('c0000000-0000-4000-8000-000000000001', 2, 'Basics of LLM',
 'How large language models actually work — tokens, context, parameters — and the failure modes that follow from the architecture.',
 '["Describe next-token prediction and why it produces fluent but sometimes wrong output","Explain tokens, context windows and their practical limits","Tune temperature, top-p and max tokens deliberately rather than by guesswork","Predict which failures come from the model and which from the application around it"]'::jsonb,
 '["Next-token prediction and why an LLM never looks anything up","Tokenisation: why cost, limits and truncation are measured in tokens","Context window, context stuffing and the lost-in-the-middle effect","Decoding parameters: temperature, top-p, top-k, max tokens, stop sequences","Hallucination, stale knowledge, no access to private data","Fine-tuning vs RAG vs prompting — what each one actually changes","System vs user vs assistant roles"]'::jsonb,
 4, 20, true),

('c0000000-0000-4000-8000-000000000001', 3, 'Prompt Engineering',
 'Designing, versioning and testing prompts as production artefacts rather than throwaway text.',
 '["Write clear, constrained prompts that produce testable output","Apply zero-shot, few-shot and chain-of-thought techniques appropriately","Force structured output and validate it","Treat a prompt as versioned code with its own regression tests"]'::jsonb,
 '["Anatomy of a prompt: role, task, context, constraints, output format","Zero-shot, few-shot and chain-of-thought prompting","Structured output: JSON schemas and validating what comes back","Delimiters, guardrail instructions and refusal handling","Prompt versioning, diffing and regression testing","Common anti-patterns: vague asks, conflicting instructions, overstuffed context","Hands-on: rewriting a weak prompt into a testable one"]'::jsonb,
 4, 30, true),

('c0000000-0000-4000-8000-000000000001', 4, 'Red Team Testing',
 'Adversarial testing of GenAI applications — deliberately making a system misbehave, and documenting it responsibly.',
 '["Build an adversarial test plan for an LLM feature","Execute prompt-injection, jailbreak and data-exfiltration attempts methodically","Assess severity in the context of the application domain","Report findings in a way that leads to a fix"]'::jsonb,
 '["Threat modelling a GenAI feature: what an attacker actually wants","Prompt injection: direct, indirect and via retrieved content","Jailbreaks, role-play attacks and instruction-hierarchy bypass","Sensitive-data leakage and system-prompt extraction","Harmful, biased and unsafe output in high-risk domains","Severity rating, evidence capture and responsible disclosure","Case study: red-teaming a real medical-information AI search"]'::jsonb,
 5, 40, true),

('c0000000-0000-4000-8000-000000000001', 5, 'Capstone Project — Requirements PRD, Test Plan, Test Cases & Reports',
 'The complete manual-testing documentation set for a GenAI application, produced end to end.',
 '["Turn a vague GenAI feature idea into a testable requirements document","Write a test plan that accounts for non-deterministic behaviour","Author manual test cases with acceptance criteria that survive rewording","Produce a defect and summary report a stakeholder can act on"]'::jsonb,
 '["Reading a PRD for a GenAI feature and finding the untestable requirements","Acceptance criteria for probabilistic output","Test plan structure: scope, risks, approach, entry/exit criteria","Writing manual test cases: positive, negative, adversarial, edge","Defect reporting for AI behaviour — reproducibility and evidence","Test summary and sign-off reporting","Deliverable: a full documentation pack for one GenAI feature"]'::jsonb,
 6, 50, true),

('c0000000-0000-4000-8000-000000000001', 6, 'Promptfoo — Evaluation',
 'Automating prompt and model evaluation with Promptfoo: declarative test cases, assertions and CI integration.',
 '["Set up Promptfoo and run a first evaluation suite","Write deterministic and model-graded assertions","Compare prompts and models side by side on the same dataset","Wire evaluations into CI so regressions are caught on every change"]'::jsonb,
 '["Installing Promptfoo and the config file layout","Providers, prompts and test cases in promptfooconfig.yaml","Assertion types: contains, equals, regex, javascript, llm-rubric, similar","Datasets and CSV-driven test cases","Side-by-side prompt and model comparison, and reading the matrix","Thresholds, caching and cost control","Running evaluations in CI and failing the build on regression"]'::jsonb,
 6, 60, true),

('c0000000-0000-4000-8000-000000000001', 7, 'Promptfoo — Red Team Testing',
 'Using Promptfoo''s red-team tooling to generate and run adversarial suites at scale.',
 '["Configure and run an automated red-team scan","Select attack plugins and strategies that fit the application''s risk profile","Interpret a red-team report and separate real risk from noise","Re-run scans as a regression gate after mitigations"]'::jsonb,
 '["Automated vs manual red teaming — what each catches","Setting up promptfoo redteam: purpose, plugins, strategies","Attack plugins: harmful content, PII, injection, hijacking, overreliance","Strategies: jailbreak, multi-turn, encoding, iterative refinement","Reading the report: severity, pass rate, per-plugin breakdown","Triaging false positives without dismissing real findings","Continuous red teaming as a release gate"]'::jsonb,
 5, 70, true),

('c0000000-0000-4000-8000-000000000001', 8, 'Python',
 'The Python a GenAI tester actually needs — enough to write real automation, not a full language course.',
 '["Write clean Python functions, handle errors and manage dependencies","Work with JSON, environment variables and API clients","Call LLM APIs and process their responses safely","Structure a small automation project others can run"]'::jsonb,
 '["Environments and dependencies: venv, pip, requirements","Core syntax refresher: types, collections, comprehensions, functions","Working with JSON and validating shapes","Exceptions, retries, timeouts and rate-limit handling","HTTP clients and calling LLM APIs","Secrets and configuration via environment variables","Project layout, logging and reusable helpers"]'::jsonb,
 6, 80, true),

('c0000000-0000-4000-8000-000000000001', 9, 'Pytest',
 'Turning GenAI evaluations into a real test suite with pytest — fixtures, parametrisation and CI reporting.',
 '["Structure a pytest suite for non-deterministic systems","Use fixtures and parametrisation to cover many cases cheaply","Mark, skip and re-run flaky or expensive LLM tests deliberately","Produce CI-friendly reports from an evaluation suite"]'::jsonb,
 '["pytest basics: discovery, assertions, test layout","Fixtures, scopes and sharing expensive LLM clients","Parametrisation for dataset-driven evaluation","Markers, skipping, xfail and handling genuinely flaky AI tests","Mocking and recording LLM responses for fast, cheap runs","Reporting: junit-xml, HTML reports, coverage of prompt paths","Integrating pytest-based evaluations into CI"]'::jsonb,
 5, 90, true),

('c0000000-0000-4000-8000-000000000001', 10, 'RAG Development',
 'Building a retrieval-augmented generation pipeline so you understand every seam where it can fail.',
 '["Build a working RAG pipeline from documents to grounded answers","Explain and tune chunking, embedding and retrieval choices","Diagnose whether a bad answer came from retrieval or from generation","Design test data that exposes retrieval weaknesses"]'::jsonb,
 '["The four steps: chunk, embed, retrieve, generate","Chunking strategies: size, overlap, structure-aware splitting","Embeddings and vector stores in practice","Similarity search, top-k, and why more context is not always better","Re-ranking and hybrid (keyword + vector) retrieval","Grounding prompts and citation of sources","Failure taxonomy: retrieval miss, wrong chunk, ignored context, hallucination"]'::jsonb,
 6, 100, true),

('c0000000-0000-4000-8000-000000000001', 11, 'MCP with Multi-Agent Development',
 'Model Context Protocol and multi-agent systems — how agents get tools, and how coordination fails.',
 '["Explain MCP and why a tool-calling standard matters","Build an agent that uses tools through MCP","Design a multi-agent system with clear roles and handoffs","Anticipate the failure modes that only appear once agents talk to each other"]'::jsonb,
 '["From chatbot to agent: the think-act-observe loop","Tool definitions, schemas and why tool descriptions are prompt surface","MCP: servers, clients, tools, resources and transports","Building and connecting an MCP server","Multi-agent patterns: supervisor, pipeline, peer collaboration","Shared state, memory and message passing between agents","Multi-agent failure modes: loops, deadlock, error propagation, conflicting actions"]'::jsonb,
 7, 110, true),

('c0000000-0000-4000-8000-000000000001', 12, 'RAGAS Metrics for RAG',
 'Measuring RAG quality objectively with RAGAS — faithfulness, relevancy and the retrieval metrics.',
 '["Choose the right RAGAS metric for the question being asked","Build an evaluation dataset with and without ground truth","Interpret metric scores and trace a low score to its cause","Track RAG quality over time as the pipeline changes"]'::jsonb,
 '["Why exact-match testing fails for RAG","Generation metrics: faithfulness, answer relevancy, answer correctness","Retrieval metrics: context precision, context recall, context entity recall","Building an evaluation dataset: questions, contexts, answers, ground truth","Running RAGAS and reading the score table","Diagnosing: low faithfulness vs low context recall — different fixes","Regression tracking and quality gates for RAG releases"]'::jsonb,
 5, 120, true),

('c0000000-0000-4000-8000-000000000001', 13, 'DeepEval for Agents',
 'Unit-test style evaluation of LLM and agent behaviour with DeepEval, integrated into pytest.',
 '["Write DeepEval test cases and choose appropriate metrics","Evaluate agent tool use, task completion and reasoning quality","Define custom metrics with G-Eval for domain-specific criteria","Run agent evaluations as part of a normal test suite"]'::jsonb,
 '["DeepEval concepts: test case, metric, threshold, evaluation run","Core metrics: answer relevancy, faithfulness, hallucination, bias, toxicity","Agent-specific metrics: tool correctness, task completion, trajectory","Custom criteria with G-Eval and DAG metrics","Conversational and multi-turn evaluation","pytest integration and CI gating on metric thresholds","Comparing DeepEval and RAGAS — when to reach for which"]'::jsonb,
 5, 130, true),

('c0000000-0000-4000-8000-000000000001', 14, 'Observability with LangSmith',
 'Tracing, monitoring and debugging LLM and agent applications in development and production.',
 '["Instrument an LLM or agent application for tracing","Read a trace to find the step that caused a bad output","Build datasets from production traffic and run offline evaluations","Monitor cost, latency and quality once a system is live"]'::jsonb,
 '["Why traces matter more than logs for agents","Runs, traces and spans: the LangSmith data model","Instrumenting an application and capturing inputs, outputs, tokens, cost","Debugging a multi-step agent from its trace","Building evaluation datasets from real traffic","Online evaluators, feedback capture and human review queues","Production monitoring: cost, latency, error and quality dashboards"]'::jsonb,
 4, 140, true),

('c0000000-0000-4000-8000-000000000001', 15, 'Capstone Project #1 — RAG-based',
 'Build, test and report on a complete RAG application, applying everything from modules 1–14.',
 '["Deliver a working RAG application against a real document set","Produce a full test strategy covering manual and automated evaluation","Report RAGAS and Promptfoo results with a quality verdict","Defend design and testing decisions in a review"]'::jsonb,
 '["Project brief, document corpus and success criteria","Building the pipeline: ingestion, chunking, retrieval, generation","Manual test pass: functional, adversarial, edge cases","Automated evaluation: Promptfoo suite plus RAGAS metrics","Red-team pass and mitigation of findings","Observability: tracing and a quality dashboard","Deliverables: application, test plan, evaluation report, demo and review"]'::jsonb,
 10, 150, true),

('c0000000-0000-4000-8000-000000000001', 16, 'Capstone Project #2 — MCP with Multi-Agents',
 'Build, test and report on a multi-agent system connected through MCP — the expert-level capstone.',
 '["Deliver a multi-agent system that completes a real multi-step task","Test tool use, coordination and recovery, not just final answers","Evaluate agent behaviour with DeepEval and trace it end to end","Present a risk assessment covering autonomy and failure containment"]'::jsonb,
 '["Project brief: a task that genuinely needs more than one agent","Designing roles, handoffs and termination conditions","Exposing tools via MCP and testing the tool layer independently","Testing coordination: loops, deadlock, conflicting actions, partial failure","DeepEval agent metrics: tool correctness, task completion, trajectory","Tracing and observability across multiple agents","Deliverables: system, test strategy, evaluation report, risk assessment, demo"]'::jsonb,
 12, 160, true)

on conflict (course_id, number) do update set
  title=excluded.title, summary=excluded.summary, objectives=excluded.objectives,
  topics=excluded.topics, duration_hours=excluded.duration_hours,
  sort_order=excluded.sort_order, published=excluded.published;

-- ---------- Re-file the existing materials into the new modules ----------
do $$
declare c uuid := 'c0000000-0000-4000-8000-000000000001';
begin
  -- module 1: Introduction to Gen AI
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=1),
    material_type='handout', module='Module 1 — Introduction to Gen AI'
   where m.storage_path in ('what_is_ai.html','what_is_ai_infographic.png','what_is_generative_ai_infographic.png');

  -- module 2: Basics of LLM
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=2),
    material_type='reading', module='Module 2 — Basics of LLM'
   where m.storage_path = 'LLMs_FineTuning_RAG_Agents_AgenticAI.html';

  -- module 4: Red Team Testing
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=4),
    material_type='lab', module='Module 4 — Red Team Testing'
   where m.storage_path = 'aitestinglab.html';
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=4),
    material_type='reading', module='Module 4 — Red Team Testing'
   where m.storage_path = 'Drugs_com_AI_Search_RedTeam_TestCases.docx';

  -- module 5: documentation capstone
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=5),
    material_type='template', module='Module 5 — Capstone: PRD, Test Plan, Test Cases & Reports'
   where m.storage_path = 'Manual_Test_Cases.docx';

  -- module 12: RAGAS
  update public.materials m set module_id = (select id from public.modules where course_id=c and number=12),
    material_type='slides', module='Module 12 — RAGAS Metrics for RAG'
   where m.storage_path = 'QualityThought_RAGAS_Metrics_Demo.pptx';
end $$;

-- Point the legacy final exam at the new course and retire it in favour of the
-- three levelled exams (kept, not deleted, so past attempts stay meaningful).
update public.quizzes
   set course_id = 'c0000000-0000-4000-8000-000000000001',
       title = 'Final Certification Exam (superseded — see Basic / Advanced / Expert)',
       published = false
 where id = 'a1a1a1a1-1111-4111-8111-a1a1a1a1a1a1';
