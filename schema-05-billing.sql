-- ============================================================
-- QT GenAI Testing Academy — Migration 05
-- Paid access: plans (prices held server-side), subscriptions, payments.
-- Module 1 stays free; modules 2+ and all exams require active access.
--
-- SECURITY MODEL
--   * Prices live in public.plans. The client never sends an amount — the
--     Edge Function reads the price from this table when creating an order.
--   * public.subscriptions and public.payments are READ-ONLY to clients.
--     Only grant_subscription() (SECURITY DEFINER, revoked from anon and
--     authenticated) can create access, so a student cannot self-grant.
--   * grade_quiz() re-checks access server-side, so bypassing the UI fails.
-- Safe to re-run.
-- ============================================================

-- ---------- PLANS (prices, server-side) ----------
create table if not exists public.plans (
  id            text primary key,               -- 'monthly' | 'quarterly' | 'yearly'
  name          text not null,
  description   text,
  amount_paise  int  not null check (amount_paise >= 0),  -- smallest currency unit
  currency      text not null default 'INR',
  duration_days int  not null check (duration_days > 0),
  badge         text,                           -- e.g. 'Most popular'
  sort_order    int  not null default 100,
  active        boolean not null default true
);

insert into public.plans (id, name, description, amount_paise, currency, duration_days, badge, sort_order, active) values
 ('monthly',   '1 Month',   'Full access to all 16 modules and all three certification exams for 30 days.',    49900, 'INR',  30, null,            10, true),
 ('quarterly', '3 Months',  'Full access for 90 days — the usual time to work through the course and capstones.', 129900, 'INR',  90, 'Most popular', 20, true),
 ('yearly',    '12 Months', 'Full access for a year, including any new modules added during that time.',        399900, 'INR', 365, 'Best value',   30, true)
on conflict (id) do update set
  name=excluded.name, description=excluded.description, amount_paise=excluded.amount_paise,
  currency=excluded.currency, duration_days=excluded.duration_days, badge=excluded.badge,
  sort_order=excluded.sort_order, active=excluded.active;

-- ---------- SUBSCRIPTIONS ----------
create table if not exists public.subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  plan_id    text references public.plans(id),
  status     text not null default 'active' check (status in ('active','expired','cancelled')),
  starts_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  source     text not null default 'razorpay' check (source in ('razorpay','manual','trial')),
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists subs_user_idx on public.subscriptions (user_id, expires_at desc);

-- ---------- PAYMENTS (audit trail) ----------
create table if not exists public.payments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles(id) on delete cascade,
  plan_id             text references public.plans(id),
  razorpay_order_id   text unique,
  razorpay_payment_id text,
  amount_paise        int not null,
  currency            text not null default 'INR',
  status              text not null default 'created' check (status in ('created','paid','failed')),
  created_at          timestamptz not null default now(),
  paid_at             timestamptz
);
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);

-- ---------- free-preview flag on modules ----------
alter table public.modules add column if not exists is_free boolean not null default false;
update public.modules set is_free = true
 where number = 1 and course_id = 'c0000000-0000-4000-8000-000000000001';

-- ============================================================
-- ACCESS CHECK
-- ============================================================
create or replace function public.has_active_access()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.subscriptions s
     where s.user_id = auth.uid()
       and s.status = 'active'
       and s.expires_at > now()
  );
$$;
grant execute on function public.has_active_access() to authenticated;

-- convenience for the UI: what does the current user hold?
create or replace function public.my_access()
returns table (has_access boolean, is_admin boolean, plan_id text, expires_at timestamptz, days_left int)
language sql stable security definer set search_path = public
as $$
  select
    public.has_active_access(),
    public.is_admin(),
    s.plan_id,
    s.expires_at,
    case when s.expires_at is null then null
         else greatest(0, ceil(extract(epoch from (s.expires_at - now())) / 86400))::int end
  from (select * from public.subscriptions
         where user_id = auth.uid() and status = 'active' and expires_at > now()
         order by expires_at desc limit 1) s
  right join (select 1) dummy on true;
$$;
grant execute on function public.my_access() to authenticated;

-- ============================================================
-- RLS
-- ============================================================
alter table public.plans         enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments      enable row level security;

-- plans: anyone (including signed-out visitors) may read active plans, so the
-- pricing page works before login. Only admins may change them.
drop policy if exists "plans read"  on public.plans;
drop policy if exists "plans admin" on public.plans;
create policy "plans read"  on public.plans for select using (active or public.is_admin());
create policy "plans admin" on public.plans for all using (public.is_admin()) with check (public.is_admin());
grant select on public.plans to anon, authenticated;

-- subscriptions / payments: readable by owner and admin. NO client writes at all.
drop policy if exists "subs read"     on public.subscriptions;
drop policy if exists "subs admin"    on public.subscriptions;
create policy "subs read"  on public.subscriptions for select using (auth.uid() = user_id or public.is_admin());
create policy "subs admin" on public.subscriptions for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "pay read"  on public.payments;
drop policy if exists "pay admin" on public.payments;
create policy "pay read"  on public.payments for select using (auth.uid() = user_id or public.is_admin());
create policy "pay admin" on public.payments for all using (public.is_admin()) with check (public.is_admin());

