-- ============================================================
-- schema-08-projects.sql — projects, per-project access, invites, coupons
--
-- Until now access was one thing: an active subscription unlocked the whole
-- academy. That cannot express what a real cohort needs — one student on the RAG
-- project only, another on the agent project only, a third on the course with no
-- projects at all, a fourth on everything.
--
-- So access becomes a *grant*: a row saying this user may open this project,
-- optionally until a date. Four ways to get one, all landing in the same table
-- so there is exactly one place to look when a student says "I can't get in":
--
--   1. an admin grants it directly, by email
--   2. an admin uploads a spreadsheet of emails
--   3. an admin invites an email that has no account yet — the grant waits and
--      attaches itself the moment that address registers
--   4. a student redeems a coupon, which either grants immediately or raises a
--      request for an admin to approve
--
-- Run order: after schema-07. Idempotent — safe to run twice.
-- In the Supabase SQL editor choose "Run without RLS"; RLS is enabled below.
-- ============================================================

-- ============================================================
-- The registry. Adding a third project is an INSERT, not a deploy.
-- ============================================================
create table if not exists public.projects (
  id          text primary key,             -- 'rag', 'agents', …
  title       text not null,
  subtitle    text not null default '',     -- one line, shown on the tab
  blurb       text not null default '',      -- what the student is testing here
  console_url text,                          -- null = hosted inside the LMS
  sort_order  int  not null default 100,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Versions exist so the console can show "5.0 Real LLM" without hard-coding a
-- list, and so a future project can have a different number of them. Access is
-- granted per *project*: hold the RAG project and you hold all its versions.
create table if not exists public.project_versions (
  project_id text not null references public.projects(id) on delete cascade,
  id         text not null,                  -- 'v1' …
  label      text not null,
  summary    text not null default '',
  sort_order int  not null default 100,
  primary key (project_id, id)
);

-- ============================================================
-- The grant. One row per (student, project).
-- ============================================================
create table if not exists public.project_grants (
  user_id    uuid not null references auth.users(id) on delete cascade,
  project_id text not null references public.projects(id) on delete cascade,
  source     text not null default 'admin',  -- admin | import | invite | coupon
  note       text,
  granted_by uuid references auth.users(id),
  expires_at timestamptz,                    -- null = no expiry
  created_at timestamptz not null default now(),
  primary key (user_id, project_id)
);
create index if not exists project_grants_user on public.project_grants(user_id);

-- A grant made for an address that has not registered yet. This is the GitHub
-- invite model: the intent is recorded now and applied the moment the person
-- exists, so an admin never has to remember to come back and finish the job.
create table if not exists public.project_invites (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,                  -- stored lower-cased
  project_id text not null references public.projects(id) on delete cascade,
  invited_by uuid references auth.users(id),
  note       text,
  expires_at timestamptz,
  claimed_at timestamptz,
  claimed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create unique index if not exists project_invites_open
  on public.project_invites(email, project_id) where claimed_at is null;
create index if not exists project_invites_email on public.project_invites(lower(email));

-- ============================================================
-- Coupons. Two kinds, chosen per code:
--   auto_grant = true   the code is the authorisation; access opens on redeem
--   auto_grant = false  redeeming raises a request an admin approves
-- A leaked auto-grant code costs whatever is left on max_redemptions, which is
-- why that column is not nullable-by-default in practice — set it.
-- ============================================================
-- A coupon that also opens the course does it by naming a real plan from
-- public.plans, not by carrying its own day count. The first draft of this table
-- had `grants_course boolean` + `course_days int` and then called
-- grant_subscription(user, 'coupon', …) — but that function's second argument is
-- a plan_id, so it looked up a plan called 'coupon', found none, and raised
-- 'unknown plan coupon', which rolled back the entire redemption. Two columns
-- describing a duration the subscriptions table already knows how to compute is
-- the kind of duplication that goes wrong quietly; a foreign key to plans makes
-- an unredeemable coupon impossible to create in the first place.
create table if not exists public.coupons (
  code            text primary key,
  project_ids     text[] not null default '{}',
  plan_id         text references public.plans(id),  -- null = projects only, no course
  auto_grant      boolean not null default false,
  max_redemptions int,                              -- null = unlimited
  redeemed_count  int not null default 0,
  expires_at      timestamptz,
  active          boolean not null default true,
  note            text,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now()
);
-- For anyone who ran an earlier copy of this file: add the column, and let the
-- two dead ones sit there rather than dropping data on a re-run.
alter table public.coupons add column if not exists plan_id text references public.plans(id);

create table if not exists public.coupon_redemptions (
  id         uuid primary key default gen_random_uuid(),
  code       text not null references public.coupons(code) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'pending',  -- pending | approved | rejected
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  reason     text,
  created_at timestamptz not null default now()
);
create unique index if not exists coupon_redemptions_once
  on public.coupon_redemptions(code, user_id);
create index if not exists coupon_redemptions_pending
  on public.coupon_redemptions(status) where status = 'pending';

-- ============================================================
-- What the caller may open.
--
-- Admins get everything. Everyone else gets exactly their unexpired grants —
-- an active subscription does NOT imply project access, because the whole point
-- of this migration is that the two are separable.
-- ============================================================
create or replace function public.my_projects()
returns table (project_id text, title text, expires_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select p.id, p.title, null::timestamptz
    from public.projects p
   where p.active and public.is_admin()
  union
  select p.id, p.title, g.expires_at
    from public.project_grants g
    join public.projects p on p.id = g.project_id
   where g.user_id = auth.uid()
     and p.active
     and (g.expires_at is null or g.expires_at > now());
$$;
grant execute on function public.my_projects() to authenticated;

create or replace function public.can_open_project(p_project text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.my_projects() where project_id = p_project);
$$;
grant execute on function public.can_open_project(text) to authenticated;

-- ============================================================
-- Admin actions. SECURITY DEFINER, and executable by service_role only —
-- the lesson from schema-05: Postgres grants EXECUTE to PUBLIC by default, so
-- every one of these must be revoked from PUBLIC explicitly or any signed-in
-- student can call it.
-- ============================================================

-- Grant by email. If the address has no account yet the intent is stored as an
-- invite instead, and applied at sign-up. Returns what it did so the admin UI
-- can say "granted" or "invited — they have not registered yet".
create or replace function public.admin_grant_project(
  p_email text, p_project text, p_expires timestamptz default null, p_note text default null)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select id into v_user from public.profiles where lower(email) = lower(trim(p_email)) limit 1;

  if v_user is null then
    insert into public.project_invites (email, project_id, note, expires_at)
    values (lower(p_email), p_project, p_note, p_expires)
    on conflict (email, project_id) where claimed_at is null
      do update set note = excluded.note, expires_at = excluded.expires_at;
    return 'invited';
  end if;

  insert into public.project_grants (user_id, project_id, source, note, expires_at)
  values (v_user, p_project, 'admin', p_note, p_expires)
  on conflict (user_id, project_id)
    do update set expires_at = excluded.expires_at, note = excluded.note;
  return 'granted';
end;
$$;
-- The guard is the first line of the function itself (`is_admin()` or raise), which is
-- how admin_grant_access already works. Revoke from PUBLIC first regardless: Postgres
-- grants EXECUTE to PUBLIC on every new function, and that once let a student
-- self-grant a subscription.
--
-- `from public, anon` rather than `from public` alone, and the second name is the one
-- that does the work. Supabase ships an ALTER DEFAULT PRIVILEGES that grants EXECUTE
-- on every new function in this schema to anon, authenticated and service_role. That
-- is an explicit grant made at CREATE time, so revoking from PUBLIC afterwards leaves
-- it standing — which is how a signed-out visitor ended up holding EXECUTE on all
-- three admin functions after the first production run. They still failed closed,
-- because is_admin() is false when auth.uid() is null, but "cannot call it" beats
-- "raises when called".
revoke execute on function public.admin_grant_project(text, text, timestamptz, text) from public, anon;
grant  execute on function public.admin_grant_project(text, text, timestamptz, text) to authenticated;

create or replace function public.admin_revoke_project(p_email text, p_project text)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select id into v_user from public.profiles where lower(email) = lower(trim(p_email)) limit 1;
  delete from public.project_invites
   where lower(email) = lower(p_email) and project_id = p_project and claimed_at is null;
  if v_user is null then return 'invite withdrawn'; end if;
  delete from public.project_grants where user_id = v_user and project_id = p_project;
  return 'revoked';
end;
$$;
-- The guard is the first line of the function itself (`is_admin()` or raise), which is
-- how admin_grant_access already works. Revoke from PUBLIC first regardless: Postgres
-- grants EXECUTE to PUBLIC on every new function, and that once let a student
-- self-grant a subscription.
--
-- `from public, anon` rather than `from public` alone, and the second name is the one
-- that does the work. Supabase ships an ALTER DEFAULT PRIVILEGES that grants EXECUTE
-- on every new function in this schema to anon, authenticated and service_role. That
-- is an explicit grant made at CREATE time, so revoking from PUBLIC afterwards leaves
-- it standing — which is how a signed-out visitor ended up holding EXECUTE on all
-- three admin functions after the first production run. They still failed closed,
-- because is_admin() is false when auth.uid() is null, but "cannot call it" beats
-- "raises when called".
revoke execute on function public.admin_revoke_project(text, text) from public, anon;
grant  execute on function public.admin_revoke_project(text, text) to authenticated;

-- ============================================================
-- Redeeming a coupon. Runs as the student, so it must be paranoid: it checks
-- the code is real, active, unexpired and not exhausted, and it will not let one
-- account redeem the same code twice.
-- ============================================================
create or replace function public.redeem_coupon(p_code text)
returns table (status text, message text)
language plpgsql security definer set search_path = public
as $$
declare
  c public.coupons%rowtype;
  v_user uuid := auth.uid();
  pid text;
begin
  if v_user is null then
    return query select 'error', 'Sign in first.'; return;
  end if;

  select * into c from public.coupons where upper(code) = upper(p_code);
  if not found or not c.active then
    return query select 'error', 'That code is not valid.'; return;
  end if;
  if c.expires_at is not null and c.expires_at < now() then
    return query select 'error', 'That code has expired.'; return;
  end if;
  if c.max_redemptions is not null and c.redeemed_count >= c.max_redemptions then
    return query select 'error', 'That code has been fully used.'; return;
  end if;
  if exists (select 1 from public.coupon_redemptions
              where code = c.code and user_id = v_user) then
    return query select 'error', 'You have already used that code.'; return;
  end if;

  insert into public.coupon_redemptions (code, user_id, status)
  values (c.code, v_user, case when c.auto_grant then 'approved' else 'pending' end);

  update public.coupons set redeemed_count = redeemed_count + 1 where code = c.code;

  if c.auto_grant then
    foreach pid in array c.project_ids loop
      insert into public.project_grants (user_id, project_id, source, note)
      values (v_user, pid, 'coupon', c.code)
      on conflict (user_id, project_id) do nothing;
    end loop;
    if c.plan_id is not null then
      perform public.grant_subscription(v_user, c.plan_id, 'coupon', 'coupon:' || c.code);
    end if;
    -- `return query` appends rows and carries on; it is not `return`. Without the
    -- bare `return` below, an auto-grant redemption fell through to the pending
    -- branch as well and handed the caller two contradictory rows — "approved"
    -- and "pending" for the same code. Every other exit in this function pairs
    -- the two statements; this one did not.
    return query select 'approved', 'Unlocked. Open the projects page.';
    return;
  end if;

  return query select 'pending', 'Code accepted — an administrator will approve it shortly.';
  return;
end;
$$;
grant execute on function public.redeem_coupon(text) to authenticated;

create or replace function public.admin_decide_redemption(
  p_id uuid, p_approve boolean, p_reason text default null)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  r public.coupon_redemptions%rowtype;
  c public.coupons%rowtype;
  pid text;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select * into r from public.coupon_redemptions where id = p_id;
  if not found then return 'no such request'; end if;
  if r.status <> 'pending' then return 'already ' || r.status; end if;
  select * into c from public.coupons where code = r.code;

  update public.coupon_redemptions
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_at = now(), decided_by = auth.uid(), reason = p_reason
   where id = p_id;

  if not p_approve then
    -- give the seat back
    update public.coupons set redeemed_count = greatest(0, redeemed_count - 1)
     where code = r.code;
    return 'rejected';
  end if;

  foreach pid in array c.project_ids loop
    insert into public.project_grants (user_id, project_id, source, note)
    values (r.user_id, pid, 'coupon', c.code)
    on conflict (user_id, project_id) do nothing;
  end loop;
  -- Approving by hand must give exactly what auto-grant gives. This branch used
  -- to hand over the projects and silently skip the course, so the same code
  -- meant two different things depending on which path it took.
  if c.plan_id is not null then
    perform public.grant_subscription(r.user_id, c.plan_id, 'coupon', 'coupon:' || c.code);
  end if;
  return 'approved';
end;
$$;
-- The guard is the first line of the function itself (`is_admin()` or raise), which is
-- how admin_grant_access already works. Revoke from PUBLIC first regardless: Postgres
-- grants EXECUTE to PUBLIC on every new function, and that once let a student
-- self-grant a subscription.
--
-- `from public, anon` rather than `from public` alone, and the second name is the one
-- that does the work. Supabase ships an ALTER DEFAULT PRIVILEGES that grants EXECUTE
-- on every new function in this schema to anon, authenticated and service_role. That
-- is an explicit grant made at CREATE time, so revoking from PUBLIC afterwards leaves
-- it standing — which is how a signed-out visitor ended up holding EXECUTE on all
-- three admin functions after the first production run. They still failed closed,
-- because is_admin() is false when auth.uid() is null, but "cannot call it" beats
-- "raises when called".
revoke execute on function public.admin_decide_redemption(uuid, boolean, text) from public, anon;
grant  execute on function public.admin_decide_redemption(uuid, boolean, text) to authenticated;

-- ============================================================
-- Apply waiting invites at sign-up.
--
-- handle_new_user() already runs on every new auth.users row; this is a second
-- trigger rather than an edit to that one, so a mistake here cannot break
-- registration itself.
-- ============================================================
create or replace function public.claim_project_invites()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.project_grants (user_id, project_id, source, note, expires_at)
  select new.id, i.project_id, 'invite', i.note, i.expires_at
    from public.project_invites i
   where lower(i.email) = lower(new.email)
     and i.claimed_at is null
     and (i.expires_at is null or i.expires_at > now())
  on conflict (user_id, project_id) do nothing;

  update public.project_invites
     set claimed_at = now(), claimed_by = new.id
   where lower(email) = lower(new.email) and claimed_at is null;

  return new;
end;
$$;
drop trigger if exists on_auth_user_claim_invites on auth.users;
create trigger on_auth_user_claim_invites
  after insert on auth.users
  for each row execute function public.claim_project_invites();

-- ============================================================
-- RLS
-- ============================================================
alter table public.projects            enable row level security;
alter table public.project_versions    enable row level security;
alter table public.project_grants      enable row level security;
alter table public.project_invites     enable row level security;
alter table public.coupons             enable row level security;
alter table public.coupon_redemptions  enable row level security;

-- The catalogue is public: the projects page should be able to show what exists
-- and mark what the student cannot open yet. Knowing a project exists is not
-- access to it.
drop policy if exists "projects read"  on public.projects;
drop policy if exists "projects admin" on public.projects;
create policy "projects read"  on public.projects for select using (active or public.is_admin());
create policy "projects admin" on public.projects for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "versions read"  on public.project_versions;
drop policy if exists "versions admin" on public.project_versions;
create policy "versions read"  on public.project_versions for select using (true);
create policy "versions admin" on public.project_versions for all
  using (public.is_admin()) with check (public.is_admin());

-- A student may see their own grants and nobody else's.
drop policy if exists "grants read"  on public.project_grants;
drop policy if exists "grants admin" on public.project_grants;
create policy "grants read"  on public.project_grants for select
  using (auth.uid() = user_id or public.is_admin());
create policy "grants admin" on public.project_grants for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "invites admin" on public.project_invites;
create policy "invites admin" on public.project_invites for all
  using (public.is_admin()) with check (public.is_admin());

-- Coupon *codes* are never readable by students — being able to list them is
-- being able to use them. Redemption happens through redeem_coupon() only.
drop policy if exists "coupons admin" on public.coupons;
create policy "coupons admin" on public.coupons for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "redemptions read"  on public.coupon_redemptions;
drop policy if exists "redemptions admin" on public.coupon_redemptions;
create policy "redemptions read"  on public.coupon_redemptions for select
  using (auth.uid() = user_id or public.is_admin());
create policy "redemptions admin" on public.coupon_redemptions for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- Seed the two projects that exist today.
-- ============================================================
insert into public.projects (id, title, subtitle, blurb, console_url, sort_order) values
  ('rag', 'RAG project', 'answers questions from documents',
   'A retrieval-augmented travel assistant built five times, each version adding exactly one '
   'change. You test what was retrieved and whether the answer stayed inside it — hallucination, '
   'over-confidence, abstention, and answering from a document that lies.',
   'https://tripsage-rag-console.onrender.com', 10),
  ('agents', 'MCP agent project', 'plans a trip and spends money',
   'An orchestrator delegates a trip to sub-agents holding narrow sets of MCP tools. You test '
   'authority rather than accuracy: the flight agent can hold a seat but cannot book one, and no '
   'money moves without a confirmation token the system itself issued.',
   'https://tripsage-rag-console.onrender.com', 20)
on conflict (id) do update
  set title = excluded.title, subtitle = excluded.subtitle, blurb = excluded.blurb,
      console_url = excluded.console_url, sort_order = excluded.sort_order;

insert into public.project_versions (project_id, id, label, summary, sort_order) values
  ('rag', 'v1', '1.0  Baseline',  'Retrieval, grounding, a first pass at guardrails.', 10),
  ('rag', 'v2', '2.0  Wider KB',  'A larger, editable knowledge base.', 20),
  ('rag', 'v3', '3.0  Hardened',  'Vector-store inspection and stricter abstention.', 30),
  ('rag', 'v4', '4.0  Poisoning', 'Indirect-injection defences and provenance flags.', 40),
  ('rag', 'v5', '5.0  Real LLM',  'The same retrieval, a real model writes the answer.', 50),
  ('agents', 'concierge', 'Concierge', 'Multi-agent, over MCP.', 10)
on conflict (project_id, id) do update
  set label = excluded.label, summary = excluded.summary, sort_order = excluded.sort_order;

-- Every existing admin keeps everything by virtue of is_admin(). Students who
-- already paid keep the course; project access is now explicit, so grant it to
-- whoever should have it from Admin → Projects.
