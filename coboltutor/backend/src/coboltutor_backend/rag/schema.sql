-- =============================================================================
-- CobolTutor knowledge-base schema (PostgreSQL + pgvector).
--
-- Applied by rag/store.py (PgVectorStore.ensure_schema), which first replaces
-- the {dimensions} placeholder with COBOLTUTOR_EMBEDDING_DIMENSIONS. That
-- number must match the embedding model: 768 for granite-embedding-english-r2.
-- Every statement is idempotent (IF NOT EXISTS), so applying it twice is safe.
--
-- Changing the embedding model means changing the vector size, which means
-- dropping and rebuilding the chunks table and re-running ingestion.
-- =============================================================================

-- pgvector adds the `vector` column type, distance operators such as <=>
-- (cosine distance), and the HNSW index used below.
CREATE EXTENSION IF NOT EXISTS vector;

-- Which embedding model built this index. Always exactly one row: the boolean
-- primary key can only be TRUE. rag/retriever.py compares it with the
-- configured embedder before searching (see models.IndexInfo).
CREATE TABLE IF NOT EXISTS index_info (
    id              boolean     PRIMARY KEY DEFAULT TRUE CHECK (id),
    embedding_model text        NOT NULL,
    dimensions      integer     NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- One row per chunk (see models.Chunk for what each column means).
CREATE TABLE IF NOT EXISTS chunks (
    id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Citation and filtering metadata (FR-3, FR-10).
    source_id    text        NOT NULL,
    source_title text        NOT NULL,
    url          text        NOT NULL,
    dialect      text        NOT NULL,
    kind         text        NOT NULL CHECK (kind IN ('cobol', 'prose')),
    -- Where the chunk sits in its source. Which ones are set depends on kind.
    division     text,
    section      text,
    paragraph    text,
    heading      text,
    start_line   integer,
    end_line     integer,
    -- The passage itself, its fingerprint, and its embedding.
    content      text        NOT NULL,
    content_hash text        NOT NULL,
    embedding    vector({dimensions}) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    -- Re-ingesting an unchanged chunk must not create a duplicate.
    UNIQUE (source_id, content_hash)
);

-- Re-ingesting one source deletes its old chunks first; this makes that fast.
CREATE INDEX IF NOT EXISTS chunks_source_id_idx ON chunks (source_id);

-- Approximate nearest-neighbour index for cosine distance. HNSW is pgvector's
-- recommended index: fast queries, no training step, fine for small tables.
-- pgvector can index at most 2000 dimensions for the `vector` type.
CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw_idx
    ON chunks USING hnsw (embedding vector_cosine_ops);
