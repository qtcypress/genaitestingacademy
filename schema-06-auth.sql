-- ============================================================
-- GenAITesting — migration 06: multi-provider sign-in
-- Run in: Supabase Dashboard → SQL Editor → New query → Run.
-- Safe to re-run. If the linter warns about RLS, choose "Run without RLS"
-- (RLS was already enabled by migrations 01–05).
--
-- Context: the portal used to accept GitHub sign-in only. It now also accepts
-- Google and email + password. Nothing in the schema *required* changing for
-- that — handle_new_user() already falls back through full_name → name → email,
-- and a Google/email account simply has a null github_user. This migration adds
-- the one safeguard that a second sign-in route makes worth having.
-- ============================================================

-- ---------- Why this guard exists ----------
-- Admin is granted by matching an allowlisted email address. With GitHub as the
-- only door, an address could only ever reach us already verified by GitHub.
-- Email + password sign-up opens a second door: if "Confirm email" were ever
-- switched off in the Supabase dashboard (or a future migration granted admin
-- before confirmation), somebody could register an admin's address, never prove
-- they own it, and inherit the admin role — which controls pricing, payments and
-- every student record.
--
-- Rather than trust a dashboard toggle to stay switched on, refuse the admin
-- role in the database unless the account's email is actually confirmed.
-- Google and GitHub accounts always satisfy this; a self-registered email
-- account only satisfies it after the student clicks the confirmation link.

create or replace function public.enforce_admin_email_confirmed()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  confirmed timestamptz;
begin
  if new.role is distinct from 'admin' then
    return new;
  end if;

  select u.email_confirmed_at into confirmed
  from auth.users u
  where u.id = new.id;

  if confirmed is null then
    raise exception
      'refusing to grant admin to % — the email address on this account has not been confirmed', new.email
      using hint = 'Have the account owner click the confirmation link, then set the role again.';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_admin_requires_confirmed_email on public.profiles;
create trigger profiles_admin_requires_confirmed_email
  before insert or update of role on public.profiles
  for each row execute function public.enforce_admin_email_confirmed();

-- ---------- Housekeeping ----------
-- github_user is meaningless for Google and email accounts. It was already
-- nullable; this just makes the intent explicit for anyone reading the schema.
comment on column public.profiles.github_user is
  'GitHub login name. NULL for accounts created with Google or email + password.';

comment on column public.profiles.full_name is
  'Shown in the portal and printed on certificates. Taken from the identity '
  'provider for GitHub/Google, or from the name the student typed at sign-up.';

-- ---------- Check it worked ----------
-- Existing admins should still be admins (they signed in through GitHub, so
-- their email is confirmed and the guard lets them through untouched):
--
--   select p.email, p.role, u.email_confirmed_at is not null as email_confirmed
--   from public.profiles p join auth.users u on u.id = p.id
--   where p.role = 'admin';
--
-- And the guard should refuse an unconfirmed account:
--
--   update public.profiles set role = 'admin'
--   where id = '<id of an unconfirmed signup>';   -- expect: refusing to grant admin

-- ============================================================
-- Dashboard settings this migration assumes (Supabase → Authentication):
--   Providers → Email    : enabled, "Confirm email" ON
--   Providers → Google   : enabled, with a Google Cloud OAuth client
--   Providers → GitHub   : enabled (unchanged)
--   URL Configuration    : Site URL + Redirect URLs include the live site and
--                          .../reset-password.html
--   Emails → SMTP        : custom SMTP configured — the built-in sender is
--                          capped at 2 emails per hour, which is not enough
--                          for real student signups.
-- ============================================================
