-- ============================================================
-- schema-12-knowledge.sql — the knowledge base behind the help agent
--
-- Run in Supabase → SQL editor. Safe to re-run; every object is guarded.
--
-- What this is for: a student asks a question and gets an answer drawn from the
-- material we actually published, with links to the material it came from. An
-- admin points the same engine at a module and gets a polished summary or a set
-- of interview questions with model answers. One corpus, one retrieval path, two
-- output instructions — not two systems that drift apart.
--
-- Sources are LMS materials (PDF, DOCX, HTML in the materials bucket), the
-- public site pages, the capstone project documents, and video transcripts.
--
-- ---------- the two decisions worth arguing about ----------
--
-- 1. EMBEDDINGS COME FROM A SEPARATE PROVIDER. Groq serves chat completions and
--    Whisper transcription; it has no embeddings endpoint. So the vector comes
--    from elsewhere (Jina, Gemini, Hugging Face) while the answer comes from
--    Groq. Two providers, two failure modes — which is why the mixing guard
--    below exists and why retrieval does not depend on the embedder being up.
--
-- 2. RETRIEVAL IS HYBRID, not vectors alone. Every chunk carries both an
--    embedding and a generated tsvector, and search fuses the two rankings.
--    This costs nothing — the tsvector is computed by the database — and buys
--    two things. Students search for exact technical terms (RAGAS, Promptfoo,
--    Hit@k, prompt injection) and lexical ranking matches those more reliably
--    than embeddings, which blur near-synonyms together. And if the embedding
--    provider is unreachable, lexical search still answers instead of the help
--    desk going dark. Vectors do the work they are good at: loosely-worded
--    questions that share no words with the text.
--
-- Depends on: schema.sql (profiles, is_admin, materials).
-- ============================================================

create extension if not exists vector;
-- For the typo-tolerant fallback. A student who types "promtfoo" should still
-- find Promptfoo, and neither exact lexical match nor an embedding reliably
-- recovers a misspelled proper noun.
create extension if not exists pg_trgm;

-- ---------- 1. CONFIG ----------
-- One row. It exists to hold the active embedding model, because the single
-- most destructive thing that can happen to a vector index is quietly mixing
-- two models in it: the dimensions match, every insert succeeds, nothing errors,
-- and the rankings become confident nonsense. Recording the model and refusing
-- anything else makes that impossible rather than merely unlikely.
create table if not exists public.kb_config (
  id              int primary key default 1 check (id = 1),
  embed_provider  text not null default 'jina',
  embed_model     text not null default 'jina-embeddings-v3',
  embed_dim       int  not null default 768 check (embed_dim = 768),
  chat_provider   text not null default 'groq',
  chat_model      text not null default 'llama-3.3-70b-versatile',

  -- Below this cosine similarity, and with no lexical hit either, the agent
  -- must refuse rather than answer. An unhelpful "I could not find this" is
  -- recoverable; a confident answer assembled from the three least-bad chunks
  -- in the corpus is not.
  --
  -- This is deliberately a SIMILARITY floor and not a floor on the fused score
  -- below. Reciprocal Rank Fusion encodes ordering, not quality: a vector
  -- search always returns its forty nearest neighbours, so the top result for
  -- "budget ceiling" in a module that never mentions budgets still comes back
  -- ranked first and still scores 1/61. Rank cannot tell you whether anything
  -- was actually found; distance can.
  --
  -- 0.30 is a conservative starting point for jina-embeddings-v3 and wants
  -- calibrating against real student questions once there are some.
  min_similarity  real not null default 0.30,
  updated_at      timestamptz not null default now()
);
insert into public.kb_config (id) values (1) on conflict (id) do nothing;

