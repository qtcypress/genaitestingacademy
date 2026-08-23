-- ============================================================
-- GenAITesting — Supabase schema
-- Run this whole file in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run (idempotent where possible).
-- ============================================================

-- ---------- 1. PROFILES ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  avatar_url  text,
  github_user text,
  role        text not null default 'student' check (role in ('student','admin')),
  created_at  timestamptz not null default now()
);

-- auto-create a profile whenever a user signs in the first time
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url, github_user)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', new.email),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'user_name'
  )
  on conflict (id) do update
    set email      = excluded.email,
        full_name  = coalesce(excluded.full_name, public.profiles.full_name),
        avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url),
        github_user= coalesce(excluded.github_user, public.profiles.github_user);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- helper: is the current user an admin?
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------- 2. MATERIALS ----------
create table if not exists public.materials (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  module       text not null default 'General',   -- e.g. 'GenAI Basics', 'Promptfoo', 'RAGAS'
  kind         text not null check (kind in ('html','image','gif','pdf','pptx','docx','xlsx','other')),
  storage_path text not null,                     -- path inside the 'materials' bucket
  file_name    text not null,
  file_size    bigint,
  sort_order   int  not null default 100,
  published    boolean not null default true,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index if not exists materials_module_idx on public.materials (module, sort_order);
create index if not exists materials_pub_idx    on public.materials (published);

-- ---------- 3. PROGRESS ----------
create table if not exists public.progress (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  material_id  uuid not null references public.materials(id) on delete cascade,
  status       text not null default 'viewed' check (status in ('viewed','completed')),
  updated_at   timestamptz not null default now(),
  primary key (user_id, material_id)
);
create index if not exists progress_material_idx on public.progress (material_id);

-- ---------- 4. QUIZZES ----------
create table if not exists public.quizzes (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  pass_percent int  not null default 70 check (pass_percent between 1 and 100),
  time_limit_minutes int default 30,
  is_final     boolean not null default false,    -- final = grants certificate
  published    boolean not null default false,
  created_at   timestamptz not null default now()
);

create table if not exists public.questions (
  id            uuid primary key default gen_random_uuid(),
  quiz_id       uuid not null references public.quizzes(id) on delete cascade,
  question      text not null,
  options       jsonb not null,                   -- ["opt A","opt B","opt C","opt D"]
  correct_index int not null,                     -- NEVER exposed to students (column grant)
  sort_order    int not null default 100
);
create index if not exists questions_quiz_idx on public.questions (quiz_id, sort_order);

create table if not exists public.attempts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  quiz_id    uuid not null references public.quizzes(id) on delete cascade,
  score      numeric not null,
  total      int not null,
  percent    numeric not null,
  passed     boolean not null,
  answers    jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists attempts_user_idx on public.attempts (user_id, quiz_id);
create index if not exists attempts_quiz_idx on public.attempts (quiz_id);

-- ---------- 5. CERTIFICATES ----------
create table if not exists public.certificates (
  id          uuid primary key default gen_random_uuid(),
  cert_number text not null unique,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  email       text not null,
  full_name   text not null,
  course      text not null default 'GenAI Application Testing — Manual & Automation (Promptfoo + DeepEval/RAGAS)',
  quiz_id     uuid references public.quizzes(id),
  percent     numeric,
  issued_at   timestamptz not null default now()
);
create index if not exists certificates_email_idx on public.certificates (lower(email));
create unique index if not exists certificates_user_course_idx on public.certificates (user_id, course);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.materials    enable row level security;
alter table public.progress     enable row level security;
alter table public.quizzes      enable row level security;
alter table public.questions    enable row level security;
alter table public.attempts     enable row level security;
alter table public.certificates enable row level security;

-- profiles
-- (is_admin() is SECURITY DEFINER, so using it here does NOT cause RLS recursion)
drop policy if exists "profiles self read"   on public.profiles;
drop policy if exists "profiles admin read"  on public.profiles;
drop policy if exists "profiles self update" on public.profiles;
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles self read"   on public.profiles for select using (auth.uid() = id or public.is_admin());
create policy "profiles self update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- students may update only their display fields — never their own role.
-- (column-level grants: revoke table-wide UPDATE, re-grant harmless columns)
revoke update on public.profiles from anon, authenticated;
grant  update (full_name, avatar_url) on public.profiles to authenticated;

-- materials: any logged-in user reads published; admins do everything
drop policy if exists "materials read"  on public.materials;
drop policy if exists "materials admin" on public.materials;
create policy "materials read"  on public.materials for select using (auth.role() = 'authenticated' and (published or public.is_admin()));
create policy "materials admin" on public.materials for all using (public.is_admin()) with check (public.is_admin());

-- progress: students manage their own rows; admins read all
drop policy if exists "progress self"       on public.progress;
drop policy if exists "progress admin read" on public.progress;
create policy "progress self"       on public.progress for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "progress admin read" on public.progress for select using (public.is_admin());

-- quizzes: logged-in read published; admin all
drop policy if exists "quizzes read"  on public.quizzes;
drop policy if exists "quizzes admin" on public.quizzes;
create policy "quizzes read"  on public.quizzes for select using (auth.role() = 'authenticated' and (published or public.is_admin()));
create policy "quizzes admin" on public.quizzes for all using (public.is_admin()) with check (public.is_admin());

-- questions: logged-in read (correct_index protected by COLUMN grants below); admin all
drop policy if exists "questions read"  on public.questions;
drop policy if exists "questions admin" on public.questions;
create policy "questions read"  on public.questions for select using (auth.role() = 'authenticated');
create policy "questions admin" on public.questions for all using (public.is_admin()) with check (public.is_admin());

-- hide the answer column from client roles (admins manage questions via RPC below).
-- NOTE: a table-level SELECT grant covers all columns, so we must revoke the table
-- grant entirely and re-grant only the safe columns. After this, `select *` fails
-- for clients — the app always selects explicit columns.
revoke select on public.questions from anon, authenticated;
grant  select (id, quiz_id, question, options, sort_order) on public.questions to authenticated;

-- attempts: student sees own; inserts happen only via grade_quiz RPC; admin reads all
drop policy if exists "attempts self read"  on public.attempts;
drop policy if exists "attempts admin read" on public.attempts;
create policy "attempts self read"  on public.attempts for select using (auth.uid() = user_id or public.is_admin());

-- certificates: owner + admin read directly; public verification via RPC only
drop policy if exists "certs self read" on public.certificates;
create policy "certs self read" on public.certificates for select using (auth.uid() = user_id or public.is_admin());

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- ----- admin: create / update a question (bypasses column revoke safely)
create or replace function public.admin_upsert_question(
  p_id uuid, p_quiz_id uuid, p_question text, p_options jsonb, p_correct_index int, p_sort_order int
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  if p_id is null then
    insert into public.questions (quiz_id, question, options, correct_index, sort_order)
    values (p_quiz_id, p_question, p_options, p_correct_index, p_sort_order)
    returning id into v_id;
  else
    update public.questions
      set question = p_question, options = p_options,
          correct_index = p_correct_index, sort_order = p_sort_order
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- ----- admin: read questions WITH answers (for the quiz builder)
create or replace function public.admin_get_questions(p_quiz_id uuid)
returns table (id uuid, quiz_id uuid, question text, options jsonb, correct_index int, sort_order int)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return query
    select q.id, q.quiz_id, q.question, q.options, q.correct_index, q.sort_order
    from public.questions q where q.quiz_id = p_quiz_id order by q.sort_order, q.question;
end;
$$;

-- ----- grade a quiz server-side; answers never leave the database
create or replace function public.grade_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_total  int;
  v_score  int := 0;
  v_pct    numeric;
  v_passed boolean;
  v_quiz   record;
  v_q      record;
  v_ans    int;
  v_cert   text := null;
  v_profile record;
begin
  if v_uid is null then raise exception 'login required'; end if;

  select * into v_quiz from public.quizzes where id = p_quiz_id and published;
  if not found then raise exception 'quiz not found'; end if;

  select count(*) into v_total from public.questions where quiz_id = p_quiz_id;
  if v_total = 0 then raise exception 'quiz has no questions'; end if;

  for v_q in select id, correct_index from public.questions where quiz_id = p_quiz_id loop
    v_ans := nullif(p_answers->>v_q.id::text, '')::int;
    if v_ans is not null and v_ans = v_q.correct_index then
      v_score := v_score + 1;
    end if;
  end loop;

  v_pct    := round(100.0 * v_score / v_total, 1);
  v_passed := v_pct >= v_quiz.pass_percent;

  insert into public.attempts (user_id, quiz_id, score, total, percent, passed, answers)
  values (v_uid, p_quiz_id, v_score, v_total, v_pct, v_passed, p_answers);

  -- issue certificate on passing the FINAL quiz (once per user/course)
  if v_passed and v_quiz.is_final then
    select * into v_profile from public.profiles where id = v_uid;
    v_cert := 'QT-' || to_char(now(),'YYYY') || '-' ||
              upper(substr(md5(v_uid::text || p_quiz_id::text || now()::text), 1, 8));
    insert into public.certificates (cert_number, user_id, email, full_name, quiz_id, percent)
    values (v_cert, v_uid, coalesce(v_profile.email,''), coalesce(v_profile.full_name, v_profile.email, 'Student'), p_quiz_id, v_pct)
    on conflict (user_id, course) do nothing;
    -- if they already had one, return the existing number
    select cert_number into v_cert from public.certificates
      where user_id = v_uid order by issued_at limit 1;
  end if;

  return jsonb_build_object(
    'score', v_score, 'total', v_total, 'percent', v_pct,
    'passed', v_passed, 'cert_number', v_cert
  );
end;
$$;

-- ----- PUBLIC certificate verification (anon allowed): by cert number OR email
create or replace function public.verify_certificate(p_query text)
returns table (cert_number text, full_name text, email text, course text, percent numeric, issued_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select c.cert_number, c.full_name,
         -- mask the email for privacy: ra*****@qualitythought.in
         regexp_replace(c.email, '^(..)[^@]*@', '\1*****@') as email,
         c.course, c.percent, c.issued_at
  from public.certificates c
  where upper(c.cert_number) = upper(trim(p_query))
     or lower(c.email) = lower(trim(p_query))
  limit 5;
$$;
grant execute on function public.verify_certificate(text) to anon, authenticated;

-- ----- admin: whole-class progress dashboard in one call
create or replace function public.admin_progress_report()
returns table (
  user_id uuid, full_name text, email text, github_user text,
  completed bigint, viewed bigint, total_published bigint,
  best_final_percent numeric, certified boolean, last_active timestamptz
)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return query
  select p.id, p.full_name, p.email, p.github_user,
    count(pr.material_id) filter (where pr.status = 'completed'),
    count(pr.material_id),
    (select count(*) from public.materials m where m.published),
    (select max(a.percent) from public.attempts a
       join public.quizzes q on q.id = a.quiz_id and q.is_final
       where a.user_id = p.id),
    exists (select 1 from public.certificates c where c.user_id = p.id),
    greatest(max(pr.updated_at), (select max(a2.created_at) from public.attempts a2 where a2.user_id = p.id))
  from public.profiles p
  left join public.progress pr on pr.user_id = p.id
  where p.role = 'student'
  group by p.id
  order by p.full_name;
end;
$$;

-- ============================================================
-- STORAGE — 'materials' bucket + policies
-- ============================================================
-- Some newer Supabase projects don't allow SQL-editor policy creation on
-- storage.objects ("must be owner of table objects"). We try here; if your
-- project refuses, this block prints a NOTICE instead of failing the script —
-- then create the same 4 policies in Dashboard → Storage → Policies (see SETUP.md).
do $storage$
begin
  insert into storage.buckets (id, name, public)
  values ('materials', 'materials', false)
  on conflict (id) do nothing;

  begin
    drop policy if exists "materials bucket read"   on storage.objects;
    drop policy if exists "materials bucket write"  on storage.objects;
    drop policy if exists "materials bucket update" on storage.objects;
    drop policy if exists "materials bucket delete" on storage.objects;

    execute $p$create policy "materials bucket read" on storage.objects
      for select using (bucket_id = 'materials' and auth.role() = 'authenticated')$p$;
    execute $p$create policy "materials bucket write" on storage.objects
      for insert with check (bucket_id = 'materials' and public.is_admin())$p$;
    execute $p$create policy "materials bucket update" on storage.objects
      for update using (bucket_id = 'materials' and public.is_admin())$p$;
    execute $p$create policy "materials bucket delete" on storage.objects
      for delete using (bucket_id = 'materials' and public.is_admin())$p$;
  exception when insufficient_privilege then
    raise notice 'Could not create storage policies via SQL — create them in Dashboard → Storage → Policies (see SETUP.md).';
  end;
end
$storage$;

-- ============================================================
-- DONE. Final manual step: promote yourself to admin —
--   update public.profiles set role='admin' where email='YOUR_GITHUB_EMAIL';
-- ============================================================
