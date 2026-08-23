-- GenAITesting — migration 10: the SEO assistant's memory
--
-- The point of the assistant is that Ram does not have to remember where he got to.
-- That only works if the state outlives the browser tab, so it lives here rather
-- than in localStorage: the same checklist, in the same place, from any machine.
--
-- Two tables, both admin-only. There is nothing here a student should read — the
-- checklist names infrastructure and the drafts are unpublished work.

-- ---------------------------------------------------------------- checklist ----
-- One row per task the assistant tracks. Seeded below with the real list; new rows
-- can be added by hand or by the assistant without a migration.
create table if not exists public.seo_tasks (
  id            text primary key,
  title         text not null,
  why           text not null,          -- shown under the title: why it is worth doing
  how           text,                   -- the concrete steps
  link          text,                   -- where to go and do it
  -- 'once' disappears when done. 'weekly'/'monthly' come back, which is the whole
  -- point: SEO fails from things not repeating, not from things never being done.
  cadence       text not null default 'once'
                check (cadence in ('once', 'weekly', 'monthly', 'quarterly')),
  sort_order    int  not null default 100,
  -- A task can be blocked by another. Submitting a sitemap before the property is
  -- verified simply fails, and showing it as available invites that.
  depends_on    text references public.seo_tasks(id),
  active        boolean not null default true,
  done_at       timestamptz,
  done_by       uuid references auth.users(id),
  note          text,                   -- whatever Ram wants to remember about it
  created_at    timestamptz not null default now()
);

create index if not exists seo_tasks_order on public.seo_tasks(sort_order);

