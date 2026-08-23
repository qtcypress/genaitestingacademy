-- ============================================================
-- schema-09-python-course.sql — the Python & DSA track
--
-- A second course, which the schema already allowed for: `courses` has always
-- been a table rather than a constant. What it did not have was a way to say
-- "these four modules are Phase 1", so `course_phases` is added and `modules`
-- grows a `phase` column. The GenAI Testing course leaves its phase null and is
-- rendered exactly as before.
--
-- Access. One subscription opens both courses — that was a deliberate decision,
-- and it means nothing here touches `my_access()`. Free-to-try is per module and
-- already exists: `modules.is_free`, added in schema-05, is what makes module 1
-- of GenAI Testing readable without paying, and it is what makes the whole of
-- Phase 1 readable here. Four rows, not a new mechanism.
--
-- The lesson plans below are generated from the module files by mksql.py, so the
-- syllabus a student reads and the days that exist in the module cannot drift
-- apart. Do not hand-edit the topics arrays; edit the module and regenerate.
--
-- Run order: after schema-08. Idempotent — safe to run twice.
-- In the Supabase SQL editor choose "Run without RLS"; RLS is enabled below.
-- ============================================================

-- ---------- phases ----------
create table if not exists public.course_phases (
  id         uuid primary key default gen_random_uuid(),
  course_id  uuid not null references public.courses(id) on delete cascade,
  number     int  not null,
  title      text not null,
  blurb      text not null default '',
  sort_order int  not null default 100,
  unique (course_id, number)
);

alter table public.modules add column if not exists phase int;
create index if not exists modules_phase_idx on public.modules (course_id, phase, number);

alter table public.course_phases enable row level security;
drop policy if exists "phases read"  on public.course_phases;
drop policy if exists "phases admin" on public.course_phases;
create policy "phases read"  on public.course_phases for select
  using (auth.role() = 'authenticated');
create policy "phases admin" on public.course_phases for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- pricing ----------
-- The three-month plan drops from Rs 1299 to Rs 1199. A price lives in one place
-- (public.plans) and the pricing page and Razorpay order both read it from there,
-- so this single update is the whole change. Existing subscriptions are unaffected:
-- they store the amount that was actually charged on the payment row.
update public.plans
   set amount_paise = 119900,
       description  = 'Full access for 90 days — both tracks, all certification exams.'
 where id = 'quarterly';
update public.plans
   set description = 'Full access to both tracks and all certification exams for 30 days.'
 where id = 'monthly';
update public.plans
   set description = 'Full access for a year, including any new modules added during that time.'
 where id = 'yearly';

-- ---------- the course ----------
-- duration_hours is deliberately null on every module here. The unit of work is a
-- lesson, not an hour: "~5h" beside each module and "~120 hours" across the course
-- is the first number a prospective student meets, and it reads as a commitment to
-- be talked out of rather than a curriculum to start. app.html omits both when the
-- column is null, so this is the whole change. The GenAI Testing course keeps its
-- hours; that audience is buying a scheduled programme.
insert into public.courses (code, title, subtitle, description, sort_order, published)
values ('PYTHON-DSA',
        'Python Zero to Hero',
        'Python & Data Structures, 24 modules in six phases',
        'Twenty-four modules from variables to dynamic programming, five lessons each, '
        'with every code sample runnable in the browser. Phase 1 is free with an '
        'account; Phase 2 onwards needs an active subscription.',
        20, true)
on conflict (code) do update set
  title = excluded.title, subtitle = excluded.subtitle,
  description = excluded.description, sort_order = excluded.sort_order,
  published = excluded.published;


