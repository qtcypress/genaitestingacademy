-- ============================================================
-- schema-15-video-kind.sql — let a material be a video
--
-- Run in Supabase → SQL editor. Safe to re-run.
--
-- schema-12 left this as a comment rather than running it, deliberately: it
-- touches a constraint on a table the whole LMS reads, and that deserves to be
-- a deliberate act rather than a side effect of installing a knowledge base.
-- This is that act.
--
-- Until now `materials.kind` allowed html, image, gif, pdf, pptx, docx, xlsx
-- and other. The knowledge base could already ingest video — kb/ingest.py
-- transcribes with Whisper — so the LMS was the half that could not hold one.
-- A lesson video had to be filed as 'other', which the viewer does not know how
-- to play.
--
-- Depends on: schema.sql.
-- ============================================================

do $$
begin
  -- Drop and re-add rather than ALTER: a check constraint cannot be widened in
  -- place. The drop is guarded so a re-run does not fail on an absent
  -- constraint, and the add is guarded so it does not fail on a present one.
  alter table public.materials drop constraint if exists materials_kind_check;

  alter table public.materials add constraint materials_kind_check
    check (kind in ('html','image','gif','pdf','pptx','docx','xlsx','video','other'));
end $$;

-- A row already filed as 'other' that is plainly a video can be corrected now
-- that there is somewhere for it to go. Deliberately narrow: it only touches
-- rows whose stored file carries a video extension, so a genuinely
-- miscellaneous 'other' is left alone.
update public.materials
   set kind = 'video'
 where kind = 'other'
   and storage_path ~* '\.(mp4|webm|mov|m4v)$';

-- ---------- check ----------
-- select kind, count(*) from public.materials group by kind order by 2 desc;
--
-- And that the constraint really accepts the new value:
--   begin;
--     insert into public.materials (module_id, title, kind, storage_path, sort_order)
--     select id, 'constraint probe', 'video', 'probe.mp4', 999
--       from public.modules limit 1;
--   rollback;