-- ------------------------------------------------------------------ drafts ----
-- A post in progress. Kept server-side so a draft survives a closed tab, and so the
-- publish step has something to read that the browser cannot have tampered with.
create table if not exists public.seo_drafts (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null
                check (slug ~ '^[a-z0-9][a-z0-9-]{2,80}$'),
  title         text not null,
  description   text not null,
  keywords      text[] not null default '{}',
  body_html     text not null default '',
  source_url    text,                   -- the reference this was written from
  source_title  text,
  status        text not null default 'draft'
                check (status in ('draft', 'published', 'archived')),
  published_at  date,
  commit_sha    text,                   -- filled in once it reaches the repo
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists seo_drafts_status on public.seo_drafts(status, updated_at desc);

create or replace function public.touch_seo_draft()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists seo_drafts_touch on public.seo_drafts;
create trigger seo_drafts_touch before update on public.seo_drafts
  for each row execute function public.touch_seo_draft();

-- -------------------------------------------------------------------- RLS ----
-- Admin only, both tables. Note the USING *and* WITH CHECK on the write policies:
-- USING alone governs which rows can be read for an update, and would let a
-- non-admin insert rows they then could not see.
alter table public.seo_tasks  enable row level security;
alter table public.seo_drafts enable row level security;

drop policy if exists seo_tasks_admin  on public.seo_tasks;
drop policy if exists seo_drafts_admin on public.seo_drafts;

create policy seo_tasks_admin on public.seo_tasks
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy seo_drafts_admin on public.seo_drafts
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------------- seed ----
-- The real list. Ordered so that anything blocking something else comes first.
insert into public.seo_tasks (id, title, why, how, link, cadence, sort_order, depends_on)
values
  ('gsc-verify',
   'Verify the site in Google Search Console',
   'Nothing else in Google works until this is done. The site currently has zero pages indexed — it cannot rank for anything, including its own name, until Google is told it exists.',
   E'1. Open Search Console and sign in.\n2. Choose the right-hand box, URL prefix, and enter https://genaitesting.online\n3. Expand the HTML tag method and copy the meta tag.\n4. Send that tag to Claude — it goes in index.html and needs a deploy.\n5. Come back and press Verify.',
   'https://search.google.com/search-console', 'once', 10, null),

  ('gsc-sitemap',
   'Submit the sitemap',
   'Verification proves the site is yours. The sitemap is what tells Google which pages to actually crawl, and without it discovery relies on links the site does not yet have.',
   E'In Search Console, open Sitemaps in the left menu and enter:\n\n    sitemap.xml\n\nIt should report Success within a few minutes.',
   'https://search.google.com/search-console/sitemaps', 'once', 20, 'gsc-verify'),

  ('gsc-inspect',
   'Request indexing for the three money pages',
   'A sitemap gets a site crawled eventually. Requesting indexing directly usually gets a specific page looked at within a day, and these three are the ones worth the queue.',
   E'In Search Console use the URL inspection bar at the top for each of:\n\n  https://genaitesting.online/\n  https://genaitesting.online/genai-testing-course.html\n  https://genaitesting.online/python-dsa-course.html\n\nPress Request indexing on each.',
   'https://search.google.com/search-console', 'once', 30, 'gsc-verify'),

  ('bing-webmaster',
   'Add the site to Bing Webmaster Tools',
   'ChatGPT search and Copilot read the Bing index, so Bing is the highest-leverage target for being quoted by an AI assistant. IndexNow already submits pages automatically; this adds the reporting.',
   E'Sign in at Bing Webmaster Tools. It offers to import everything from Google Search Console, which is the fastest route — do the Google one first.',
   'https://www.bing.com/webmasters', 'once', 40, 'gsc-verify'),

  ('publish-post',
   'Publish one blog post',
   'This is the one that actually moves rankings, and the one most likely to slip. Each post is a new page that can rank, a new answer an assistant can quote, and a reason for somebody to link to the site.',
   E'Use the composer on this page. Paste a reference link, let it draft, edit it until it sounds like you, then publish. The post goes live on its own once Netlify is connected to GitHub.',
   null, 'weekly', 50, null),

  ('check-watchdog',
   'Check the SEO watchdog is green',
   'It runs every morning and emails on failure, so a red run usually means an email was missed. Silent SEO breakage is the expensive kind — a page that quietly goes noindex can cost weeks.',
   E'Open the Actions tab and look at the most recent SEO watchdog run. Green is fine. Red lists exactly what broke.',
   'https://github.com/qtcypress/genaitestingacademy/actions/workflows/seo-watchdog.yml',
   'weekly', 60, null),

  ('earn-link',
   'Get one link from another site',
   'The single biggest thing no amount of on-page work substitutes for. Google treats a link as somebody vouching for the site, and right now almost nobody has.',
   E'Realistic sources, easiest first: a post from the company LinkedIn page; a comment or answer on a testing community that genuinely helps and happens to cite a post; a listing in a Hyderabad training directory; a guest article for a testing blog.',
   null, 'monthly', 70, null),

  ('review-queries',
   'Read what people actually searched to find you',
   'The Performance report shows real queries, not guesses. Terms appearing at position 8 to 20 are the cheapest wins available — the page already almost ranks, and usually needs a paragraph rather than a new page.',
   E'Search Console → Performance → Queries. Sort by impressions. Anything with impressions and no clicks is a title or description worth rewriting.',
   'https://search.google.com/search-console/performance/search-analytics',
   'monthly', 80, 'gsc-verify')
on conflict (id) do update
  set title = excluded.title, why = excluded.why, how = excluded.how,
      link = excluded.link, cadence = excluded.cadence,
      sort_order = excluded.sort_order, depends_on = excluded.depends_on;

-- A recurring task is "due" again once its cadence has elapsed. Doing that in SQL
-- keeps one definition of due rather than one per caller.
create or replace function public.seo_checklist()
returns table (
  id text, title text, why text, how text, link text, cadence text,
  sort_order int, depends_on text, note text, done_at timestamptz,
  blocked boolean, due boolean
)
language sql stable security definer set search_path = public as $$
  select t.id, t.title, t.why, t.how, t.link, t.cadence, t.sort_order,
         t.depends_on, t.note, t.done_at,
         -- blocked while whatever it depends on is not done
         (t.depends_on is not null
          and not exists (select 1 from seo_tasks d
                          where d.id = t.depends_on and d.done_at is not null)) as blocked,
         case
           when t.done_at is null then true
           when t.cadence = 'once' then false
           when t.cadence = 'weekly'    then t.done_at < now() - interval '7 days'
           when t.cadence = 'monthly'   then t.done_at < now() - interval '30 days'
           when t.cadence = 'quarterly' then t.done_at < now() - interval '90 days'
           else false
         end as due
  from seo_tasks t
  where t.active
  order by t.sort_order;
$$;

revoke execute on function public.seo_checklist() from public, anon;
grant execute on function public.seo_checklist() to authenticated;

-- Marking done is a function rather than a direct update so the timestamp and the
-- user are recorded by the database instead of trusted from the browser.
create or replace function public.seo_task_done(p_id text, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  update seo_tasks
     set done_at = now(), done_by = auth.uid(),
         note = coalesce(p_note, note)
   where id = p_id;
end $$;

revoke execute on function public.seo_task_done(text, text) from public, anon;
grant execute on function public.seo_task_done(text, text) to authenticated;
