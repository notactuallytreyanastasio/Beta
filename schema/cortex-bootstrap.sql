-- Minimal cortex schema for a fresh, dump-less Alpha instance.
--
-- Mirrors the production layout closely enough for every MCP tool and hook
-- handler to function against an empty database. Vector column is sized 2560
-- to match Qwen 3 Embedding 4B (the model llm.format_query_for_embedding is
-- hard-coded for). If you swap embedding models you must DROP and recreate
-- cortex.memories with the new dimension AND revisit format_query_for_embedding.

-- pgvector must live in the extensions schema to match production alpha-DB.
-- db.py calls register_vector(conn, schema="extensions") specifically.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS vector SCHEMA extensions;

CREATE SCHEMA IF NOT EXISTS cortex;

-- cortex.memories — semantic memory store.
-- Columns are exactly what the code queries:
--   store_memory  -> INSERT (content, embedding_qwen, created_at)
--   search_memories (semantic) -> embedding_qwen <=> $1
--   search_memories (index)    -> content_tsv @@ query
--   recent_memories / get_memory -> id, content, created_at, forgotten
CREATE TABLE IF NOT EXISTS cortex.memories (
    id              bigserial PRIMARY KEY,
    content         text NOT NULL,
    embedding_qwen  vector(2560),
    created_at      timestamptz NOT NULL,
    forgotten       boolean NOT NULL DEFAULT false,
    content_tsv     tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

-- cortex.diary — the continuity letter. Each row is one diary entry.
-- add_to_diary INSERTs with an implicit created_at default; read_from_diary
-- reads by created_at; clock.start_of_day handles the 6 AM day-seam.
CREATE TABLE IF NOT EXISTS cortex.diary (
    id          bigserial PRIMARY KEY,
    content     text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Indexes
--
-- Vector index: deliberately NOT created here.
--
-- pgvector's HNSW index supports at most 2000 dimensions; Qwen 3 Embedding 4B
-- is 2560, so HNSW with `vector(2560)` is impossible. Production Alpha
-- handles this by using halfvec or IVFFlat; for a from-scratch dev instance
-- with an empty table, a sequential scan is fast enough that we don't need
-- ANY index. When you have real data, pick one of:
--   - IVFFlat (no dim limit; needs lists tuned to row count)
--       CREATE INDEX ... USING ivfflat (embedding_qwen vector_cosine_ops)
--         WITH (lists = 100);
--   - HNSW over halfvec (halve the precision; needs a column-type change)
--       ALTER TABLE cortex.memories
--         ALTER COLUMN embedding_qwen TYPE halfvec(2560);
--       CREATE INDEX ... USING hnsw (embedding_qwen halfvec_cosine_ops);
-- The semantic-search SQL works either way; only the EXPLAIN plan differs.

-- GIN over the generated tsvector for the "index" mode of search_memories.
CREATE INDEX IF NOT EXISTS memories_content_tsv_gin
    ON cortex.memories USING gin (content_tsv);

-- Created-at indexes for the date-bounded queries in search_memories and
-- the ORDER BY created_at DESC in recent_memories / read_from_diary.
CREATE INDEX IF NOT EXISTS memories_created_at_idx
    ON cortex.memories (created_at DESC);
CREATE INDEX IF NOT EXISTS diary_created_at_idx
    ON cortex.diary (created_at DESC);
