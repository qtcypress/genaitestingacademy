-- ============================================================
-- GenAITesting — Migration 04
-- Three levelled exams across all 16 modules.
-- Basic = recall & concepts · Advanced = application · Expert = judgement.
-- Each issues its own certificate on a pass. Safe to re-run.
-- ============================================================

insert into public.quizzes (id, course_id, title, description, pass_percent, time_limit_minutes, level, is_final, published) values
('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',
 'GenAI Testing — Basic Level',
 'Concepts and vocabulary across all 16 modules. 20 questions, 30 minutes, 60% to pass. Passing issues your Basic certificate.',
 60, 30, 'basic', false, true),
('a0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001',
 'GenAI Testing — Advanced Level',
 'Applying the techniques: designing tests, writing assertions, building pipelines. 25 questions, 45 minutes, 70% to pass. Passing issues your Advanced certificate.',
 70, 45, 'advanced', false, true),
('e0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000001',
 'GenAI Testing — Expert Level',
 'Diagnosis, trade-offs and judgement on real failures across RAG, agents and multi-agent systems. 30 questions, 60 minutes, 75% to pass. Passing issues your Expert certificate.',
 75, 60, 'expert', false, true)
on conflict (id) do update set
  course_id=excluded.course_id, title=excluded.title, description=excluded.description,
  pass_percent=excluded.pass_percent, time_limit_minutes=excluded.time_limit_minutes,
  level=excluded.level, is_final=excluded.is_final, published=excluded.published;

delete from public.questions where quiz_id in (
  'b0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000002',
  'e0000000-0000-4000-8000-000000000003');

