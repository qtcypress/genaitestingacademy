-- ============================================================
-- schema-11-booking.sql — one-to-one and group sessions, inside the LMS
--
-- Run in Supabase → SQL editor. Safe to re-run; every object is guarded.
--
-- Why this is not Calendly. Calendly solves "pick a slot" and stops there. The
-- things actually wanted here — an admin queue, outcome notes that become the
-- student's own action items, a status the student can change and the admin can
-- see, meeting history and a growth view — are all rows that belong beside the
-- student they describe. Putting the calendar in a second system would mean
-- syncing those rows back, and a sync is a thing that breaks quietly. Calendly's
-- free tier also excludes Google Meet, which was the integration asked for.
--
-- The shape, in one paragraph: an EVENT TYPE is a template ("Career guidance,
-- 30 minutes, one seat"). A SESSION is one concrete occurrence of it at a real
-- time. A BOOKING is one student's seat in a session. One-to-one and one-to-many
-- are then the same mechanism with a different `capacity`: at capacity 1 the
-- student's booking creates the session, and above 1 the admin publishes the
-- session first and students take seats in it. Two tables, not two subsystems.
--
-- Depends on: schema.sql (profiles, is_admin), schema-05-billing (has_active_access).
-- ============================================================

-- Needed for the exclusion constraint that stops a host being double-booked.
-- btree_gist lets a plain uuid sit in the same GiST index as a time range.
create extension if not exists btree_gist;

-- ---------- 1. EVENT TYPES ----------
-- The template a student picks from. `capacity` is the only thing that decides
-- whether this is a one-to-one or a group session, which is why there is no
-- "kind" column: a kind column could disagree with the capacity, and then one of
-- them would be a lie.
create table if not exists public.event_types (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique,
  title          text not null,
  description    text,
  host_id        uuid not null references public.profiles(id) on delete cascade,
  duration_min   int  not null check (duration_min between 5 and 480),
  capacity       int  not null default 1 check (capacity >= 1),

  -- Minutes of protected time after a session before the next may start. Back
  -- to back calls are how an admin ends up late to all of them.
  buffer_min     int  not null default 10 check (buffer_min >= 0),

  -- How far ahead a student may book, and how little notice they may give.
  horizon_days   int  not null default 30 check (horizon_days between 1 and 365),
  min_notice_min int  not null default 120 check (min_notice_min >= 0),

  -- Where the meeting happens. `meeting_url` is pasted once per event type and
  -- every session inherits it unless that session overrides it. Auto-created
  -- per-booking links (Google Calendar API, Zoom API) are a later phase: when
  -- they arrive they set sessions.meeting_url per session and nothing else here
  -- changes, which is the whole reason provider is a column and not a guess
  -- parsed back out of the URL.
  provider       text not null default 'google_meet'
                 check (provider in ('google_meet','zoom','teams','phone','in_person','other')),
  meeting_url    text,
  location_note  text,

  -- Who may book it. 'anyone' covers a free discovery call; 'subscriber'
  -- restricts it to students with live access.
  audience       text not null default 'subscriber'
                 check (audience in ('anyone','subscriber')),

  active         boolean not null default true,
  sort_order     int not null default 100,
  created_at     timestamptz not null default now()
);

-- ---------- 2. WHEN THE HOST IS AVAILABLE ----------
-- Weekly recurring windows, held in the host's own timezone as a wall-clock
-- time. Storing "Tuesdays, 18:00 Asia/Kolkata" rather than a timestamptz is
-- deliberate: the host means six in the evening where they live, and that must
-- stay six in the evening across a daylight-saving change in the student's
-- country. Converting to UTC once at write time would freeze the wrong thing.
create table if not exists public.availability_rules (
  id         uuid primary key default gen_random_uuid(),
  host_id    uuid not null references public.profiles(id) on delete cascade,
  weekday    int  not null check (weekday between 1 and 7),   -- ISO: 1 = Monday
  start_time time not null,
  end_time   time not null,
  timezone   text not null default 'Asia/Kolkata',
  active     boolean not null default true,
  check (end_time > start_time)
);

-- A date the host is simply not available, whatever the weekly rule says.
-- Holidays, travel, a day already full of something else.
create table if not exists public.availability_blocks (
  id         uuid primary key default gen_random_uuid(),
  host_id    uuid not null references public.profiles(id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  reason     text,
  check (ends_at > starts_at)
);

-- ---------- 3. SESSIONS ----------
-- One concrete meeting. `seats_taken` is denormalised on purpose: the capacity
-- check has to happen while holding a lock on exactly one row, and counting
-- bookings in a subquery would let two students pass the check at once and both
-- insert. It is maintained by trigger below, never by hand.
create table if not exists public.sessions (
  id             uuid primary key default gen_random_uuid(),
  event_type_id  uuid not null references public.event_types(id) on delete cascade,
  host_id        uuid not null references public.profiles(id) on delete cascade,
  starts_at      timestamptz not null,
  ends_at        timestamptz not null,
  capacity       int not null check (capacity >= 1),
  seats_taken    int not null default 0 check (seats_taken >= 0),
  status         text not null default 'scheduled'
                 check (status in ('scheduled','cancelled','completed')),

  -- Overrides the event type's link when a session needs its own room.
  meeting_url    text,

  -- Bumped on every change that attendees must be told about. This is the ICS
  -- SEQUENCE: a calendar client only replaces an event it already holds if the
  -- replacement carries a higher sequence with the same UID, so an off-by-one
  -- here shows up as "the reschedule email did nothing".
  ics_sequence   int not null default 0,

  title          text,
  notes          text,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  check (ends_at > starts_at)
);

-- The host cannot be in two places at once. Enforced by the database rather
-- than by the booking function, because the function is not the only thing that
-- can insert a row — an admin creating a group session by hand goes through a
-- different path and must hit the same wall.
--
-- Cancelled sessions are excluded: a cancelled 4pm must not block a new 4pm.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sessions_no_host_overlap') then
    alter table public.sessions add constraint sessions_no_host_overlap
      exclude using gist (
        host_id with =,
        tstzrange(starts_at, ends_at) with &&
      ) where (status = 'scheduled');
  end if;
end $$;

create index if not exists sessions_upcoming_idx
  on public.sessions (starts_at) where status = 'scheduled';

-- ---------- 4. BOOKINGS ----------
create table if not exists public.bookings (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'booked'
              check (status in ('booked','cancelled','attended','no_show')),

  -- What the student wants out of the call. The single most useful field here:
  -- an admin who reads this before the call runs a different conversation.
  agenda      text,

  cancelled_at     timestamptz,
  cancelled_by     uuid references public.profiles(id) on delete set null,
  cancel_reason    text,
  created_at  timestamptz not null default now()
);

-- One live seat per student per session. Partial, so a student who cancels can
-- book the same session again later rather than being locked out by their own
-- cancellation.
create unique index if not exists bookings_one_live_seat
  on public.bookings (session_id, user_id) where status = 'booked';

create index if not exists bookings_user_idx on public.bookings (user_id, created_at desc);

-- Keep seats_taken true to the bookings, in the same transaction as the booking.
create or replace function public.sync_seats_taken()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_session uuid;
begin
  v_session := coalesce(new.session_id, old.session_id);
  update public.sessions s
     set seats_taken = (
       -- 'attended' counts too. Recording an outcome flips every seat from
       -- 'booked' to 'attended', and counting only 'booked' made a finished
       -- session report zero attendees — so the admin queue showed a call that
       -- had just happened as nobody having turned up.
       select count(*) from public.bookings b
        where b.session_id = v_session and b.status in ('booked','attended'))
   where s.id = v_session;
  return null;
end $$;

drop trigger if exists bookings_sync_seats on public.bookings;
create trigger bookings_sync_seats
  after insert or update or delete on public.bookings
  for each row execute function public.sync_seats_taken();

-- ---------- 5. OUTCOMES AND ACTION ITEMS ----------
-- What the call produced. The admin writes this once; the student reads it for
-- as long as they are on the course, which is the point of keeping it here
-- rather than in the admin's own notes app.
create table if not exists public.session_outcomes (
  session_id  uuid primary key references public.sessions(id) on delete cascade,
  summary     text not null,
  author_id   uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- An outcome becomes tasks the student owns. They move the status; the admin
-- sees the status move. That two-way visibility is the entire feature — a task
-- list only the admin can change is a report, not a plan.
create table if not exists public.action_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  session_id  uuid references public.sessions(id) on delete set null,
  title       text not null,
  detail      text,
  status      text not null default 'open'
              check (status in ('open','in_progress','done','dropped')),
  due_on      date,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists action_items_user_idx
  on public.action_items (user_id, status, created_at desc);

-- ---------- 6. OUTBOUND EMAIL ----------
-- A queue, not a direct send. Three reasons it is a table: a booking must not
-- fail because a mail host was briefly down; the edge function can be given the
-- token later and will then find everything waiting for it; and every invite,
-- change and cancellation is auditable afterwards without reading the mail
-- provider's dashboard.
create table if not exists public.email_outbox (
  id           bigserial primary key,
  kind         text not null
               check (kind in ('booking_confirmed','booking_rescheduled',
                               'booking_cancelled','booking_reminder',
                               'session_cancelled')),
  to_email     text not null,
  to_name      text,
  user_id      uuid references public.profiles(id) on delete set null,
  session_id   uuid references public.sessions(id) on delete cascade,
  booking_id   uuid references public.bookings(id) on delete cascade,

  -- Everything the renderer needs, captured at queue time. Deliberately a
  -- snapshot: an email about a session that was then deleted should still say
  -- what it said, and a renderer that re-reads live rows would either crash or
  -- quietly describe the wrong thing.
  payload      jsonb not null default '{}'::jsonb,

  -- The ICS identity. uid is stable for the life of the session so a client can
  -- match an update to the event it already holds; sequence is the session's at
  -- queue time.
  ics_uid      text,
  ics_sequence int not null default 0,

  status       text not null default 'queued'
               check (status in ('queued','sent','failed','skipped')),
  attempts     int not null default 0,
  last_error   text,
  send_after   timestamptz not null default now(),
  sent_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists email_outbox_pending_idx
  on public.email_outbox (send_after) where status = 'queued';

-- ---------- 7. ROW LEVEL SECURITY ----------
-- Table privileges first. Supabase's default privileges already grant these to
-- anon and authenticated for anything created in `public`, so on a real project
-- these lines change nothing — they are here so the file can be applied to a
-- plain Postgres (a test harness, a staging copy) and behave identically.
-- RLS below is what actually decides who sees what; a grant without a policy
-- grants access to nothing.
grant select on public.event_types, public.availability_rules, public.sessions
  to anon;
grant select on public.event_types, public.availability_rules,
                public.availability_blocks, public.sessions, public.bookings,
                public.session_outcomes, public.action_items, public.email_outbox
  to authenticated;

alter table public.event_types        enable row level security;
alter table public.availability_rules enable row level security;
alter table public.availability_blocks enable row level security;
alter table public.sessions           enable row level security;
alter table public.bookings           enable row level security;
alter table public.session_outcomes   enable row level security;
alter table public.action_items       enable row level security;
alter table public.email_outbox       enable row level security;

-- Event types are a menu; an unauthenticated visitor may read the active ones
-- so the booking page can render before sign-in.
drop policy if exists "event types read"  on public.event_types;
drop policy if exists "event types admin" on public.event_types;
create policy "event types read" on public.event_types for select
  using (active or public.is_admin());
create policy "event types admin" on public.event_types for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "availability read"  on public.availability_rules;
drop policy if exists "availability admin" on public.availability_rules;
create policy "availability read" on public.availability_rules for select using (true);
create policy "availability admin" on public.availability_rules for all
  using (public.is_admin()) with check (public.is_admin());

-- Blocks are admin-only to read: "busy 3–5pm, reason: hospital" is the host's
-- business. open_slots() runs as definer and subtracts them without exposing them.
drop policy if exists "blocks admin" on public.availability_blocks;
create policy "blocks admin" on public.availability_blocks for all
  using (public.is_admin()) with check (public.is_admin());

-- A student may see a session they hold a seat in, and any group session with
-- seats left that they could still join. They may not browse someone else's
-- one-to-one.
drop policy if exists "sessions read"  on public.sessions;
drop policy if exists "sessions admin" on public.sessions;
create policy "sessions read" on public.sessions for select
  using (
    public.is_admin()
    or exists (select 1 from public.bookings b
                where b.session_id = sessions.id and b.user_id = auth.uid())
    or (capacity > 1 and status = 'scheduled')
  );
create policy "sessions admin" on public.sessions for all
  using (public.is_admin()) with check (public.is_admin());

-- A student sees their own bookings and nobody else's. Note this is read-only:
-- every write goes through the functions below, so the capacity and notice
-- rules cannot be stepped around with a direct insert.
drop policy if exists "bookings read"  on public.bookings;
drop policy if exists "bookings admin" on public.bookings;
create policy "bookings read" on public.bookings for select
  using (user_id = auth.uid() or public.is_admin());
create policy "bookings admin" on public.bookings for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "outcomes read"  on public.session_outcomes;
drop policy if exists "outcomes admin" on public.session_outcomes;
create policy "outcomes read" on public.session_outcomes for select
  using (
    public.is_admin()
    or exists (select 1 from public.bookings b
                where b.session_id = session_outcomes.session_id
                  and b.user_id = auth.uid())
  );
create policy "outcomes admin" on public.session_outcomes for all
  using (public.is_admin()) with check (public.is_admin());

-- The student may change the status of their own action items and nothing else
-- about them. The column guard lives in set_action_item_status(); this policy
-- keeps other people's items invisible.
drop policy if exists "action items read"  on public.action_items;
drop policy if exists "action items admin" on public.action_items;
create policy "action items read" on public.action_items for select
  using (user_id = auth.uid() or public.is_admin());
create policy "action items admin" on public.action_items for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "outbox admin" on public.email_outbox;
create policy "outbox admin" on public.email_outbox for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 7b. DROP BEFORE REPLACE ----------
-- `create or replace function` refuses to change a function's OUT columns, so
-- a later version of this file that adds a field to my_bookings would fail on a
-- database where the earlier version had already run — with "cannot change
-- return type of existing function", which reads like a syntax error and is not.
-- Dropping first makes the re-run promise in the header true across versions,
-- not merely across identical copies. Signatures are spelled out because an
-- unqualified drop is ambiguous once a name is overloaded.
drop function if exists public.open_slots(uuid, timestamptz, timestamptz);
drop function if exists public.book_slot(uuid, timestamptz, text);
drop function if exists public.join_session(uuid, text);
drop function if exists public.cancel_booking(uuid, text);
drop function if exists public.reschedule_booking(uuid, timestamptz);
drop function if exists public.my_bookings(boolean);
drop function if exists public.open_group_sessions();
drop function if exists public.my_action_items(boolean);
drop function if exists public.set_action_item_status(uuid, text);
drop function if exists public.admin_create_group_session(uuid, timestamptz, int, text, text);
drop function if exists public.admin_cancel_session(uuid, text);
drop function if exists public.admin_upcoming_sessions(int);
drop function if exists public.admin_record_outcome(uuid, text, jsonb);
drop function if exists public.admin_student_history(text);

-- ---------- 8. QUEUEING AN EMAIL ----------
-- Internal. Snapshots everything the renderer needs so the row stands alone.
create or replace function public.queue_booking_email(
  p_kind text, p_booking_id uuid, p_extra jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare r record;
begin
  select b.id as booking_id, b.user_id, b.agenda,
         s.id as session_id, s.starts_at, s.ends_at, s.ics_sequence,
         coalesce(s.meeting_url, e.meeting_url) as meeting_url,
         coalesce(s.title, e.title) as title,
         e.description, e.provider, e.duration_min, e.location_note,
         p.email, coalesce(p.full_name, split_part(p.email, '@', 1)) as full_name,
         hp.email as host_email,
         coalesce(hp.full_name, 'GenAITesting') as host_name
    into r
    from public.bookings b
    join public.sessions s    on s.id = b.session_id
    join public.event_types e on e.id = s.event_type_id
    join public.profiles p    on p.id = b.user_id
    left join public.profiles hp on hp.id = s.host_id
   where b.id = p_booking_id;

  if not found or r.email is null then return; end if;

  insert into public.email_outbox
    (kind, to_email, to_name, user_id, session_id, booking_id,
     ics_uid, ics_sequence, payload, send_after)
  values (
    p_kind, r.email, r.full_name, r.user_id, r.session_id, r.booking_id,
    -- Stable for the life of the session, which is what lets a calendar client
    -- recognise an update as the same event rather than adding a second one.
    'session-' || r.session_id::text || '@genaitesting.online',
    r.ics_sequence,
    jsonb_build_object(
      'title', r.title, 'description', r.description,
      'starts_at', r.starts_at, 'ends_at', r.ends_at,
      'meeting_url', r.meeting_url, 'provider', r.provider,
      'location_note', r.location_note,
      'duration_min', r.duration_min, 'agenda', r.agenda,
      'host_name', r.host_name, 'host_email', r.host_email,
      'student_name', r.full_name
    ) || coalesce(p_extra, '{}'::jsonb),
    case when p_kind = 'booking_reminder'
         then r.starts_at - interval '24 hours' else now() end
  );
end $$;

revoke all on function public.queue_booking_email(text, uuid, jsonb) from public, anon, authenticated;

-- ---------- 9. WHICH SLOTS ARE OPEN ----------
-- Generated from the weekly rules, minus blocks, minus anything already on the
-- host's calendar, minus whatever falls inside the notice window. Computed on
-- read rather than materialised: a table of empty slots would have to be
-- regenerated every time a rule changed, and would be wrong in between.
create or replace function public.open_slots(
  p_event_type uuid,
  p_from timestamptz default now(),
  p_to   timestamptz default null)
returns table (slot_start timestamptz, slot_end timestamptz)
language plpgsql stable security definer set search_path = public
as $$
declare e record; v_to timestamptz; v_from timestamptz;
begin
  select * into e from public.event_types where id = p_event_type and active;
  if not found then return; end if;

  -- A student cannot book inside the notice window even if the slot is free.
  v_from := greatest(p_from, now() + make_interval(mins => e.min_notice_min));
  v_to   := least(coalesce(p_to, now() + make_interval(days => e.horizon_days)),
                  now() + make_interval(days => e.horizon_days));
  if v_to <= v_from then return; end if;

  return query
  with days as (
    select generate_series(
      (v_from at time zone 'UTC')::date - 1,
      (v_to   at time zone 'UTC')::date + 1,
      interval '1 day')::date as d
  ),
  candidates as (
    select
      -- Built in the host's timezone so "18:00 Tuesday" survives a DST shift.
      ((d + r.start_time) at time zone r.timezone)
        + make_interval(mins => g * e.duration_min) as s_start,
      ((d + r.start_time) at time zone r.timezone)
        + make_interval(mins => (g + 1) * e.duration_min) as s_end,
      ((d + r.end_time) at time zone r.timezone) as window_end
    from days
    join public.availability_rules r
      on r.host_id = e.host_id
     and r.active
     and r.weekday = extract(isodow from d)::int
    cross join generate_series(0, 95) as g
  )
  select c.s_start, c.s_end
    from candidates c
   where c.s_end <= c.window_end
     and c.s_start >= v_from
     and c.s_start <  v_to
     -- not inside a declared block
     and not exists (
       select 1 from public.availability_blocks ab
        where ab.host_id = e.host_id
          and tstzrange(ab.starts_at, ab.ends_at) && tstzrange(c.s_start, c.s_end))
     -- not colliding with an existing session, buffer included
     and not exists (
       select 1 from public.sessions s
        where s.host_id = e.host_id
          and s.status = 'scheduled'
          and tstzrange(s.starts_at - make_interval(mins => e.buffer_min),
                        s.ends_at   + make_interval(mins => e.buffer_min))
              && tstzrange(c.s_start, c.s_end))
   order by c.s_start;
end $$;

grant execute on function public.open_slots(uuid, timestamptz, timestamptz) to anon, authenticated;

-- ---------- 10. BOOKING ----------
-- One-to-one: the student's booking is what creates the session. The exclusion
-- constraint is the real guard against two students taking the same time — the
-- check below is only there to turn a constraint violation into a sentence a
-- person can read.
create or replace function public.book_slot(
  p_event_type uuid, p_starts_at timestamptz, p_agenda text default null)
returns table (ok boolean, message text, booking_id uuid, session_id uuid)
language plpgsql security definer set search_path = public
as $$
declare e record; v_session uuid; v_booking uuid; v_ends timestamptz;
begin
  if auth.uid() is null then
    return query select false, 'Please sign in first.', null::uuid, null::uuid; return;
  end if;

  select * into e from public.event_types where id = p_event_type and active;
  if not found then
    return query select false, 'That session type is not available.', null::uuid, null::uuid; return;
  end if;

  if e.audience = 'subscriber' and not public.has_active_access() and not public.is_admin() then
    return query select false,
      'This session is for subscribers. Your access is not active yet.',
      null::uuid, null::uuid; return;
  end if;

  if p_starts_at < now() + make_interval(mins => e.min_notice_min) then
    return query select false,
      format('Please book at least %s minutes ahead.', e.min_notice_min),
      null::uuid, null::uuid; return;
  end if;

  -- The offered slot must be one open_slots would have offered. Without this a
  -- crafted request could book 3am on a day the host never works, because the
  -- exclusion constraint only knows about collisions, not about availability.
  if not exists (
    select 1 from public.open_slots(p_event_type, p_starts_at - interval '1 minute',
                                    p_starts_at + interval '1 minute') o
     where o.slot_start = p_starts_at) then
    return query select false,
      'That time is no longer open. Please pick another.', null::uuid, null::uuid; return;
  end if;

  v_ends := p_starts_at + make_interval(mins => e.duration_min);

  begin
    insert into public.sessions
      (event_type_id, host_id, starts_at, ends_at, capacity, status,
       meeting_url, title, created_by)
    values (e.id, e.host_id, p_starts_at, v_ends, e.capacity, 'scheduled',
            e.meeting_url, e.title, auth.uid())
    returning id into v_session;
  exception when exclusion_violation then
    return query select false,
      'Someone just took that time. Please pick another.', null::uuid, null::uuid; return;
  end;

  insert into public.bookings (session_id, user_id, agenda)
  values (v_session, auth.uid(), p_agenda)
  returning id into v_booking;

  perform public.queue_booking_email('booking_confirmed', v_booking);
  perform public.queue_booking_email('booking_reminder',  v_booking);

  return query select true, 'Booked.', v_booking, v_session;
end $$;

grant execute on function public.book_slot(uuid, timestamptz, text) to authenticated;

-- Group sessions: the admin publishes the session, students take seats. The row
-- lock is what makes the capacity check safe — two students arriving in the same
-- millisecond serialise on it, and the second one sees the first one's seat.
create or replace function public.join_session(
  p_session uuid, p_agenda text default null)
returns table (ok boolean, message text, booking_id uuid)
language plpgsql security definer set search_path = public
as $$
declare s record; e record; v_booking uuid;
begin
  if auth.uid() is null then
    return query select false, 'Please sign in first.', null::uuid; return;
  end if;

  select * into s from public.sessions where id = p_session for update;
  if not found or s.status <> 'scheduled' then
    return query select false, 'That session is not open.', null::uuid; return;
  end if;

  select * into e from public.event_types where id = s.event_type_id;

  if e.audience = 'subscriber' and not public.has_active_access() and not public.is_admin() then
    return query select false,
      'This session is for subscribers. Your access is not active yet.', null::uuid; return;
  end if;

  if s.starts_at < now() + make_interval(mins => coalesce(e.min_notice_min, 0)) then
    return query select false, 'That session starts too soon to join.', null::uuid; return;
  end if;

  if exists (select 1 from public.bookings b
              where b.session_id = p_session and b.user_id = auth.uid()
                and b.status = 'booked') then
    return query select false, 'You are already booked on this one.', null::uuid; return;
  end if;

  if s.seats_taken >= s.capacity then
    return query select false, 'That session is full.', null::uuid; return;
  end if;

  insert into public.bookings (session_id, user_id, agenda)
  values (p_session, auth.uid(), p_agenda)
  returning id into v_booking;

  perform public.queue_booking_email('booking_confirmed', v_booking);
  perform public.queue_booking_email('booking_reminder',  v_booking);

  return query select true, 'Booked.', v_booking;
end $$;

grant execute on function public.join_session(uuid, text) to authenticated;

-- ---------- 11. CANCEL AND RESCHEDULE ----------
create or replace function public.cancel_booking(
  p_booking uuid, p_reason text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare b record; s record;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then
    return query select false, 'Booking not found.'; return;
  end if;
  if b.user_id <> auth.uid() and not public.is_admin() then
    return query select false, 'That is not your booking.'; return;
  end if;
  if b.status <> 'booked' then
    return query select false, 'That booking is already closed.'; return;
  end if;

  -- Queue the email while the rows still describe the meeting being cancelled.
  -- Afterwards would work too, but only because of the snapshot in the payload,
  -- and relying on that would be relying on an implementation detail.
  perform public.queue_booking_email('booking_cancelled', p_booking,
    jsonb_build_object('cancel_reason', p_reason));

  update public.bookings
     set status = 'cancelled', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   where id = p_booking;

  -- A one-to-one with nobody left in it is not a meeting. Freeing the slot also
  -- releases it back to open_slots for the next student.
  select * into s from public.sessions where id = b.session_id;
  if s.capacity = 1 then
    update public.sessions set status = 'cancelled' where id = s.id;
  end if;

  -- The reminder is now about a meeting that is not happening.
  delete from public.email_outbox
   where booking_id = p_booking and kind = 'booking_reminder' and status = 'queued';

  return query select true, 'Cancelled.';
end $$;

grant execute on function public.cancel_booking(uuid, text) to authenticated;

-- Reschedule is a move, not a cancel-and-rebook: the session keeps its id, so
-- the ICS UID is unchanged and the attendee's calendar updates the event in
-- place instead of leaving the old one behind and adding a second.
create or replace function public.reschedule_booking(
  p_booking uuid, p_new_start timestamptz)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare b record; s record; e record; v_ends timestamptz;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then return query select false, 'Booking not found.'; return; end if;
  if b.user_id <> auth.uid() and not public.is_admin() then
    return query select false, 'That is not your booking.'; return;
  end if;
  if b.status <> 'booked' then
    return query select false, 'That booking is already closed.'; return;
  end if;

  select * into s from public.sessions where id = b.session_id;
  select * into e from public.event_types where id = s.event_type_id;

  if s.capacity > 1 then
    return query select false,
      'Group sessions cannot be moved by one attendee. Cancel and join another.'; return;
  end if;

  if not exists (
    select 1 from public.open_slots(e.id, p_new_start - interval '1 minute',
                                    p_new_start + interval '1 minute') o
     where o.slot_start = p_new_start) then
    return query select false, 'That time is not open.'; return;
  end if;

  v_ends := p_new_start + make_interval(mins => e.duration_min);

  begin
    update public.sessions
       set starts_at = p_new_start, ends_at = v_ends,
           ics_sequence = ics_sequence + 1
     where id = s.id;
  exception when exclusion_violation then
    return query select false, 'Someone just took that time.'; return;
  end;

  perform public.queue_booking_email('booking_rescheduled', p_booking,
    jsonb_build_object('previous_start', s.starts_at));

  -- The old reminder points at the old time.
  delete from public.email_outbox
   where booking_id = p_booking and kind = 'booking_reminder' and status = 'queued';
  perform public.queue_booking_email('booking_reminder', p_booking);

  return query select true, 'Moved.';
end $$;

grant execute on function public.reschedule_booking(uuid, timestamptz) to authenticated;

-- ---------- 12. WHAT THE STUDENT SEES ----------
create or replace function public.my_bookings(p_include_past boolean default false)
returns table (
  booking_id uuid, session_id uuid, event_type_id uuid, title text,
  starts_at timestamptz, ends_at timestamptz, status text, meeting_url text,
  provider text, capacity int, seats_taken int, agenda text, host_name text,
  outcome_summary text)
language sql stable security definer set search_path = public
as $$
  -- event_type_id is returned so the page can offer "reschedule" against the
  -- right slot grid. Matching on the title instead would break the moment two
  -- session types shared a name, or one was renamed after a booking was made.
  select b.id, s.id, e.id, coalesce(s.title, e.title), s.starts_at, s.ends_at,
         case when s.status = 'cancelled' then 'cancelled' else b.status end,
         -- The join link is withheld until the meeting is close. A link handed
         -- out three weeks early is a link pasted into a group chat.
         case when s.starts_at - now() < interval '1 hour' and b.status = 'booked'
              then coalesce(s.meeting_url, e.meeting_url) else null end,
         e.provider, s.capacity, s.seats_taken, b.agenda,
         coalesce(hp.full_name, 'GenAITesting'),
         o.summary
    from public.bookings b
    join public.sessions s    on s.id = b.session_id
    join public.event_types e on e.id = s.event_type_id
    left join public.profiles hp on hp.id = s.host_id
    left join public.session_outcomes o on o.session_id = s.id
   where b.user_id = auth.uid()
     and (p_include_past or s.ends_at > now() - interval '1 hour')
   order by s.starts_at;
$$;

grant execute on function public.my_bookings(boolean) to authenticated;

-- Group sessions a student could still join.
create or replace function public.open_group_sessions()
returns table (
  session_id uuid, event_type_id uuid, title text, description text,
  starts_at timestamptz, ends_at timestamptz, capacity int, seats_taken int,
  seats_left int, provider text, already_booked boolean)
language sql stable security definer set search_path = public
as $$
  select s.id, e.id, coalesce(s.title, e.title), e.description,
         s.starts_at, s.ends_at, s.capacity, s.seats_taken,
         s.capacity - s.seats_taken, e.provider,
         exists (select 1 from public.bookings b
                  where b.session_id = s.id and b.user_id = auth.uid()
                    and b.status = 'booked')
    from public.sessions s
    join public.event_types e on e.id = s.event_type_id
   where s.status = 'scheduled'
     and s.capacity > 1
     and e.active
     and s.starts_at > now()
   order by s.starts_at;
$$;

grant execute on function public.open_group_sessions() to anon, authenticated;

-- ---------- 13. ACTION ITEMS, BOTH WAYS ----------
create or replace function public.my_action_items(p_include_done boolean default true)
returns table (
  id uuid, title text, detail text, status text, due_on date,
  session_id uuid, session_on timestamptz, created_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select a.id, a.title, a.detail, a.status, a.due_on,
         a.session_id, s.starts_at, a.created_at
    from public.action_items a
    left join public.sessions s on s.id = a.session_id
   where a.user_id = auth.uid()
     and (p_include_done or a.status not in ('done','dropped'))
   -- a.id last, deliberately: items written by one admin_record_outcome call
   -- share a created_at to the microsecond, so without a tiebreak the list
   -- reorders itself between reloads and looks like it is losing rows.
   order by case a.status when 'in_progress' then 0 when 'open' then 1 else 2 end,
            a.due_on nulls last, a.created_at, a.id;
$$;

grant execute on function public.my_action_items(boolean) to authenticated;

-- The student moves the status and nothing else. A direct update would let them
-- rewrite the title of a task someone set them, which is not the same feature.
create or replace function public.set_action_item_status(p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
begin
  if p_status not in ('open','in_progress','done','dropped') then
    return query select false, 'Unknown status.'; return;
  end if;
  update public.action_items
     set status = p_status, updated_at = now()
   where id = p_id and (user_id = auth.uid() or public.is_admin());
  if not found then
    return query select false, 'That item is not yours.'; return;
  end if;
  return query select true, 'Updated.';
end $$;

grant execute on function public.set_action_item_status(uuid, text) to authenticated;

-- ---------- 14. ADMIN ----------
create or replace function public.admin_create_group_session(
  p_event_type uuid, p_starts_at timestamptz,
  p_capacity int default null, p_title text default null,
  p_meeting_url text default null)
returns table (ok boolean, message text, session_id uuid)
language plpgsql security definer set search_path = public
as $$
declare e record; v_id uuid;
begin
  if not public.is_admin() then
    return query select false, 'Admins only.', null::uuid; return;
  end if;
  select * into e from public.event_types where id = p_event_type;
  if not found then
    return query select false, 'Unknown session type.', null::uuid; return;
  end if;

  begin
    insert into public.sessions
      (event_type_id, host_id, starts_at, ends_at, capacity, meeting_url,
       title, created_by)
    values (e.id, e.host_id, p_starts_at,
            p_starts_at + make_interval(mins => e.duration_min),
            greatest(coalesce(p_capacity, e.capacity), 1),
            coalesce(p_meeting_url, e.meeting_url),
            coalesce(p_title, e.title), auth.uid())
    returning id into v_id;
  exception when exclusion_violation then
    return query select false,
      'You already have something scheduled then.', null::uuid; return;
  end;

  return query select true, 'Published.', v_id;
end $$;

grant execute on function public.admin_create_group_session(uuid, timestamptz, int, text, text)
  to authenticated;

-- Cancelling the whole session, which is different from one attendee leaving:
-- everyone holding a seat has to be told.
create or replace function public.admin_cancel_session(
  p_session uuid, p_reason text default null)
returns table (ok boolean, message text, notified int)
language plpgsql security definer set search_path = public
as $$
declare r record; n int := 0;
begin
  if not public.is_admin() then
    return query select false, 'Admins only.', 0; return;
  end if;

  for r in select id from public.bookings
            where session_id = p_session and status = 'booked' loop
    perform public.queue_booking_email('session_cancelled', r.id,
      jsonb_build_object('cancel_reason', p_reason));
    n := n + 1;
  end loop;

  update public.bookings
     set status = 'cancelled', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   where session_id = p_session and status = 'booked';

  update public.sessions
     set status = 'cancelled', ics_sequence = ics_sequence + 1
   where id = p_session;

  delete from public.email_outbox
   where session_id = p_session and kind = 'booking_reminder' and status = 'queued';

  return query select true, 'Cancelled.', n;
end $$;

grant execute on function public.admin_cancel_session(uuid, text) to authenticated;

-- The queue the admin works from.
create or replace function public.admin_upcoming_sessions(p_days int default 30)
returns table (
  session_id uuid, title text, starts_at timestamptz, ends_at timestamptz,
  capacity int, seats_taken int, status text, meeting_url text,
  attendees jsonb, has_outcome boolean)
language sql stable security definer set search_path = public
as $$
  select s.id, coalesce(s.title, e.title), s.starts_at, s.ends_at,
         s.capacity, s.seats_taken, s.status,
         coalesce(s.meeting_url, e.meeting_url),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'booking_id', b.id, 'user_id', b.user_id,
                    'name', coalesce(p.full_name, split_part(p.email,'@',1)),
                    'email', p.email, 'agenda', b.agenda, 'status', b.status)
                    order by b.created_at)
             from public.bookings b
             join public.profiles p on p.id = b.user_id
            where b.session_id = s.id
              and b.status in ('booked','attended')), '[]'::jsonb),
         exists (select 1 from public.session_outcomes o where o.session_id = s.id)
    from public.sessions s
    join public.event_types e on e.id = s.event_type_id
   where public.is_admin()
     and s.starts_at between now() - interval '7 days'
                         and now() + make_interval(days => p_days)
   order by s.starts_at;
$$;

grant execute on function public.admin_upcoming_sessions(int) to authenticated;

-- Write the outcome and turn it into the student's tasks in one transaction.
-- p_items is [{"title": "...", "detail": "...", "due_on": "2026-12-01"}, ...]
-- and every attendee gets a copy, because a group session's outcome is each
-- attendee's outcome.
create or replace function public.admin_record_outcome(
  p_session uuid, p_summary text, p_items jsonb default '[]'::jsonb)
returns table (ok boolean, message text, items_created int)
language plpgsql security definer set search_path = public
as $$
declare r record; it jsonb; n int := 0;
begin
  if not public.is_admin() then
    return query select false, 'Admins only.', 0; return;
  end if;
  if coalesce(trim(p_summary), '') = '' then
    return query select false, 'The summary cannot be empty.', 0; return;
  end if;

  insert into public.session_outcomes (session_id, summary, author_id)
  values (p_session, p_summary, auth.uid())
  on conflict (session_id) do update
    set summary = excluded.summary, author_id = excluded.author_id,
        updated_at = now();

  for r in select user_id from public.bookings
            where session_id = p_session and status in ('booked','attended') loop
    for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
      if coalesce(trim(it->>'title'), '') <> '' then
        insert into public.action_items
          (user_id, session_id, title, detail, due_on, created_by)
        values (r.user_id, p_session, it->>'title', it->>'detail',
                nullif(it->>'due_on','')::date, auth.uid());
        n := n + 1;
      end if;
    end loop;
  end loop;

  -- Having written the outcome, the meeting happened.
  update public.sessions set status = 'completed'
   where id = p_session and status = 'scheduled' and starts_at < now();
  -- Only for a session that has actually happened. Writing notes ahead of a
  -- call would otherwise mark everyone present and, because seats_taken follows
  -- booking status, quietly reopen seats on a session that is already full.
  update public.bookings set status = 'attended'
   where session_id = p_session and status = 'booked'
     and exists (select 1 from public.sessions s
                  where s.id = p_session and s.starts_at < now());

  return query select true, 'Saved.', n;
end $$;

grant execute on function public.admin_record_outcome(uuid, text, jsonb) to authenticated;

-- One student's whole history: every meeting, every outcome, every task and
-- where they have got to with it. This is what the growth view reads.
create or replace function public.admin_student_history(p_email text)
returns table (
  session_id uuid, title text, starts_at timestamptz, status text,
  summary text, items jsonb)
language sql stable security definer set search_path = public
as $$
  select s.id, coalesce(s.title, e.title), s.starts_at,
         case when s.status = 'cancelled' then 'cancelled' else b.status end,
         o.summary,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', a.id, 'title', a.title, 'status', a.status,
                    'due_on', a.due_on, 'updated_at', a.updated_at)
                    order by a.created_at, a.id)
             from public.action_items a
            where a.session_id = s.id and a.user_id = b.user_id), '[]'::jsonb)
    from public.bookings b
    join public.profiles p    on p.id = b.user_id
    join public.sessions s    on s.id = b.session_id
    join public.event_types e on e.id = s.event_type_id
    left join public.session_outcomes o on o.session_id = s.id
   where public.is_admin()
     and lower(p.email) = lower(p_email)
   order by s.starts_at desc;
