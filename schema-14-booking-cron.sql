-- ============================================================
-- schema-14-booking-cron.sql — the thing that makes the outbox send
--
-- Run in Supabase → SQL editor, after schema-11-booking.sql. Safe to re-run.
--
-- schema-11 queues invitations, reschedules, cancellations and reminders into
-- public.email_outbox and stops there, on purpose: a booking must not fail
-- because a mail host is briefly down. But a queue nobody drains is just a
-- table that fills up. This file is the drain.
--
-- Three things live here.
--
--   1. A claim, so two overlapping runs cannot send the same invitation twice.
--   2. A reaper, so a run that dies mid-flight does not strand rows forever.
--   3. A schedule, so the sender is called without anyone remembering to.
--
-- Depends on: schema-11-booking.sql.
-- Requires:   pg_net and pg_cron, and one secret in Supabase Vault.
-- ============================================================

-- ---------- 1. EXTENSIONS ----------
-- pg_net posts to the edge function; pg_cron decides when.
--
-- GitHub Actions was the obvious alternative and is the wrong tool here:
-- GitHub throttles sub-hourly schedules hard — a */5 cron there executes
-- roughly one time in twenty, which would make a "24 hour reminder" arrive
-- whenever GitHub felt like it. pg_cron runs inside the database that already
-- holds the queue, on the schedule it was given.
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ---------- 2. A STATUS THAT MEANS "SOMEONE IS SENDING THIS" ----------
-- Without it, the sender's read-then-write pattern is a double-send waiting to
-- happen: it SELECTs up to 25 queued rows, then marks each one 'sent' as it
-- goes. Two runs that overlap — one slow batch against a stalling mail host,
-- the next tick arriving before it finished — both read the same rows and both
-- send them. The student gets two identical invitations and a duplicate
-- calendar entry, which is exactly the sort of fault that looks like the
-- system is broken rather than busy.
--
-- pg_net is fire-and-forget, so the schedule cannot know whether the previous
-- run is still working. The claim is what makes that safe.
do $$
begin
  alter table public.email_outbox drop constraint if exists email_outbox_status_check;
  alter table public.email_outbox add constraint email_outbox_status_check
    check (status in ('queued','sending','sent','failed','skipped'));
end $$;

-- Claimed rows are no longer 'queued', so the partial index that finds work
-- keeps doing its job; this one exists to find abandoned claims.
create index if not exists email_outbox_sending_idx
  on public.email_outbox (created_at) where status = 'sending';

-- ---------- 3. THE CLAIM ----------
-- FOR UPDATE SKIP LOCKED is the whole point: two callers arriving together
-- take disjoint sets rather than queueing behind each other or colliding.
create or replace function public.claim_outbox_batch(p_limit int default 25)
returns setof public.email_outbox
language plpgsql security definer set search_path = public
as $$
begin
  -- service_role only. This hands back recipients' email addresses and the
  -- full payload of every pending invitation, so it must never be reachable
  -- from a browser, admin or not.
  if auth.role() is distinct from 'service_role' then
    raise exception 'claim_outbox_batch is for the sender, not for callers';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 200 then
    p_limit := 25;
  end if;

  return query
  update public.email_outbox o
     set status = 'sending', attempts = o.attempts + 1
   where o.id in (
     select id from public.email_outbox
      where status = 'queued' and send_after <= now()
      order by send_after
      limit p_limit
      for update skip locked
   )
  returning o.*;
end $$;

revoke all on function public.claim_outbox_batch(int) from public, anon, authenticated;
grant execute on function public.claim_outbox_batch(int) to service_role;

-- ---------- 4. THE REAPER ----------
-- A claim is a promise to finish, and processes break promises: the function
-- times out, the runtime is recycled mid-batch, ZeptoMail hangs past the edge
-- runtime's wall clock. Those rows would sit at 'sending' forever and the
-- student would simply never be told about their call.
--
-- Fifteen minutes is deliberately longer than any plausible batch (25 messages
-- against a healthy mail host is seconds) and shorter than the gap between a
-- booking and the call it is about. Attempts is not incremented here — the
-- claim already counted it, and counting twice would retire a message after
-- two and a half real failures instead of five.
create or replace function public.release_stale_outbox(p_older_than interval default interval '15 minutes')
returns int
language plpgsql security definer set search_path = public
as $$
declare v_count int;
begin
  with released as (
    update public.email_outbox
       set status = case when attempts >= 5 then 'failed' else 'queued' end,
           last_error = coalesce(last_error, 'claimed but never completed')
     where status = 'sending'
       and created_at < now() - p_older_than
     returning 1)
  select count(*) into v_count from released;
  return v_count;
end $$;

revoke all on function public.release_stale_outbox(interval) from public, anon, authenticated;

-- ---------- 5. THE DRAIN ----------
-- Called by the schedule. Reaps, then posts to the edge function if — and only
-- if — there is something for it to do.
--
-- The "only if" matters on the free tier. A */5 schedule is 288 invocations a
-- day; an application with no bookings this week should spend none of them.
-- The count is one index-only scan against a partial index, which is cheaper
-- than the HTTP request it avoids by several orders of magnitude.
create or replace function public.drain_booking_outbox()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_due     int;
  v_freed   int;
  v_url     text;
  v_secret  text;
  v_request bigint;