-- belt and braces: strip write privileges from client roles entirely
revoke insert, update, delete on public.subscriptions from anon, authenticated;
revoke insert, update, delete on public.payments      from anon, authenticated;
revoke insert, update, delete on public.plans         from anon, authenticated;

-- ============================================================
-- GATE THE CONTENT
--   modules stay readable (students can see the whole syllabus and what they'd
--   be buying) but the MATERIALS inside paid modules are hidden, and exam
--   questions are hidden, without active access.
-- ============================================================
drop policy if exists "materials read" on public.materials;
create policy "materials read" on public.materials for select using (
  auth.role() = 'authenticated'
  and (published or public.is_admin())
  and (
    public.is_admin()
    or public.has_active_access()
    or exists (select 1 from public.modules m where m.id = public.materials.module_id and m.is_free)
  )
);

drop policy if exists "questions read" on public.questions;
create policy "questions read" on public.questions for select using (
  auth.role() = 'authenticated' and (public.is_admin() or public.has_active_access())
);

-- ============================================================
-- grade_quiz: refuse without access, whatever the client claims
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
  if not public.has_active_access() then
    raise exception 'An active subscription is required to sit this exam';
  end if;

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

  if v_passed and (v_quiz.level is not null or v_quiz.is_final) then
    select * into v_profile from public.profiles where id = v_uid;
    select * into v_course  from public.courses  where id = v_quiz.course_id;

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
-- GRANTING ACCESS — only callable by the service role (Edge Function)
-- Extends an existing active subscription rather than overwriting it.
-- ============================================================
create or replace function public.grant_subscription(
  p_user_id uuid, p_plan_id text, p_source text default 'razorpay', p_note text default null
) returns public.subscriptions
language plpgsql security definer set search_path = public
as $$
declare
  v_days int;
  v_from timestamptz;
  v_row  public.subscriptions;
begin
  select duration_days into v_days from public.plans where id = p_plan_id;
  if v_days is null then raise exception 'unknown plan %', p_plan_id; end if;

  -- if they already have time left, add to it
  select greatest(now(), coalesce(max(expires_at), now())) into v_from
    from public.subscriptions
   where user_id = p_user_id and status = 'active' and expires_at > now();

  update public.subscriptions set status = 'expired'
   where user_id = p_user_id and status = 'active';

  insert into public.subscriptions (user_id, plan_id, status, starts_at, expires_at, source, note)
  values (p_user_id, p_plan_id, 'active', now(), v_from + (v_days || ' days')::interval, p_source, p_note)
  returning * into v_row;

  return v_row;
end;
$$;
-- IMPORTANT: Postgres grants EXECUTE on new functions to PUBLIC by default, so
-- revoking from anon/authenticated alone leaves the function wide open. It must
-- be revoked from PUBLIC and then granted back only to the service role that the
-- Edge Function uses. Without this a student can self-grant a free subscription.
revoke execute on function public.grant_subscription(uuid, text, text, text) from public;
revoke execute on function public.grant_subscription(uuid, text, text, text) from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.grant_subscription(uuid, text, text, text) to service_role;
  end if;
end $$;

-- admin can grant access by email (for bank transfer / offline students)
create or replace function public.admin_grant_access(p_email text, p_plan_id text, p_note text default 'manual')
returns public.subscriptions
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid; v_row public.subscriptions;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select id into v_uid from public.profiles where lower(email) = lower(trim(p_email));
  if v_uid is null then raise exception 'no student with email %', p_email; end if;
  v_row := public.grant_subscription(v_uid, p_plan_id, 'manual', p_note);
  return v_row;
end;
$$;
grant execute on function public.admin_grant_access(text, text, text) to authenticated;

-- admin can revoke
create or replace function public.admin_revoke_access(p_email text)
returns int
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid; v_n int;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select id into v_uid from public.profiles where lower(email) = lower(trim(p_email));
  if v_uid is null then raise exception 'no student with email %', p_email; end if;
  update public.subscriptions set status = 'cancelled'
   where user_id = v_uid and status = 'active';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
grant execute on function public.admin_revoke_access(text) to authenticated;

-- ---------- admin report: who is paying ----------
drop function if exists public.admin_billing_report();
create or replace function public.admin_billing_report()
returns table (
  email text, full_name text, plan_id text, status text,
  expires_at timestamptz, days_left int, source text,
  total_paid_paise bigint, payments bigint
)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return query
  select p.email, p.full_name, s.plan_id, s.status, s.expires_at,
    case when s.expires_at is null then null
         else greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int end,
    s.source,
    coalesce((select sum(pay.amount_paise) from public.payments pay
               where pay.user_id = p.id and pay.status = 'paid'), 0),
    (select count(*) from public.payments pay where pay.user_id = p.id and pay.status = 'paid')
  from public.profiles p
  left join public.subscriptions s
    on s.user_id = p.id and s.status = 'active' and s.expires_at > now()
  where p.role = 'student'
  order by s.expires_at desc nulls last, p.full_name;
end;
$$;
grant execute on function public.admin_billing_report() to authenticated;
