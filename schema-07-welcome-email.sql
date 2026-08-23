-- ============================================================
-- GenAITesting — migration 07: welcome email
-- Run in: Supabase Dashboard → SQL Editor → New query → Run.
-- Safe to re-run. If the linter complains, choose "Run without RLS".
--
-- Sends one welcome email the first time a student enrols, whichever door they
-- came through — Google, GitHub or email + password. Google and GitHub students
-- currently receive no email from us at all, so this is their only touchpoint.
-- ============================================================

-- ---------- 1. Columns on profiles ----------
alter table public.profiles
  add column if not exists welcome_email_sent_at timestamptz,
  add column if not exists marketing_opt_out     boolean not null default false,
  add column if not exists unsubscribe_token      uuid    not null default gen_random_uuid();

comment on column public.profiles.welcome_email_sent_at is
  'Stamped when the welcome email is accepted by ZeptoMail. Non-null means never send again.';
comment on column public.profiles.marketing_opt_out is
  'Set by the student via the unsubscribe link. Suppresses this and any future non-essential mail.';
comment on column public.profiles.unsubscribe_token is
  'Random per-student token used in the unsubscribe URL, so the link reveals nothing and cannot be guessed.';

create unique index if not exists profiles_unsub_token_idx on public.profiles (unsubscribe_token);

-- Students must not be able to rewrite their own send-state or token. Only the
-- two columns they legitimately own stay writable (see migration 01, which
-- revoked UPDATE and re-granted full_name/avatar_url).
revoke update (welcome_email_sent_at, marketing_opt_out, unsubscribe_token)
  on public.profiles from anon, authenticated;

-- ---------- 2. Delivery log ----------
-- One row per send attempt. Lets you answer "did this student get it, and when?"
-- without digging through ZeptoMail, and makes a failed send visible instead of silent.
create table if not exists public.email_log (
  id          bigserial primary key,
  user_id     uuid references public.profiles(id) on delete set null,
  to_email    text not null,
  kind        text not null default 'welcome',
  status      text not null check (status in ('sent','failed','skipped')),
  detail      text,
  created_at  timestamptz not null default now()
);
create index if not exists email_log_user_idx on public.email_log (user_id, created_at desc);

alter table public.email_log enable row level security;
-- Only admins can read it; nothing but the service role writes to it.
drop policy if exists "email log admin read" on public.email_log;
create policy "email log admin read" on public.email_log
  for select using (public.is_admin());

revoke all on public.email_log from anon, authenticated;
grant select on public.email_log to authenticated;   -- RLS above still limits this to admins

-- ---------- 3. Who is still owed a welcome ----------
-- The Edge Function calls this rather than reading profiles directly, so the
-- "should we send?" rule lives in one place: never sent, not opted out, and the
-- address is confirmed (OAuth accounts are confirmed the moment they're created).
create or replace function public.pending_welcome(p_user_id uuid)
returns table (user_id uuid, email text, full_name text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.email, coalesce(p.full_name, split_part(p.email, '@', 1))
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_user_id
    and p.welcome_email_sent_at is null
    and p.marketing_opt_out = false
    and p.email is not null
    and u.email_confirmed_at is not null;
$$;

revoke execute on function public.pending_welcome(uuid) from public, anon, authenticated;
grant  execute on function public.pending_welcome(uuid) to service_role;

-- ---------- 4. Mark as sent ----------
create or replace function public.mark_welcome_sent(p_user_id uuid, p_status text, p_detail text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email from public.profiles where id = p_user_id;

  insert into public.email_log (user_id, to_email, kind, status, detail)
  values (p_user_id, coalesce(v_email, 'unknown'), 'welcome', p_status, p_detail);

  -- Only a genuine send closes the door. A failure stays open so a retry can pick it up.
  if p_status = 'sent' then
    update public.profiles set welcome_email_sent_at = now() where id = p_user_id;
  end if;
end;
$$;

revoke execute on function public.mark_welcome_sent(uuid, text, text) from public, anon, authenticated;
grant  execute on function public.mark_welcome_sent(uuid, text, text) to service_role;

-- ---------- 5. Unsubscribe ----------
-- Callable by anyone holding the token, which only ever appears in that student's
-- own email. Takes no session, so the link works from any mail client.
create or replace function public.unsubscribe_by_token(p_token uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  update public.profiles
     set marketing_opt_out = true
   where unsubscribe_token = p_token
  returning id into v_id;

  if v_id is null then
    return false;
  end if;

  insert into public.email_log (user_id, to_email, kind, status, detail)
  select v_id, coalesce(email, 'unknown'), 'unsubscribe', 'skipped', 'student opted out'
  from public.profiles where id = v_id;

  return true;
end;
$$;

revoke execute on function public.unsubscribe_by_token(uuid) from public;
grant  execute on function public.unsubscribe_by_token(uuid) to anon, authenticated;

-- ---------- 6. Don't email the students you already have ----------
-- Everyone who signed up before this migration is treated as already welcomed,
-- so switching this on doesn't blast your existing roster.
update public.profiles
   set welcome_email_sent_at = now()
 where welcome_email_sent_at is null;

-- ---------- Check it worked ----------
--   select email, welcome_email_sent_at, marketing_opt_out from public.profiles order by created_at desc limit 10;
--   select * from public.email_log order by created_at desc limit 20;
--
-- To re-arm one account for testing (use your own):
--   update public.profiles set welcome_email_sent_at = null where email = 'you@example.com';