-- ---------- 2. SOURCES AND DOCUMENTS ----------
create table if not exists public.kb_sources (
  id        uuid primary key default gen_random_uuid(),
  slug      text not null unique,
  label     text not null,
  kind      text not null check (kind in
              ('lms_material','site_page','capstone_doc','video','manual')),
  enabled   boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.kb_documents (
  id           uuid primary key default gen_random_uuid(),
  source_id    uuid not null references public.kb_sources(id) on delete cascade,

  -- What this document is in its own world: a materials.id, a URL path, a file
  -- name. Unique per source so re-ingesting updates rather than duplicates —
  -- the commonest way a knowledge base rots is the same document present three
  -- times at three ages, with retrieval picking whichever it likes.
  external_ref text not null,

  title        text not null,
  module       text,
  kind         text not null check (kind in
                 ('html','pdf','docx','pptx','xlsx','video','text','other')),
  uri          text,

  -- Of the extracted text, so a re-run can skip a document that has not
  -- changed. Embedding is the expensive step and the one with a quota.
  content_hash text,
  char_count   int,

  status       text not null default 'pending'
               check (status in ('pending','ingested','failed','skipped')),
  error        text,
  ingested_at  timestamptz,
  created_at   timestamptz not null default now(),
  unique (source_id, external_ref)
);

create index if not exists kb_documents_module_idx on public.kb_documents (module);
create index if not exists kb_documents_status_idx on public.kb_documents (status);

-- ---------- 3. CHUNKS ----------
create table if not exists public.kb_chunks (
  id           bigserial primary key,
  document_id  uuid not null references public.kb_documents(id) on delete cascade,
  ordinal      int not null,

  -- The heading trail this chunk sat under, which is what makes a citation
  -- readable: "Module 4 → Poisoning defences → Indirect injection" tells a
  -- student where to go; "chunk 37" does not.
  heading      text,
  content      text not null,
  char_count   int not null,

  -- For video: where in the recording this came from, so a citation can be a
  -- link that starts playing at the right moment.
  start_sec    int,
  end_sec      int,

  embedding    vector(768),
  embed_model  text,

  -- Generated, so it can never disagree with the content it indexes. Weighting
  -- the heading above the body is deliberate: a term in a heading is usually
  -- what the section is *about*, not merely a term it mentions.
  fts tsvector generated always as (
    setweight(to_tsvector('english', coalesce(heading, '')), 'A') ||
    setweight(to_tsvector('english', content), 'B')
  ) stored,

  created_at   timestamptz not null default now(),
  unique (document_id, ordinal)
);

create index if not exists kb_chunks_fts_idx on public.kb_chunks using gin (fts);
create index if not exists kb_chunks_trgm_idx on public.kb_chunks using gin (content gin_trgm_ops);

-- HNSW over cosine distance. Built unconditionally: on an empty table it costs
-- nothing, and adding it later on a full one is a long lock at the worst moment.
do $$
begin
  if not exists (select 1 from pg_class where relname = 'kb_chunks_embedding_idx') then
    create index kb_chunks_embedding_idx on public.kb_chunks
      using hnsw (embedding vector_cosine_ops);
  end if;
end $$;

-- The mixing guard. Dimensions agreeing is not the same as embeddings being
-- comparable; two 768-dimension models produce vectors in unrelated spaces.
create or replace function public.kb_guard_embed_model()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_model text;
begin
  if new.embedding is null then return new; end if;
  select embed_model into v_model from public.kb_config where id = 1;
  if new.embed_model is null then
    new.embed_model := v_model;
  elsif new.embed_model <> v_model then
    raise exception
      'embedding from % cannot join an index built with % — change kb_config.embed_model and re-embed every chunk, or this index silently returns nonsense',
      new.embed_model, v_model;
  end if;
  return new;
end $$;

drop trigger if exists kb_chunks_guard_model on public.kb_chunks;
create trigger kb_chunks_guard_model
  before insert or update of embedding, embed_model on public.kb_chunks
  for each row execute function public.kb_guard_embed_model();

-- ---------- 4. WHAT WAS ASKED ----------
-- Kept because the questions students actually ask are the most useful SEO and
-- curriculum signal this platform can produce, and because an answer nobody can
-- audit is an answer nobody should trust.
create table if not exists public.kb_queries (
  id          bigserial primary key,
  user_id     uuid references public.profiles(id) on delete set null,
  mode        text not null check (mode in ('ask','summary','interview')),
  question    text not null,
  module      text,
  answer      text,
  cited       bigint[],
  grounded    boolean,
  chat_model  text,
  ms          int,
  error       text,
  created_at  timestamptz not null default now()
);

create index if not exists kb_queries_recent_idx on public.kb_queries (created_at desc);

-- ---------- 5. ROW LEVEL SECURITY ----------
alter table public.kb_config    enable row level security;
alter table public.kb_sources   enable row level security;
alter table public.kb_documents enable row level security;
alter table public.kb_chunks    enable row level security;
alter table public.kb_queries   enable row level security;

grant select on public.kb_sources, public.kb_documents to anon, authenticated;
grant select on public.kb_config, public.kb_sources, public.kb_documents,
                public.kb_chunks, public.kb_queries to authenticated;

-- The corpus catalogue is readable — a student may see what the agent knows
-- about, which is the difference between "I don't know" and "I don't know, and
-- here is what I do have".
drop policy if exists "kb sources read" on public.kb_sources;
drop policy if exists "kb sources admin" on public.kb_sources;
create policy "kb sources read" on public.kb_sources for select using (enabled or public.is_admin());
create policy "kb sources admin" on public.kb_sources for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "kb documents read" on public.kb_documents;
drop policy if exists "kb documents admin" on public.kb_documents;
create policy "kb documents read" on public.kb_documents for select
  using (status = 'ingested' or public.is_admin());
create policy "kb documents admin" on public.kb_documents for all
  using (public.is_admin()) with check (public.is_admin());

-- Chunks are admin-only to read directly. Not secrecy — the text is published
-- material — but a readable chunk table is a readable copy of every handout,
-- and the no-download policy exists for a reason. Answers reach students
-- through kb_search(), which returns only what a question actually matched.
drop policy if exists "kb chunks admin" on public.kb_chunks;
create policy "kb chunks admin" on public.kb_chunks for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "kb config read" on public.kb_config;
drop policy if exists "kb config admin" on public.kb_config;
create policy "kb config read" on public.kb_config for select using (true);
create policy "kb config admin" on public.kb_config for all
  using (public.is_admin()) with check (public.is_admin());

-- A student sees their own question history; the admin sees all of it.
drop policy if exists "kb queries read" on public.kb_queries;
drop policy if exists "kb queries admin" on public.kb_queries;
create policy "kb queries read" on public.kb_queries for select
  using (user_id = auth.uid() or public.is_admin());
create policy "kb queries admin" on public.kb_queries for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 6. SEARCH ----------
drop function if exists public.kb_search(vector, text, text, int);
drop function if exists public.kb_lexical_search(text, text, int);

-- Hybrid, fused by Reciprocal Rank Fusion.
--
-- RRF rather than a weighted sum of scores, because the two scores are not on
-- the same scale and never will be: cosine distance is bounded and ts_rank is
-- not, so any fixed weighting is really a guess about the corpus that stops
-- being true as the corpus grows. RRF only uses each list's *ordering*, which
-- is the part both methods agree is meaningful. k = 60 is the usual constant
-- and it is not sensitive.
create or replace function public.kb_search(
  p_embedding vector(768),
  p_query     text,
  p_module    text default null,
  p_limit     int default 8)
returns table (
  chunk_id bigint, document_id uuid, title text, module text, kind text,
  uri text, heading text, content text, start_sec int,
  score real, similarity real, lex_hit boolean, vec_rank int, lex_rank int)
language sql stable security definer set search_path = public
as $$
  with vec as (
    select c.id, row_number() over (order by c.embedding <=> p_embedding) as r,
           (1 - (c.embedding <=> p_embedding))::real as sim
      from public.kb_chunks c
      join public.kb_documents d on d.id = c.document_id
     where p_embedding is not null
       and c.embedding is not null
       and d.status = 'ingested'
       and (p_module is null or d.module = p_module)
     order by c.embedding <=> p_embedding
     limit 40
  ),
  lex as (
    select c.id, row_number() over (
             order by ts_rank(c.fts, websearch_to_tsquery('english', p_query)) desc) as r
      from public.kb_chunks c
      join public.kb_documents d on d.id = c.document_id
     where coalesce(p_query, '') <> ''
       and c.fts @@ websearch_to_tsquery('english', p_query)
       and d.status = 'ingested'
       and (p_module is null or d.module = p_module)
     order by ts_rank(c.fts, websearch_to_tsquery('english', p_query)) desc
     limit 40
  ),
  fused as (
    select coalesce(v.id, l.id) as id,
           (coalesce(1.0 / (60 + v.r), 0) + coalesce(1.0 / (60 + l.r), 0))::real as score,
           v.sim, (l.id is not null) as lex_hit,
           v.r::int as vec_rank, l.r::int as lex_rank
      from vec v full outer join lex l on l.id = v.id
  )
  select c.id, d.id, d.title, d.module, d.kind, d.uri, c.heading, c.content,
         c.start_sec, f.score, f.sim, f.lex_hit, f.vec_rank, f.lex_rank
    from fused f
    join public.kb_chunks c    on c.id = f.id
    join public.kb_documents d on d.id = c.document_id
   order by f.score desc
   limit greatest(p_limit, 1);
$$;

grant execute on function public.kb_search(vector, text, text, int) to authenticated;

-- The same search with no embedding, for when the embedding provider is down
-- or a caller has no vector to offer. Deliberately a separate entry point: a
-- silent fall back to lexical-only would hide a broken embedder for weeks.
create or replace function public.kb_lexical_search(
  p_query text, p_module text default null, p_limit int default 8)
returns table (
  chunk_id bigint, document_id uuid, title text, module text, kind text,
  uri text, heading text, content text, start_sec int,
  score real, similarity real, lex_hit boolean, vec_rank int, lex_rank int)
language sql stable security definer set search_path = public
as $$
  select * from public.kb_search(null::vector(768), p_query, p_module, p_limit);
$$;

grant execute on function public.kb_lexical_search(text, text, int) to authenticated;

-- ---------- 7. WHAT THE CORPUS CONTAINS ----------
-- So the agent can say "I don't know, but I do hold these eleven modules",
-- and so the admin can see coverage without reading the chunk table.
create or replace function public.kb_coverage()
returns table (module text, documents int, chunks int, embedded int, last_ingest timestamptz)
language sql stable security definer set search_path = public
as $$
  select coalesce(d.module, 'Unfiled'),
         count(distinct d.id)::int,
         count(c.id)::int,
         count(c.embedding)::int,
         max(d.ingested_at)
    from public.kb_documents d
    left join public.kb_chunks c on c.document_id = d.id
   where d.status = 'ingested'
   group by 1
   order by 1;
$$;

grant execute on function public.kb_coverage() to anon, authenticated;

-- ---------- 8. LOGGING AN ANSWER ----------
create or replace function public.kb_log_answer(
  p_mode text, p_question text, p_module text, p_answer text,
  p_cited bigint[], p_grounded boolean, p_model text, p_ms int,
  p_error text default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_id bigint;
begin
  insert into public.kb_queries
    (user_id, mode, question, module, answer, cited, grounded, chat_model, ms, error)
  values (auth.uid(), p_mode, p_question, p_module, p_answer,
          p_cited, p_grounded, p_model, p_ms, p_error)
  returning id into v_id;
  return v_id;
end $$;

grant execute on function
  public.kb_log_answer(text, text, text, text, bigint[], boolean, text, int, text)
  to authenticated;

-- ---------- 9. INGESTION HELPERS ----------
-- Called by kb/ingest.py with the service role. Upsert on (source, external_ref)
-- so a second run updates in place; the content hash lets the caller skip
-- re-embedding a document that has not changed, which is the only expensive part.
create or replace function public.kb_upsert_document(
  p_source_slug text, p_external_ref text, p_title text, p_kind text,
  p_module text default null, p_uri text default null,
  p_content_hash text default null, p_char_count int default null)
returns table (document_id uuid, unchanged boolean)
language plpgsql security definer set search_path = public
as $$
declare v_src uuid; v_id uuid; v_old text;
begin
  select id into v_src from public.kb_sources where slug = p_source_slug;
  if v_src is null then
    raise exception 'unknown kb source %', p_source_slug;
  end if;

  select id, content_hash into v_id, v_old
    from public.kb_documents
   where source_id = v_src and external_ref = p_external_ref;

  if v_id is null then
    insert into public.kb_documents
      (source_id, external_ref, title, module, kind, uri, content_hash, char_count, status)
    values (v_src, p_external_ref, p_title, p_module, p_kind, p_uri,
            p_content_hash, p_char_count, 'pending')
    returning id into v_id;
    return query select v_id, false;
    -- `return query` APPENDS rows and carries on; it is not `return`. Without
    -- this the insert branch falls through to the update below and appends a
    -- second row, so a brand-new document answers both "new" and "unchanged".
    -- claude/qt-projects-entitlements-plan.md records the identical bug in
    -- redeem_coupon, which is where this one was caught by the same test shape.
    return;
  end if;

  update public.kb_documents
     set title = p_title, module = p_module, kind = p_kind, uri = p_uri,
         content_hash = p_content_hash, char_count = p_char_count
   where id = v_id;

  return query select v_id, (v_old is not null and v_old = p_content_hash);
end $$;

revoke all on function public.kb_upsert_document(text, text, text, text, text, text, text, int)
  from public, anon, authenticated;

-- Replace a document's chunks in one transaction. Delete-then-insert rather
-- than diffing: a half-replaced document is a document that answers questions
-- with two versions of itself.
create or replace function public.kb_replace_chunks(
  p_document uuid, p_chunks jsonb)
returns int
language plpgsql security definer set search_path = public
as $$
declare it jsonb; n int := 0;
begin
  delete from public.kb_chunks where document_id = p_document;

  for it in select * from jsonb_array_elements(coalesce(p_chunks, '[]'::jsonb)) loop
    insert into public.kb_chunks
      (document_id, ordinal, heading, content, char_count, start_sec, end_sec,
       embedding, embed_model)
    values (
      p_document, (it->>'ordinal')::int, it->>'heading', it->>'content',
      coalesce((it->>'char_count')::int, length(it->>'content')),
      nullif(it->>'start_sec','')::int, nullif(it->>'end_sec','')::int,
      nullif(it->>'embedding','')::vector(768), it->>'embed_model');
    n := n + 1;
  end loop;

  update public.kb_documents
     set status = 'ingested', ingested_at = now(), error = null
   where id = p_document;

  return n;
end $$;

revoke all on function public.kb_replace_chunks(uuid, jsonb) from public, anon, authenticated;

-- ---------- 10. THE SOURCES WE START WITH ----------
insert into public.kb_sources (slug, label, kind) values
  ('lms',      'LMS materials',            'lms_material'),
  ('site',     'Public website pages',     'site_page'),
  ('capstone', 'Capstone project documents','capstone_doc'),
  ('video',    'Video transcripts',        'video'),
  ('manual',   'Written by hand',          'manual')
on conflict (slug) do nothing;

-- ---------- 11. NEXT ----------
-- 1. The materials table has no 'video' kind. Before any video is uploaded:
--      alter table public.materials drop constraint materials_kind_check;
--      alter table public.materials add constraint materials_kind_check
--        check (kind in ('html','image','gif','pdf','pptx','docx','xlsx','video','other'));
--    Left as a comment rather than run here, because it touches a table the
--    whole LMS reads and deserves to be a deliberate act.
-- 2. Run kb/ingest.py to fill the corpus.
-- 3. Deploy the kb-agent edge function and set GROQ_API_KEY and the embedding
--    provider's key in Edge Functions → Secrets.