begin
  v_freed := public.release_stale_outbox();

  select count(*) into v_due
    from public.email_outbox
   where status = 'queued' and send_after <= now();

  if v_due = 0 then
    return jsonb_build_object('posted', false, 'due', 0, 'released', v_freed);
  end if;

  -- Both read from Vault rather than written into this file or into the cron
  -- job's command text. cron.job is a readable table: a secret pasted into a
  -- schedule is a secret shown to everyone who can list the schedules, and it
  -- would have travelled into git with this file besides.
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'booking_hook_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'booking_hook_secret';

  if v_url is null or v_secret is null then
    -- Loud, and specific about which one is missing. A silent no-op here would
    -- present as "the emails just never arrive", which is the most expensive
    -- kind of failure to diagnose.
    raise exception 'drain_booking_outbox: % missing from Vault',
      case when v_url is null and v_secret is null then 'booking_hook_url and booking_hook_secret'
           when v_url is null then 'booking_hook_url'
           else 'booking_hook_secret' end;
  end if;

  select net.http_post(
    url     := v_url,
    body    := '{}'::jsonb,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-booking-secret', v_secret),
    timeout_milliseconds := 55000
  ) into v_request;

  return jsonb_build_object('posted', true, 'due', v_due,
                            'released', v_freed, 'request_id', v_request);
end $$;

revoke all on function public.drain_booking_outbox() from public, anon, authenticated;

-- ---------- 6. THE SCHEDULE ----------
-- pg_cron puts its tables in schema `cron`, but the extension's functions land
-- wherever it was created — pg_catalog on some Supabase projects, cron on
-- others. Looking the function up is shorter than asking which kind of project
-- this is.
do $$
declare v_schema text;
begin
  select n.nspname into v_schema
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where p.proname = 'schedule'
     and pg_get_function_identity_arguments(p.oid) = 'job_name text, schedule text, command text'
   limit 1;

  if v_schema is null then
    raise notice 'pg_cron is not installed — drain_booking_outbox() exists but nothing calls it.';
    return;
  end if;

  -- unschedule raises when the job is absent, which is the ordinary case on a
  -- first run, so it gets its own block rather than a precondition query.
  begin
    execute format('select %I.unschedule(%L)', v_schema, 'drain-booking-outbox');
  exception when others then null;
  end;

  execute format('select %I.schedule(%L, %L, %L)',
                 v_schema, 'drain-booking-outbox', '*/5 * * * *',
                 'select public.drain_booking_outbox();');
end $$;

-- ---------- 7. LOOKING AT IT AFTERWARDS ----------
-- pg_net answers asynchronously: http_post returns an id immediately and the
-- response arrives later in net._http_response. Without somewhere to look,
-- "did the sender actually reply 200?" is unanswerable.
create or replace function public.admin_outbox_health()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare r jsonb;
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;

  select jsonb_build_object(
    'queued',  count(*) filter (where status = 'queued'),
    'sending', count(*) filter (where status = 'sending'),
    'sent',    count(*) filter (where status = 'sent'),
    'failed',  count(*) filter (where status = 'failed'),
    'skipped', count(*) filter (where status = 'skipped'),
    'due_now', count(*) filter (where status = 'queued' and send_after <= now()),
    'oldest_due_minutes', coalesce(
       round(max(extract(epoch from now() - send_after))
             filter (where status = 'queued' and send_after <= now()) / 60)::int, 0),
    'last_error', (select last_error from public.email_outbox
                    where last_error is not null
                    order by id desc limit 1)
  ) into r
  from public.email_outbox;

  return r;
end $$;

grant execute on function public.admin_outbox_health() to authenticated;

-- ---------- 8. WHAT TO DO NEXT ----------
-- 1. Put the two values in Vault (Supabase → Project Settings → Vault, or here):
--
--      select vault.create_secret(
--        'https://<project-ref>.supabase.co/functions/v1/send-booking-email',
--        'booking_hook_url', 'where the booking sender lives');
--
--      select vault.create_secret(
--        '<the same string you set as BOOKING_HOOK_SECRET>',
--        'booking_hook_secret', 'shared secret for the booking sender');
--
--    To change one later, vault.update_secret(id, new_value) — create_secret
--    will not overwrite a name that already exists.
--
-- 2. Deploy send-booking-email with JWT verification OFF. It authenticates
--    with the shared secret instead, because its caller is a schedule rather
--    than a person with a session.
--
-- 3. Check it: select public.drain_booking_outbox();
--    'posted', false with 'due', 0 means there is simply nothing waiting.
--    Then: select * from net._http_response order by id desc limit 1;
--
-- 4. Watch it: select public.admin_outbox_health();
--    A 'sending' count that never falls means the sender is dying mid-batch;
--    a rising 'due_now' with oldest_due_minutes past 10 means nothing is
--    calling it at all.