-- ============================ BASIC (20) ============================
insert into public.questions (quiz_id, question, options, correct_index, sort_order) values
('b0000000-0000-4000-8000-000000000001','M1 — What distinguishes a generative model from a discriminative one?','["Generative models create new content; discriminative models classify or predict from existing data","Generative models are always larger","Discriminative models cannot use neural networks","Generative models never make mistakes"]'::jsonb,0,10),
('b0000000-0000-4000-8000-000000000001','M1 — Which of these is NOT a typical generative AI application shape?','["Summarising a document","Generating code","Sorting a fixed list of numbers alphabetically","Answering questions from a knowledge base"]'::jsonb,2,20),
('b0000000-0000-4000-8000-000000000001','M2 — At its core, what does an LLM do to produce a response?','["Queries a database of verified facts","Repeatedly predicts the next token based on patterns learned in training","Runs rules written by its developers","Searches the web in real time"]'::jsonb,1,30),
('b0000000-0000-4000-8000-000000000001','M2 — A token is best described as:','["One word","A chunk of text (often a word piece) that the model processes as a single unit","One character","One sentence"]'::jsonb,1,40),
('b0000000-0000-4000-8000-000000000001','M2 — The context window determines:','["How fast the model responds","How much text the model can consider in a single request","How many users can connect at once","The model training cost"]'::jsonb,1,50),
('b0000000-0000-4000-8000-000000000001','M2 — Raising the temperature parameter generally makes output:','["Shorter","More varied and less predictable","More factually accurate","Cheaper"]'::jsonb,1,60),
('b0000000-0000-4000-8000-000000000001','M2 — Which problem does RAG address that fine-tuning addresses poorly?','["Making the model respond faster","Giving the model access to fresh or private facts that change often","Reducing the number of parameters","Improving grammar"]'::jsonb,1,70),
('b0000000-0000-4000-8000-000000000001','M3 — Which prompt is most testable?','["Tell me about our refund policy","Summarise the refund policy in exactly three bullet points, using only the provided policy text","Explain refunds nicely","Refunds?"]'::jsonb,1,80),
('b0000000-0000-4000-8000-000000000001','M3 — Few-shot prompting means:','["Asking the same question several times","Including a small number of worked examples in the prompt","Using a smaller model","Limiting the response length"]'::jsonb,1,90),
('b0000000-0000-4000-8000-000000000001','M4 — Prompt injection is:','["A way to compress prompts","Untrusted input that overrides or subverts the system instructions","A method of speeding up inference","Adding embeddings to a vector store"]'::jsonb,1,100),
('b0000000-0000-4000-8000-000000000001','M4 — The primary aim of red-team testing a GenAI application is to:','["Measure response latency","Deliberately provoke unsafe, harmful or policy-violating behaviour","Check the UI layout","Verify the model version"]'::jsonb,1,110),
('b0000000-0000-4000-8000-000000000001','M5 — Why do acceptance criteria need rewriting for GenAI features?','["Because GenAI features have no requirements","Because the same input can produce differently worded but still correct output, so exact-match criteria fail","Because testers cannot access the model","Because GenAI features are always low risk"]'::jsonb,1,120),
('b0000000-0000-4000-8000-000000000001','M6 — Promptfoo is primarily a tool for:','["Hosting LLMs in production","Defining declarative test cases and assertions against prompts and models","Labelling training data","Building vector databases"]'::jsonb,1,130),
('b0000000-0000-4000-8000-000000000001','M7 — A Promptfoo red-team scan works by:','["Load-testing the API","Generating and running adversarial inputs against your application, then reporting what got through","Checking code style","Measuring token cost only"]'::jsonb,1,140),
('b0000000-0000-4000-8000-000000000001','M8 — Why use a Python virtual environment for a test project?','["It makes tests run faster","It isolates the project dependencies so versions do not clash with other projects","It encrypts your code","It is required to call any API"]'::jsonb,1,150),
('b0000000-0000-4000-8000-000000000001','M9 — In pytest, parametrisation is used to:','["Run the same test logic across many input cases without duplicating code","Run tests in parallel","Skip failing tests automatically","Generate random inputs"]'::jsonb,0,160),
('b0000000-0000-4000-8000-000000000001','M10 — What is the correct order of a RAG pipeline?','["Embed → Chunk → Retrieve → Generate","Chunk → Embed → Retrieve → Generate","Retrieve → Generate → Chunk → Embed","Chunk → Retrieve → Embed → Generate"]'::jsonb,1,170),
('b0000000-0000-4000-8000-000000000001','M11 — MCP (Model Context Protocol) is:','["A prompt compression format","A standard way for agents to discover and call external tools and data sources","A fine-tuning technique","A vector similarity metric"]'::jsonb,1,180),
('b0000000-0000-4000-8000-000000000001','M12 — In RAGAS, faithfulness measures whether:','["The answer is grammatically correct","The answer is supported by the retrieved context","The answer is short","The retrieval was fast"]'::jsonb,1,190),
('b0000000-0000-4000-8000-000000000001','M14 — Why are traces more useful than plain logs when debugging an agent?','["Traces are smaller","Traces show the ordered chain of steps, tool calls and inputs/outputs, so you can find which step went wrong","Traces are encrypted","Logs cannot be searched"]'::jsonb,1,200);

