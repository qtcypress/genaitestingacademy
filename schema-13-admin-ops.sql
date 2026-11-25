-- ============================================================
-- schema-13-admin-ops.sql — the numbers that say whether it is working
--
-- Run in Supabase → SQL editor, after schema-11-booking.sql. Safe to re-run.
--
-- The admin queue already lists every session. This is the other question: is
-- the follow-up loop actually turning, or does it merely exist? A booking
-- system can look healthy — sessions in the calendar, attendees attached — while
-- no outcome is ever written and no action item is ever closed, and the queue
-- cannot show you that, because the queue shows what is coming rather than what
-- has been left behind.
--
-- So these are deliberately the uncomfortable numbers: calls that happened and
-- were never written up, tasks that went past their date, people who did not
-- turn up. Counting the comfortable ones would make a dashboard that is always
-- green.
--
-- Depends on: schema.sql (profiles, is_admin), schema-11-booking.sql.
-- ============================================================

drop function if exists public.admin_ops_dashboard();

create or replace function public.admin_ops_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare r jsonb;
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;

  select jsonb_build_object(

    'bookings', (select jsonb_build_object(
        'next_7_days', count(*) filter (
           where s.starts_at between now() and now() + interval '7 days'
             and s.status = 'scheduled' and b.status = 'booked'),
        'last_30_days', count(*) filter (
           where s.starts_at between now() - interval '30 days' and now()),
        'booked_this_week', count(*) filter (
           where b.created_at >= date_trunc('week', now())),
        'total', count(*))
      from public.bookings b join public.sessions s on s.id = b.session_id),

    -- Attendance only counts sessions that have finished AND been written up,
    -- because a booking still marked 'booked' a week later means nobody recorded
    -- the outcome — which is a different problem from a no-show and must not be
    -- quietly folded into one.
    'attendance', (select jsonb_build_object(
        'attended', count(*) filter (where b.status = 'attended'),
        'no_show',  count(*) filter (where b.status = 'no_show'),
        'cancelled',count(*) filter (where b.status = 'cancelled'),
        'rate', case when count(*) filter (where b.status in ('attended','no_show')) = 0
                     then null
                     else round(100.0 * count(*) filter (where b.status = 'attended')
                          / count(*) filter (where b.status in ('attended','no_show')))
                end)
      from public.bookings b join public.sessions s on s.id = b.session_id
     where s.ends_at < now()),

    -- The single most useful number here. A call with no outcome produced no
    -- action items, so the student got nothing out of it that outlives the hour.
    'unwritten', (select jsonb_build_object(
        'count', count(*),
        -- Rounded epoch days, not extract(day from interval): that truncates,
        -- so a call written up nowhere for 2 days 23 hours reported as "2 days"
        -- and the number read as less urgent than it was.
        'oldest_days', coalesce(
           round(max(extract(epoch from now() - s.ends_at)) / 86400)::int, 0),
        'sessions', coalesce(jsonb_agg(jsonb_build_object(
            'session_id', s.id,
            'title', coalesce(s.title, e.title),
            'ended', s.ends_at,
            'attendees', (select count(*) from public.bookings b2
                           where b2.session_id = s.id and b2.status in ('booked','attended')))
          order by s.ends_at), '[]'::jsonb))
      from public.sessions s
      join public.event_types e on e.id = s.event_type_id
     where s.ends_at < now()
       and s.status <> 'cancelled'
       and not exists (select 1 from public.session_outcomes o where o.session_id = s.id)
       and exists (select 1 from public.bookings b3
                    where b3.session_id = s.id and b3.status in ('booked','attended'))),

    'action_items', (select jsonb_build_object(
        'open', count(*) filter (where a.status = 'open'),
        'in_progress', count(*) filter (where a.status = 'in_progress'),
        'done', count(*) filter (where a.status = 'done'),
        'dropped', count(*) filter (where a.status = 'dropped'),
        'overdue', count(*) filter (
           where a.due_on is not null and a.due_on < current_date
             and a.status in ('open','in_progress')),
        -- Untouched since it was set: the student has not even opened it. A task
        -- sitting at 'open' three weeks later is a conversation to have, not a
        -- number to average away.
        'stale', count(*) filter (
           where a.status = 'open' and a.created_at < now() - interval '21 days'))
      from public.action_items a),

    'overdue_detail', (select coalesce(jsonb_agg(jsonb_build_object(
          'title', a.title, 'due_on', a.due_on, 'status', a.status,
          'student', coalesce(p.full_name, split_part(p.email, '@', 1)),
          'email', p.email,
          'days_over', (current_date - a.due_on))
        order by a.due_on), '[]'::jsonb)
      from public.action_items a
      join public.profiles p on p.id = a.user_id
     where a.due_on is not null and a.due_on < current_date
       and a.status in ('open','in_progress')),

    'capacity', (select jsonb_build_object(
        'event_types', count(*),
        'active', count(*) filter (where active),
        -- Without a link nobody can join the call, which is the quietest way
        -- for a booking system to be useless: everything works except the part
        -- the student needs.
        'without_meeting_link', count(*) filter (where active and coalesce(meeting_url,'') = ''),
        'availability_windows', (select count(*) from public.availability_rules where active))
      from public.event_types),

    'email', (select jsonb_build_object(
        'queued', count(*) filter (where status = 'queued'),
        'sent', count(*) filter (where status = 'sent'),
        'failed', count(*) filter (where status = 'failed'),
        'oldest_queued_hours', coalesce(
           max(extract(epoch from now() - created_at) / 3600)
             filter (where status = 'queued'), 0)::int)
      from public.email_outbox),

    'generated_at', now()
  ) into r;

  return r;
end $$;

grant execute on function public.admin_ops_dashboard() to authenticated;

-- ---------- marking a no-show ----------
-- Attendance is only meaningful if somebody records it, and admin_record_outcome
-- marks everyone present. This is the other half: one attendee who did not turn
-- up, recorded separately so the attendance rate above means something.
create or replace function public.admin_mark_no_show(p_booking uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare v_started boolean;
begin
  if not public.is_admin() then
    return query select false, 'Admins only.'; return;
  end if;

  select s.starts_at < now() into v_started
    from public.bookings b join public.sessions s on s.id = b.session_id
   where b.id = p_booking;

  if v_started is null then
    return query select false, 'Booking not found.'; return;
  end if;
  if not v_started then
    -- Marking a future session as a no-show would also free its seat, because
    -- seats_taken follows booking status.
    return query select false, 'That session has not happened yet.'; return;
  end if;

  update public.bookings set status = 'no_show' where id = p_booking and status = 'booked';
  if not found then
    return query select false, 'That booking is not open to mark.'; return;
  end if;
  return query select true, 'Marked as a no-show.';
end $$;

grant execute on function public.admin_mark_no_show(uuid) to authenticated;