do $$
declare v_course uuid;
begin
  select id into v_course from public.courses where code = 'PYTHON-DSA';

  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 1, 'Phase 1 — Foundations', 'Modules 1–4. Everything a program is made of. Free to everyone with an account.', 10)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;
  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 2, 'Phase 2 — Intermediate Python', 'Modules 5–8. Classes, packages, the lazy constructs, and testing.', 20)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;
  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 3, 'Phase 3 — DSA Foundations', 'Modules 9–12. Cost, arrays and strings, and the first structures built by hand.', 30)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;
  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 4, 'Phase 4 — DSA Core', 'Modules 13–16. Trees, graphs, hashing, sorting and searching.', 40)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;
  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 5, 'Phase 5 — DSA Advanced', 'Modules 17–20. Dynamic programming, greedy, backtracking, weighted graphs.', 50)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;
  insert into public.course_phases (course_id, number, title, blurb, sort_order)
  values (v_course, 6, 'Phase 6 — Expert', 'Modules 21–24. Concurrency, professional testing, packaging and patterns, performance, capstone.', 60)
  on conflict (course_id, number) do update set
    title = excluded.title, blurb = excluded.blurb, sort_order = excluded.sort_order;

  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 1, 'First Contact — Values, Operators, Strings & Decisions', 'Everything a Python program is made of: values and the names you bind them to, the operators that combine them, strings and how to cut them up, and the first branch in the road.',
    '["Bind values to names and predict what a type conversion will do", "Slice and format strings, including f-strings", "Write a branching decision with if / elif / else"]'::jsonb,
    '["Lesson 1 — Hello, Python — Values & Variables", "Lesson 2 — Operators & Type Conversion", "Lesson 3 — Strings — Slicing, Methods & f-strings", "Lesson 4 — Making Decisions — if / elif / else", "Lesson 5 — Capstone — A Retail Billing System"]'::jsonb,
    null, 1, 10, true, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 2, 'Collections & Repetition — Lists, Tuples & Loops', 'The two ways to hold more than one thing, and the two ways to do something more than once. Ends with a comprehension, which is both at the same time.',
    '["Choose between a list and a tuple, and say why", "Write for and while loops, including nested ones, without off-by-one errors", "Replace a simple loop with a list comprehension"]'::jsonb,
    '["Lesson 1 — Lists — Ordered, Changeable Collections", "Lesson 2 — Loops — for, while & range()", "Lesson 3 — Tuples — When Data Shouldn''t Change", "Lesson 4 — Nested Loops & List Comprehensions", "Lesson 5 — Capstone — An Inventory Management Mini-System"]'::jsonb,
    null, 1, 20, true, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 3, 'Dictionaries, Sets & Functions', 'Lookup by name instead of position, sets for uniqueness and comparison, and functions — the first tool for making a program bigger than your screen.',
    '["Model data as a dictionary and loop over it by key, value or both", "Use a set for uniqueness and for comparing two groups", "Extract repeated logic into a function with clear parameters"]'::jsonb,
    '["Lesson 1 — Dictionaries — Lookup by Name, Not Position", "Lesson 2 — Looping Through Dictionaries", "Lesson 3 — Sets — Uniqueness & Comparing Groups", "Lesson 4 — Functions — Naming Your Logic", "Lesson 5 — Capstone — A Student Grade Management System"]'::jsonb,
    null, 1, 30, true, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 4, 'Files, Errors & a First Look at OOP', 'Making data survive the program ending, dealing with the failures that follow, and the first classes: your own types, with their own behaviour.',
    '["Read and write a file, and close it properly with a context manager", "Handle a failure with try / except without hiding the cause", "Define a class with state that changes over time"]'::jsonb,
    '["Lesson 1 — Reading & Writing Files", "Lesson 2 — Handling Errors Gracefully", "Lesson 3 — Classes — Modeling Real Things", "Lesson 4 — Objects That Change Over Time", "Lesson 5 — Capstone — A Class-Based Inventory System with Persistence"]'::jsonb,
    null, 1, 40, true, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 5, 'OOP Deep Dive — Inheritance & Special Methods', 'The rest of what classes do. Inheritance without the copy-paste, one interface over many behaviours, and the special methods that make your objects feel native.',
    '["Extend a class by inheritance instead of copying it", "Use polymorphism so one call site serves many types", "Implement __repr__, __eq__ and other special methods where they earn their place"]'::jsonb,
    '["Lesson 1 — Inheritance — Building on What Exists", "Lesson 2 — Polymorphism — One Interface, Many Behaviors", "Lesson 3 — Special Methods — Making Objects Feel Native", "Lesson 4 — Class Attributes, classmethod & staticmethod", "Lesson 5 — Capstone — Employee Management System"]'::jsonb,
    null, 2, 50, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 6, 'Modules, Packages & the Python Ecosystem', 'How a project grows past one file: the standard library, your own modules, packages, and reading and writing the two formats you will actually meet.',
    '["Find and use the right standard-library module instead of writing it", "Split a growing program into modules and a package", "Read and write JSON and CSV"]'::jsonb,
    '["Lesson 1 — The Standard Library — Batteries Included", "Lesson 2 — Writing Your Own Modules", "Lesson 3 — Packages — Organizing a Growing Project", "Lesson 4 — Structured Data — json & csv", "Lesson 5 — Capstone — A Multi-Module Order Processing Project"]'::jsonb,
    null, 2, 60, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 7, 'Comprehensions, Generators & Decorators', 'The constructs that make Python code look like Python — and generators, which let you process more data than fits in memory.',
    '["Write dict, set and nested comprehensions where they are clearer than a loop", "Write a generator and explain when laziness matters", "Write a decorator, and say what it does to the function it wraps"]'::jsonb,
    '["Lesson 1 — Comprehensions — Dict, Set & Nested", "Lesson 2 — Generators — Producing Values Lazily", "Lesson 3 — Decorators — Wrapping Behavior Around Functions", "Lesson 4 — Lambda, map, filter & *args/**kwargs", "Lesson 5 — Capstone — A Log Analysis Pipeline"]'::jsonb,
    null, 2, 70, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 8, 'Regex & Testing with pytest-style Tests', 'Finding structure in text with regular expressions, and proving your code does what you claim with tests you can run in one command.',
    '["Match, capture and substitute text with regular expressions", "Write tests that state one expectation each", "Run a suite and read what it tells you"]'::jsonb,
    '["Lesson 1 — Regex — Pattern Matching in Text", "Lesson 2 — Capture Groups & Substitution", "Lesson 3 — Why Test — assert & Simple Test Functions", "Lesson 4 — pytest Conventions & a Mini Test Runner", "Lesson 5 — Capstone — A Validators Module with a Full Test Suite"]'::jsonb,
    null, 2, 80, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 9, 'Complexity Analysis — Big-O', 'How to say what an algorithm costs before you run it, and how to check whether you were right. The vocabulary the rest of the course is written in.',
    '["State the time and space complexity of a piece of code you have just written", "Recognise O(log n) and say where it comes from", "Benchmark two approaches and reconcile the numbers with the theory"]'::jsonb,
    '["Lesson 1 — Why Complexity Matters", "Lesson 2 — Measuring Growth in Practice", "Lesson 3 — Space Complexity — The Other Cost", "Lesson 4 — O(log n) in Action — Binary Search", "Lesson 5 — Capstone — Benchmarking Three Approaches to One Problem"]'::jsonb,
    null, 3, 90, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 10, 'Arrays & Strings — Core Interview Patterns', 'The two-pointer and sliding-window patterns, prefix sums, and the string problems that most interview questions turn out to be a variation of.',
    '["Apply the two-pointer and sliding-window patterns to array and string problems", "Answer repeated range queries with a prefix sum", "Recognise which of these patterns a new problem is asking for"]'::jsonb,
    '["Lesson 1 — The Two-Pointer Technique", "Lesson 2 — The Sliding Window Technique", "Lesson 3 — Prefix Sums — Answer Range Queries Instantly", "Lesson 4 — Classic String Problems", "Lesson 5 — Capstone — A Mini Interview Problem Set"]'::jsonb,
    null, 3, 100, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 11, 'Linked Lists — Your First Real Data Structure', 'Your first data structure built from scratch rather than borrowed from the language — and the pointer manipulation that makes every later structure possible.',
    '["Implement a singly linked list with insertion, deletion and traversal", "Reverse a list in place with three pointers", "Use fast and slow pointers to find a cycle or a midpoint"]'::jsonb,
    '["Lesson 1 — Building a Singly Linked List", "Lesson 2 — Insertion & Deletion", "Lesson 3 — Reversing a Linked List", "Lesson 4 — Fast & Slow Pointers — Cycles and the Middle Node", "Lesson 5 — Capstone — A Playlist Manager with Undo"]'::jsonb,
    null, 3, 110, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 12, 'Stacks, Queues & Recursion', 'The two structures everything else is built on, and the recursion that borrows one of them without telling you.',
    '["Use a stack for anything that must be undone in reverse order", "Use collections.deque for a queue, and say why a list is the wrong choice", "Write a recursive function with a correct base case, and convert it to an explicit stack"]'::jsonb,
    '["Lesson 1 — Stacks — Last In, First Out", "Lesson 2 — Queues — First In, First Out", "Lesson 3 — Recursion — A Function That Calls Itself", "Lesson 4 — The Call Stack — Where Recursion Actually Lives", "Lesson 5 — Capstone — A Command Console with Undo, Redo and a Job Queue"]'::jsonb,
    null, 3, 120, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 13, 'Trees', 'Nodes that branch. Traversals and what each ordering is for, search trees, and the measured truth that a BST is O(height) rather than O(log n).',
    '["Build a binary tree and walk it in all four useful orders", "Implement insert and search on a binary search tree", "Measure a tree''s height and explain what unbalances it"]'::jsonb,
    '["Lesson 1 — Binary Trees — A Node Whose Children Are Also Trees", "Lesson 2 — Traversals — Four Ways to Visit Every Node", "Lesson 3 — Binary Search Trees — One Rule That Buys You Everything", "Lesson 4 — Height, Balance and the Tree That Is Secretly a List", "Lesson 5 — Capstone — A Filesystem Explorer"]'::jsonb,
    null, 4, 130, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 14, 'Graphs', 'Nodes with arbitrary connections: how to store a graph, how to walk it breadth-first and depth-first, and how to order work that has dependencies.',
    '["Represent a graph as an adjacency list and justify that over a matrix", "Find a shortest path in an unweighted graph with BFS and reconstruct it", "Detect a cycle and produce a topological order"]'::jsonb,
    '["Lesson 1 — Representing a Graph — Nodes, Edges, and Two Ways to Store Them", "Lesson 2 — Breadth-First Search — Nearest Things First", "Lesson 3 — Depth-First Search — Down First, Wide Later", "Lesson 4 — Cycle Detection and Topological Sort — Putting Things in a Possible Order", "Lesson 5 — Capstone — A Course Prerequisite Planner"]'::jsonb,
    null, 4, 140, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 15, 'Hashing, Sets & Counting', 'What a dictionary is doing underneath, what the word ''average'' in O(1) average is hiding, and the problems that dissolve the moment you reach for a hash.',
    '["Explain how a hash table turns a key into an address", "Say why a list is unhashable, and why membership in a set beats membership in a list", "Solve a problem in one pass using a dict as an index"]'::jsonb,
    '["Lesson 1 — What a Hash Table Actually Is", "Lesson 2 — Collisions — What the Word “Average” Was Hiding", "Lesson 3 — Sets and Counting — The Accidental O(n²)", "Lesson 4 — Hashing as a Problem-Solving Tool", "Lesson 5 — Capstone — A Search Index Over a Small Corpus"]'::jsonb,
    null, 4, 150, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 16, 'Sorting, Searching & Heaps', 'Three elementary sorts, two good ones, binary search done properly, and the heap that gives you a priority queue for the price of a log.',
    '["Implement merge sort and quick sort and state the cost of each", "Demonstrate quick sort''s worst case and fix it with a pivot change", "Use bisect and heapq rather than reimplementing them"]'::jsonb,
    '["Lesson 1 — The Elementary Sorts — Bubble, Selection, Insertion", "Lesson 2 — Merge Sort — Divide, Conquer, and Pay for It", "Lesson 3 — Quick Sort — Fast, Until It Isn''t", "Lesson 4 — Binary Search and Heaps — Order You Can Exploit", "Lesson 5 — Capstone — A Live Leaderboard"]'::jsonb,
    null, 4, 160, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 17, 'Dynamic Programming', 'Recognising a problem that contains overlapping copies of itself, and the four questions that turn one into a table — including how to recover the answer, not just its cost.',
    '["Identify overlapping subproblems and optimal substructure in a new problem", "Convert a recurrence into a memoised function and then into a table", "Reconstruct the solution itself by walking the table back"]'::jsonb,
    '["Lesson 1 — Overlapping Subproblems — Paying Off fib(20)", "Lesson 2 — Tabulation — The Same Recurrence, Turned Around", "Lesson 3 — One-Dimensional DP — Four Questions, Then the Loop", "Lesson 4 — Two-Dimensional DP — When One Index Is Not Enough", "Lesson 5 — Capstone — Edit Distance, and the Edits Themselves"]'::jsonb,
    null, 5, 170, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 18, 'Greedy Algorithms', 'Taking the best option now and never reconsidering: when that is provably optimal, when it quietly is not, and how to test which case you are in.',
    '["State the greedy-choice property and test whether a problem has it", "Solve interval scheduling and explain why earliest-finish is the right rule", "Find a counterexample to a greedy hypothesis by brute force"]'::jsonb,
    '["Lesson 1 — The Greedy Choice — Best Now, Never Reconsidered", "Lesson 2 — Interval Scheduling — Three Plausible Rules, One That Works", "Lesson 3 — Sorting Is the Greedy Workhorse", "Lesson 4 — Greedy or DP? — Testing the Hypothesis", "Lesson 5 — Capstone — The Meeting Room Scheduler"]'::jsonb,
    null, 5, 180, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 19, 'Backtracking', 'Choose, explore, un-choose — searching a space of decisions you build as you go, and the pruning that is the only reason it finishes.',
    '["Write the choose / explore / un-choose template from memory", "Generate permutations, combinations and subsets, duplicates included", "Prune a search and measure the reduction in nodes explored"]'::jsonb,
    '["Lesson 1 — The Template — Choose, Explore, Un-choose", "Lesson 2 — Permutations, Combinations and Subsets", "Lesson 3 — N-Queens — Backtracking Under Constraints", "Lesson 4 — Pruning — Why Backtracking Finishes At All", "Lesson 5 — Capstone — A Sudoku Solver That Reports Its Own Effort"]'::jsonb,
    null, 5, 190, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 20, 'Advanced Graph Algorithms', 'Edges with costs: cheapest paths, negative cycles, and the minimum network that connects everything — plus the structure that answers ''are these already joined?''.',
    '["Implement Dijkstra with a heap and reconstruct the cheapest path", "Use Bellman-Ford where edges can be negative, and detect a negative cycle", "Build a minimum spanning tree, and explain why it is not a shortest-path tree"]'::jsonb,
    '["Lesson 1 — Weighted Graphs and Dijkstra — Cheapest, Not Fewest", "Lesson 2 — Bellman-Ford — Slower, and Right Where Dijkstra Is Confidently Wrong", "Lesson 3 — Minimum Spanning Trees — Connect Everything for the Least Total Cost", "Lesson 4 — Union-Find and Kruskal — The Structure That Answers \"Already Connected?\"", "Lesson 5 — Capstone — A Delivery Route Planner"]'::jsonb,
    null, 5, 200, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 21, 'Concurrency & Async', 'Doing more than one thing at a time, what the GIL does and does not stop, and why the answer is almost always asyncio.',
    '["Classify a workload as I/O-bound or CPU-bound and pick the right tool", "Explain what the GIL does and does not prevent", "Write an async worker pool with a bounded queue, a semaphore and retries"]'::jsonb,
    '["Lesson 1 — Why Concurrency — and the Lock That Shapes All of It", "Lesson 2 — Threads — Overlapping Waits, and the Bug You Cannot See", "Lesson 3 — Processes — Real Parallelism, and the Toll You Pay to Reach It", "Lesson 4 — asyncio — One Thread, Ten Thousand Waits", "Lesson 5 — Capstone — A Concurrent Job Runner"]'::jsonb,
    null, 6, 210, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 22, 'Testing & Quality with pytest', 'Module 8 covered the mechanics. This is the judgement: what to test, what to leave alone, and how to keep a suite that still means something in a year.',
    '["Decide what is worth testing and what makes a test a liability", "Use fixtures, parametrisation and test doubles appropriately", "Diagnose a flaky test, and treat coverage as a floor rather than a target"]'::jsonb,
    '["Lesson 1 — What to Test, and What to Leave Alone", "Lesson 2 — Fixtures and Parametrize — Set Up Once, Assert Many Times", "Lesson 3 — Test Doubles — Stubs, Fakes, Mocks and Spies", "Lesson 4 — Keeping a Suite Honest", "Lesson 5 — Capstone — Find the Bugs Before Anybody Tells You"]'::jsonb,
    null, 6, 220, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 23, 'Packaging, Tooling & Design Patterns', 'How a project leaves your laptop, the tooling that keeps it honest, and the handful of design patterns that are genuinely worth the words.',
    '["Lay out and package a project with a real pyproject.toml", "Configure formatting, linting and type checking so the tools decide", "Apply strategy, factory, adapter, observer and dependency injection where they fit"]'::jsonb,
    '["Lesson 1 — How a Project Is Shipped", "Lesson 2 — Tooling That Keeps a Codebase Honest", "Lesson 3 — Patterns You Will Actually Use, Part One", "Lesson 4 — Patterns You Will Actually Use, Part Two", "Lesson 5 — Capstone — Refactoring a Tangle, and Proving You Did Not Break It"]'::jsonb,
    null, 6, 230, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
  insert into public.modules
    (course_id, number, title, summary, objectives, topics, duration_hours, phase,
     sort_order, is_free, published)
  values (v_course, 24, 'Performance, and the Final Capstone', 'Measuring before optimising, the structural choices that dwarf every clever trick, and the final project that draws on all six phases.',
    '["Profile before optimising, and read a profile correctly", "Choose a data structure on measured evidence", "Deliver a complete project that draws on all six phases"]'::jsonb,
    '["Lesson 1 — Measure First — The Profiler Is Not Optional", "Lesson 2 — The Right Structure Is the Whole Optimisation", "Lesson 3 — Caching, Hoisting and the Cost of a Dot", "Lesson 4 — Memory — Stream, Don''t Accumulate", "Lesson 5 — The Final Capstone — Ship a Log Analysis Tool"]'::jsonb,
    null, 6, 240, false, true)
  on conflict (course_id, number) do update set
    title = excluded.title, summary = excluded.summary, objectives = excluded.objectives,
    topics = excluded.topics, duration_hours = excluded.duration_hours,
    phase = excluded.phase, sort_order = excluded.sort_order,
    is_free = excluded.is_free, published = excluded.published;
end $$;

-- ---------- what just happened ----------
-- 24 modules, 6 phases, modules 1-4 free. Verify with:
--   select m.number, m.phase, m.is_free, m.title
--     from public.modules m join public.courses c on c.id = m.course_id
--    where c.code = 'PYTHON-DSA' order by m.number;