-- ============================ ADVANCED (25) ============================
insert into public.questions (quiz_id, question, options, correct_index, sort_order) values
('a0000000-0000-4000-8000-000000000002','M2 — A summarisation feature silently truncates long documents. Most likely cause?','["Temperature set too high","Input exceeds the context window and is being cut","The model is fine-tuned","Top-p is too low"]'::jsonb,1,10),
('a0000000-0000-4000-8000-000000000002','M2 — You need identical output for the same input in a regression suite. Best first step?','["Increase max tokens","Set temperature to 0 (and fix seed where supported)","Switch to a bigger model","Add more few-shot examples"]'::jsonb,1,20),
('a0000000-0000-4000-8000-000000000002','M3 — A feature must return JSON your code parses. Strongest approach?','["Ask politely for JSON in the prompt","Specify an explicit schema, use structured-output mode where available, and validate the parsed result in the test","Lower the temperature only","Post-process with regex and hope"]'::jsonb,1,30),
('a0000000-0000-4000-8000-000000000002','M3 — Your team edits a production prompt weekly. Which practice matters most?','["Keeping prompts in a shared document","Versioning prompts in source control with a regression suite that runs on every change","Making prompts as long as possible","Letting each developer keep a local copy"]'::jsonb,1,40),
('a0000000-0000-4000-8000-000000000002','M4 — A RAG chatbot answers using text hidden inside an uploaded document that instructs it to ignore its rules. This is:','["A retrieval bug","Indirect prompt injection via retrieved content","A chunking error","Model drift"]'::jsonb,1,50),
('a0000000-0000-4000-8000-000000000002','M4 — Which red-team finding is most severe in a medical-information assistant?','["The tone is inconsistent","It produces a confident, specific and unsafe dosage recommendation","It refuses some valid questions","Responses are slow"]'::jsonb,1,60),
('a0000000-0000-4000-8000-000000000002','M5 — Best acceptance criterion for a GenAI summary feature?','["The summary matches the reference text exactly","The summary contains no claim absent from the source, covers the stated key points, and stays within the length limit","The summary is under 100 words","Users like the summary"]'::jsonb,1,70),
('a0000000-0000-4000-8000-000000000002','M5 — A defect report for AI behaviour should always include:','["Only the final wrong answer","The exact input, model and settings used, the observed output, and how often it reproduces","A screenshot only","The tester''s opinion of the model"]'::jsonb,1,80),
('a0000000-0000-4000-8000-000000000002','M6 — Which Promptfoo assertion best checks that an answer conveys the right meaning without demanding exact words?','["equals","contains-all","llm-rubric or similar (semantic assertion)","regex on the whole response"]'::jsonb,2,90),
('a0000000-0000-4000-8000-000000000002','M6 — You want to compare three prompts against two models on the same 50 cases. In Promptfoo this is:','["Impossible without custom code","A matrix of prompts x providers over one shared test set","Three separate projects","Only possible in the paid version"]'::jsonb,1,100),
('a0000000-0000-4000-8000-000000000002','M6 — Why add an evaluation suite to CI rather than running it manually?','["It reduces token cost to zero","It catches quality regressions on every prompt or model change before release","It removes the need for manual testing","It makes the model deterministic"]'::jsonb,1,110),
('a0000000-0000-4000-8000-000000000002','M7 — A red-team scan reports 40 failures; 25 are the model refusing politely but being flagged. Correct response?','["Ship it, all findings are noise","Triage: separate genuine policy violations from mis-flagged refusals, tune the plugins/graders, then fix the real ones","Delete the failing plugins","Lower the severity threshold until it passes"]'::jsonb,1,120),
('a0000000-0000-4000-8000-000000000002','M8 — An LLM API intermittently returns 429. The right handling in a test harness is:','["Ignore the error and mark the test passed","Retry with exponential backoff and surface a clear failure if it persists","Loop immediately without delay","Hard-code a long sleep before every call"]'::jsonb,1,130),
('a0000000-0000-4000-8000-000000000002','M8 — Where should an API key live in an automation project?','["Hard-coded in the test file","In an environment variable or secret store, never committed","In the README","In a comment next to the call"]'::jsonb,1,140),
('a0000000-0000-4000-8000-000000000002','M9 — Your LLM tests are slow and costly in CI. Best approach for the majority of runs?','["Delete most tests","Record/mock model responses for deterministic logic tests, keeping a smaller live suite for real model behaviour","Increase the timeout","Run everything only on release day"]'::jsonb,1,150),
('a0000000-0000-4000-8000-000000000002','M9 — A genuinely non-deterministic test fails roughly 1 in 10 runs. Most responsible action?','["Mark it xfail and forget it","Investigate, then either assert on a tolerance/metric threshold or move it to a monitored evaluation suite rather than a pass/fail gate","Delete the test","Retry until it passes and report green"]'::jsonb,1,160),
('a0000000-0000-4000-8000-000000000002','M10 — Answers cite the right document but miss detail that sits mid-document. Most likely cause?','["Temperature too low","Chunking or top-k is losing the relevant passage; chunk size/overlap and retrieval depth need tuning","The model is too small","The embedding model is broken"]'::jsonb,1,170),
('a0000000-0000-4000-8000-000000000002','M10 — Why add a re-ranker to a RAG pipeline?','["To reduce storage","To reorder retrieved candidates so the most relevant land in the prompt","To compress the answer","To replace embeddings"]'::jsonb,1,180),
('a0000000-0000-4000-8000-000000000002','M11 — When testing an MCP-connected agent, tool descriptions matter because:','["They are shown to end users","They are prompt surface the model reads to decide which tool to call, so a poor description causes wrong tool selection","They control rate limits","They define the database schema"]'::jsonb,1,190),
('a0000000-0000-4000-8000-000000000002','M11 — Which test targets a multi-agent-specific risk rather than a single-agent one?','["Checking the answer is factually correct","Verifying the system terminates instead of two agents handing work back and forth indefinitely","Checking response latency","Checking the prompt length"]'::jsonb,1,200),
('a0000000-0000-4000-8000-000000000002','M12 — RAGAS context recall specifically tells you:','["How relevant the answer is","Whether the retrieved context actually contained the information needed to answer","How fast retrieval ran","How many tokens were used"]'::jsonb,1,210),
('a0000000-0000-4000-8000-000000000002','M12 — Which RAGAS metric needs ground-truth answers?','["Faithfulness","Answer correctness","Answer relevancy","Context precision (reference-free variant)"]'::jsonb,1,220),
('a0000000-0000-4000-8000-000000000002','M13 — DeepEval''s tool-correctness metric is used to check that an agent:','["Responds quickly","Called the expected tools with sensible arguments for the task","Used few tokens","Produced valid JSON"]'::jsonb,1,230),
('a0000000-0000-4000-8000-000000000002','M13 — G-Eval in DeepEval is useful when:','["You need a deterministic string match","You need a custom, domain-specific quality criterion expressed in natural language and scored consistently","You want to reduce cost","You need to fine-tune a model"]'::jsonb,1,240),
('a0000000-0000-4000-8000-000000000002','M14 — Building evaluation datasets from production traces is valuable because:','["It removes the need for tests","The dataset reflects what real users actually send, including cases you never imagined","It reduces model cost","It guarantees no hallucinations"]'::jsonb,1,250);