$$;

grant execute on function public.admin_student_history(text) to authenticated;

-- ---------- 15. A STARTING MENU ----------
-- Seeded only if there is an admin to host them and nothing exists yet, so
-- re-running this file never duplicates the menu.
do $$
declare v_admin uuid;
begin
  select id into v_admin from public.profiles where role = 'admin' order by created_at limit 1;
  if v_admin is null then
    raise notice 'No admin profile yet — skipping the seed. Re-run this file after an admin exists.';
    return;
  end if;

  if not exists (select 1 from public.event_types) then
    insert into public.event_types
      (slug, title, description, host_id, duration_min, capacity, audience, sort_order, provider)
    values
      ('career-guidance',
       'Career guidance — 1:1',
       'Thirty minutes on where you are, what to learn next, and what the market actually asks for. Bring a question.',
       v_admin, 30, 1, 'subscriber', 10, 'google_meet'),
      ('project-review',
       'Project review — 1:1',
       'Walk through your capstone work. Defects you found, the ones you are unsure about, and how to write them up.',
       v_admin, 45, 1, 'subscriber', 20, 'google_meet'),
      ('discovery-call',
       'Is this course right for me? — 1:1',
       'Fifteen minutes, no account needed. Ask anything about the syllabus, the projects or the certification.',
       v_admin, 15, 1, 'anyone', 30, 'google_meet'),
      ('office-hours',
       'Open office hours — group',
       'A shared hour. Bring a problem; everyone learns from watching it get taken apart.',
       v_admin, 60, 12, 'subscriber', 40, 'google_meet');
  end if;

  if not exists (select 1 from public.availability_rules where host_id = v_admin) then
    insert into public.availability_rules (host_id, weekday, start_time, end_time, timezone)
    select v_admin, d, time '18:00', time '21:00', 'Asia/Kolkata'
      from generate_series(1, 5) d
    union all
    select v_admin, 6, time '10:00', time '13:00', 'Asia/Kolkata';
  end if;
end $$;

-- ---------- 16. WHAT TO DO NEXT ----------
-- 1. Paste a meeting link onto each event type:
--      update public.event_types set meeting_url = 'https://meet.google.com/xxx-xxxx-xxx';
--    Until then everything works except the join button, which stays hidden.
-- 2. Set ZEPTOMAIL_TOKEN in Edge Functions → Secrets, then deploy
--    send-booking-email. Until then invitations queue in email_outbox and
--    nothing is lost — the function sends whatever it finds waiting.
-- 3. Adjust availability_rules to the hours you actually want to work.
