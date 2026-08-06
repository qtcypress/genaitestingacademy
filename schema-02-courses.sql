-- ============================================================
-- QT GenAI Testing Academy — Migration 02
-- Adds: courses, modules (with lesson plans), material types,
--       three exam levels, and one certificate per level.
-- Safe to re-run.
-- ============================================================

-- ---------- COURSES ----------
create table if not exists public.courses (
  id          uuid primary key default gen_random_uuid(),
  code        text unique,
  title       text not null,
  subtitle    text,
  description text,
  sort_order  int  not null default 100,
  published   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------- MODULES (each carries its lesson plan) ----------
create table if not exists public.modules (
  id             uuid primary key default gen_random_uuid(),
  course_id      uuid not null references public.courses(id) on delete cascade,
  number         int  not null,
  title          text not null,
  summary        text,
  objectives     jsonb not null default '[]'::jsonb,  -- ["learners will be able to ..."]
  topics         jsonb not null default '[]'::jsonb,  -- lesson-plan bullets
  duration_hours numeric,
  sort_order     int  not null default 100,
  published      boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (course_id, number)
);
create index if not exists modules_course_idx on public.modules (course_id, sort_order, number);

-- ---------- MATERIALS: attach to a module, and classify ----------
alter table public.materials add column if not exists module_id uuid references public.modules(id) on delete set null;
alter table public.materials add column if not exists material_type text not null default 'material';
do $$ begin
  alter table public.materials add constraint materials_type_chk
    check (material_type in ('handout','slides','lab','reading','template','recording','material'));
exception when duplicate_object then null; end $$;
create index if not exists materials_module_id_idx on public.materials (module_id, sort_order);

-- ---------- QUIZZES: course + level ----------
alter table public.quizzes add column if not exists course_id uuid references public.courses(id) on delete cascade;
alter table public.quizzes add column if not exists level text;
do $$ begin
  alter table public.quizzes add constraint quizzes_level_chk
    check (level is null or level in ('basic','advanced','expert'));
exception when duplicate_object then null; end $$;

-- ---------- CERTIFICATES: one per (user, course, level) ----------
alter table public.certificates add column if not exists level text;
alter table public.certificates add column if not exists course_id uuid references public.courses(id);
-- the old "one certificate per user per course-title" rule is replaced by a
-- per-level rule. The partial index leaves any pre-existing rows untouched.
drop index if exists public.certificates_user_course_idx;
create unique index if not exists certificates_user_course_level_idx
  on public.certificates (user_id, course_id, level) where level is not null;

-- ============================================================
-- RLS for the new tables
-- ============================================================
alter table public.courses enable row level security;
alter table public.modules enable row level security;

drop policy if exists "courses read"  on public.courses;
drop policy if exists "courses admin" on public.courses;
create policy "courses read"  on public.courses for select
  using (auth.role() = 'authenticated' and (published or public.is_admin()));
create policy "courses admin" on public.courses for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "modules read"  on public.modules;
drop policy if exists "modules admin" on public.modules;
create policy "modules read"  on public.modules for select
  using (auth.role() = 'authenticated' and (published or public.is_admin()));
create policy "modules admin" on public.modules for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- grade_quiz — now level-aware; issues a per-level certificate
-- ============================================================
create or replace function public.grade_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_total   int;
  v_score   int := 0;
  v_pct     numeric;
  v_passed  boolean;
  v_quiz    record;
  v_q       record;
  v_ans     int;
  v_cert    text := null;
  v_profile record;
  v_course  record;
  v_label   text;
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

  -- a certificate is issued for any quiz that carries a level (basic/advanced/expert),
  -- or for a legacy quiz flagged is_final.
  if v_passed and (v_quiz.level is not null or v_quiz.is_final) then
    select * into v_profile from public.profiles where id = v_uid;
    select * into v_course  from public.courses where id = v_quiz.course_id;

    v_label := coalesce(v_course.title, 'GenAI Application Testing')
             || case when v_quiz.level is null then ''
                     else ' — ' || initcap(v_quiz.level) || ' Level' end;

    v_cert := 'QT-' || to_char(now(),'YYYY') || '-'
           || case when v_quiz.level is null then 'F' else upper(left(v_quiz.level,1)) end
           || '-' || upper(substr(md5(v_uid::text || p_quiz_id::text || clock_timestamp()::text), 1, 8));

    insert into public.certificates
      (cert_number, user_id, email, full_name, course, course_id, level, quiz_id, percent)
    values (v_cert, v_uid, coalesce(v_profile.email,''),
            coalesce(nullif(trim(v_profile.full_name),''), v_profile.email, 'Student'),
            v_label, v_quiz.course_id, v_quiz.level, p_quiz_id, v_pct)
    on conflict (user_id, course_id, level) where level is not null do nothing;

    -- return the certificate that now stands for this level
    select cert_number into v_cert from public.certificates
      where user_id = v_uid
        and (level is not distinct from v_quiz.level)
        and (course_id is not distinct from v_quiz.course_id)
      order by issued_at limit 1;
  end if;

  return jsonb_build_object(
    'score', v_score, 'total', v_total, 'percent', v_pct,
    'passed', v_passed, 'level', v_quiz.level, 'cert_number', v_cert
  );
end;
$$;

-- ============================================================
-- verify_certificate — now also reports the level
-- ============================================================
drop function if exists public.verify_certificate(text);
create or replace function public.verify_certificate(p_query text)
returns table (cert_number text, full_name text, email text, course text,
               level text, percent numeric, issued_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select c.cert_number, c.full_name,
         regexp_replace(c.email, '^(..)[^@]*@', '\1*****@') as email,
         c.course, c.level, c.percent, c.issued_at
  from public.certificates c
  where upper(c.cert_number) = upper(trim(p_query))
     or lower(c.email) = lower(trim(p_query))
  order by c.issued_at
  limit 10;
$$;
grant execute on function public.verify_certificate(text) to anon, authenticated;

-- ============================================================
-- admin_progress_report — per-level results
-- ============================================================
drop function if exists public.admin_progress_report();
create or replace function public.admin_progress_report()
returns table (
  user_id uuid, full_name text, email text, github_user text,
  completed bigint, viewed bigint, total_published bigint,
  best_basic numeric, best_advanced numeric, best_expert numeric,
  certificates bigint, last_active timestamptz
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
    (select max(a.percent) from public.attempts a join public.quizzes q on q.id=a.quiz_id
       where a.user_id = p.id and q.level = 'basic'),
    (select max(a.percent) from public.attempts a join public.quizzes q on q.id=a.quiz_id
       where a.user_id = p.id and q.level = 'advanced'),
    (select max(a.percent) from public.attempts a join public.quizzes q on q.id=a.quiz_id
       where a.user_id = p.id and q.level = 'expert'),
    (select count(*) from public.certificates c where c.user_id = p.id),
    greatest(max(pr.updated_at),
             (select max(a2.created_at) from public.attempts a2 where a2.user_id = p.id))
  from public.profiles p
  left join public.progress pr on pr.user_id = p.id
  where p.role = 'student'
  group by p.id
  order by p.full_name;
end;
$$;

-- ============================================================
-- admin_module_progress — per-module completion for one student,
-- and a course-wide roll-up used by the student dashboard.
-- ============================================================
create or replace function public.module_progress(p_course_id uuid)
returns table (module_id uuid, number int, title text,
               total_materials bigint, completed_materials bigint)
language sql stable security definer set search_path = public
as $$
  select m.id, m.number, m.title,
         count(mat.id) filter (where mat.published),
         count(pr.material_id) filter (where pr.status = 'completed')
  from public.modules m
  left join public.materials mat on mat.module_id = m.id and mat.published
  left join public.progress  pr  on pr.material_id = mat.id and pr.user_id = auth.uid()
  where m.course_id = p_course_id and m.published
  group by m.id, m.number, m.title
  order by m.number;
$$;
grant execute on function public.module_progress(uuid) to authenticated;