-- ============================ EXPERT (30) ============================
insert into public.questions (quiz_id, question, options, correct_index, sort_order) values
('e0000000-0000-4000-8000-000000000003','A RAG answer is fluent, cites a real retrieved chunk, but states a fact absent from that chunk. Which metric pair best isolates this?','["Context precision high, context recall high","Faithfulness low while context recall is adequate — a grounding failure, not a retrieval failure","Answer relevancy low, faithfulness high","Both faithfulness and context recall high"]'::jsonb,1,10),
('e0000000-0000-4000-8000-000000000003','Faithfulness is high but users still call the answers useless. Most likely explanation?','["The model is too small","The system is faithfully answering the wrong thing — answer relevancy and retrieval targeting need attention","Temperature is too low","The vector store is corrupted"]'::jsonb,1,20),
('e0000000-0000-4000-8000-000000000003','You must choose between fine-tuning and RAG for a policy assistant whose policies change monthly. Best reasoning?','["Fine-tune, because it is more accurate","RAG, because knowledge that changes monthly is cheap to update in the index but expensive to retrain into weights","Fine-tune, because RAG cannot cite sources","Neither; use a bigger context window alone"]'::jsonb,1,30),
('e0000000-0000-4000-8000-000000000003','A red-team scan passes 100% after mitigation. The most defensible conclusion is:','["The application is now safe","The application resists the attacks in this suite; coverage is bounded by the plugins and strategies used, so continued and varied testing is still required","Red teaming is complete and can be removed from CI","The model no longer hallucinates"]'::jsonb,1,40),
('e0000000-0000-4000-8000-000000000003','Which mitigation most reduces indirect prompt injection risk in a RAG system?','["Raising the temperature","Treating retrieved content as untrusted data — never as instructions — plus output constraints and least-privilege tools","Adding more few-shot examples","Increasing top-k"]'::jsonb,1,50),
('e0000000-0000-4000-8000-000000000003','An agent with a database tool is asked to "clean up old records" by an end user. The safest design is:','["Let the agent execute deletes autonomously for speed","Require explicit human confirmation for irreversible actions and scope the tool to least privilege","Give the agent admin credentials but log everything","Trust the model to refuse if it is wrong"]'::jsonb,1,60),
('e0000000-0000-4000-8000-000000000003','Two agents in a supervisor pattern keep re-delegating the same subtask. Best structural fix?','["Increase the model size","Add explicit termination conditions, iteration limits and progress tracking to the orchestration","Raise the temperature to break the tie","Merge them into a single prompt"]'::jsonb,1,70),
('e0000000-0000-4000-8000-000000000003','Your evaluation suite passes but production quality degrades over weeks. Most likely cause?','["The tests are too fast","Distribution shift — real inputs drift away from the fixed evaluation dataset, so the suite no longer represents reality","The database is full","The prompts were deleted"]'::jsonb,1,80),
('e0000000-0000-4000-8000-000000000003','A model-graded (LLM-as-judge) assertion consistently scores a correct answer as failing. First thing to examine?','["The model temperature of the system under test","The rubric and the judge''s own prompt/model — judges need validating against human labels before you trust them","The network latency","The vector store index"]'::jsonb,1,90),
('e0000000-0000-4000-8000-000000000003','Why is a single aggregate quality score a poor release gate for a RAG system?','["It is expensive to compute","It hides which stage failed; retrieval and generation problems need different fixes and should be measured separately","Aggregate scores are always wrong","It cannot be automated"]'::jsonb,1,100),
('e0000000-0000-4000-8000-000000000003','Chunk size is increased from 300 to 1500 tokens. Most likely combined effect?','["Both precision and recall improve","Recall of complete ideas may improve while retrieval precision drops and more irrelevant text enters the prompt","No measurable change","Embedding cost falls to zero"]'::jsonb,1,110),
('e0000000-0000-4000-8000-000000000003','Hybrid (keyword + vector) retrieval most helps when:','["All queries are conversational","Queries contain exact identifiers, codes or rare terms that embeddings blur","The corpus is tiny","Latency is the only concern"]'::jsonb,1,120),
('e0000000-0000-4000-8000-000000000003','Which is the strongest evidence that an agent failure is a tool-layer bug rather than a reasoning bug?','["The final answer is wrong","The trace shows the correct tool called with correct arguments but the tool returned an error or wrong data","The agent used many tokens","The response was slow"]'::jsonb,1,130),
('e0000000-0000-4000-8000-000000000003','You inherit a suite of 800 exact-match assertions over LLM output, mostly failing. Best strategy?','["Delete the suite","Reclassify: keep exact-match only for genuinely deterministic fields, convert the rest to schema, semantic or metric-based assertions","Set every assertion to contains","Raise temperature until they pass"]'::jsonb,1,140),
('e0000000-0000-4000-8000-000000000003','Which best describes a responsible use of autonomy limits in an agentic system?','["Unlimited actions with post-hoc review","Bounded actions per task, allowlisted tools, confirmation for irreversible steps, and a hard stop on budget or iterations","Autonomy only in production","No autonomy at all"]'::jsonb,1,150),
('e0000000-0000-4000-8000-000000000003','A capstone RAG app scores 0.92 faithfulness but 0.41 context recall. Priority fix?','["Change the generation prompt","Improve retrieval — chunking, embeddings, top-k or re-ranking — since needed context is often missing","Lower temperature","Switch to a larger generation model"]'::jsonb,1,160),
('e0000000-0000-4000-8000-000000000003','Why can a passing DeepEval task-completion metric still hide a serious defect?','["The metric is always unreliable","It judges the outcome; an agent can reach the right result via unsafe or wasteful steps that only a trajectory/tool-use check would catch","It requires ground truth","It only works on chat"]'::jsonb,1,170),
('e0000000-0000-4000-8000-000000000003','Which testing gap is most commonly missed in multi-agent systems?','["Spelling of outputs","Partial failure — one agent fails or returns garbage and the system continues as if it succeeded","Response length","Token counting"]'::jsonb,1,180),
('e0000000-0000-4000-8000-000000000003','You must prove a certificate-bearing exam cannot be cheated by inspecting the browser. The essential control is:','["Obfuscating the JavaScript","Never sending correct answers to the client and grading server-side","Disabling right-click","Using a short time limit"]'::jsonb,1,190),
('e0000000-0000-4000-8000-000000000003','For a GenAI feature in a regulated domain, which artefact set best demonstrates diligence?','["A passing unit-test run","Requirements with testable acceptance criteria, manual and adversarial test evidence, metric-based evaluation results, traceability and a risk assessment","A demo recording","A model card alone"]'::jsonb,1,200),
('e0000000-0000-4000-8000-000000000003','An indirect injection succeeds only when a specific document is retrieved. The best regression test is:','["Re-run the whole red-team suite monthly","Add a deterministic test that forces retrieval of that document and asserts the instruction is not obeyed","Remove the document permanently","Lower top-k"]'::jsonb,1,210),
('e0000000-0000-4000-8000-000000000003','Which statement about LLM-as-judge cost/quality trade-offs is most accurate?','["Bigger judges are always worth it","A strong judge on a small, well-sampled set often beats a weak judge on everything; sampling strategy matters as much as judge size","Judges should match the system model exactly","Judges remove the need for human review"]'::jsonb,1,220),
('e0000000-0000-4000-8000-000000000003','Observability data shows p95 latency tripled but quality metrics are unchanged. Most likely cause to investigate first?','["The prompts changed","Retrieval or tool-call latency, provider throttling, or a larger context being assembled","The judge model","The certificate service"]'::jsonb,1,230),
('e0000000-0000-4000-8000-000000000003','Why should red-team findings feed the regression suite rather than only a report?','["Reports are hard to read","Otherwise a fixed vulnerability can silently return on the next prompt or model change","It reduces token cost","It satisfies the linter"]'::jsonb,1,240),
('e0000000-0000-4000-8000-000000000003','A stakeholder asks for "100% accuracy" from a GenAI feature. Most professional response?','["Agree and target it","Explain that probabilistic systems need measurable quality targets, guardrails and human oversight for high-risk paths, then agree thresholds per risk level","Refuse to test the feature","Reduce scope until accuracy is 100%"]'::jsonb,1,250),
('e0000000-0000-4000-8000-000000000003','Which is the best first check when a previously good RAG system degrades right after a deployment?','["Retrain the embedding model","Diff what changed — prompt, model version, chunking, index build — and compare traces before and after","Increase top-k","Add more documents"]'::jsonb,1,260),
('e0000000-0000-4000-8000-000000000003','Fine-tuning is the better choice over RAG primarily when you need:','["Fresher facts","Consistent tone, format or specialised behaviour baked into the model itself","Cheaper updates","Source citations"]'::jsonb,1,270),
('e0000000-0000-4000-8000-000000000003','In a multi-agent system, shared mutable memory most increases the risk of:','["Slower responses","One agent corrupting context that other agents then reason over, propagating a single error system-wide","Higher token cost only","Tool schema drift"]'::jsonb,1,280),
('e0000000-0000-4000-8000-000000000003','Which evaluation design flaw most often produces falsely reassuring results?','["Too many test cases","Evaluating on data the prompt was tuned against — no held-out set, so the suite measures fit rather than generalisation","Using temperature 0","Running in CI"]'::jsonb,1,290),
('e0000000-0000-4000-8000-000000000003','A tester reports an agent "sometimes ignores the tool and answers from memory". The most useful evidence to attach is:','["A screenshot of the answer","Traces from both a passing and a failing run showing the divergence in tool-call decisions, with inputs and settings","The token count","The model release notes"]'::jsonb,1,300);

-- ============================================================
-- Redistribute the correct answers across option positions.
-- Authoring naturally clusters the right answer in one slot, which would let a
-- student pass by always picking the same letter. The shuffle is seeded by the
-- question id, so it is deterministic and re-running this file is idempotent.
-- Scoped to the three levelled exams so historical attempts on other quizzes
-- keep pointing at the options they were graded against.
-- ============================================================
do $$
declare
  r        record;
  correct  jsonb;
  newopts  jsonb;
  newidx   int;
begin
  for r in select id, question, options, correct_index from public.questions
            where quiz_id in ('b0000000-0000-4000-8000-000000000001',
                              'a0000000-0000-4000-8000-000000000002',
                              'e0000000-0000-4000-8000-000000000003')
  loop
    correct := r.options -> r.correct_index;

    select jsonb_agg(o order by md5(r.question || o::text)) into newopts
      from jsonb_array_elements(r.options) o;

    select ord - 1 into newidx
      from jsonb_array_elements(newopts) with ordinality as t(o, ord)
     where o = correct
     limit 1;

    update public.questions
       set options = newopts, correct_index = newidx
     where id = r.id;
  end loop;
end $$;
