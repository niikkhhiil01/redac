# Schema Design Decisions for Phase 1

## Overview
Phase 1 needs to balance rapid development with the security guarantees outlined in `redac.md`. The schema therefore separates public metadata (central corpus) from user-generated private content, adds instrumentation for token consumption, and bakes in privacy controls at the database layer.

## Table-by-Table Rationale

### users
Stores authentication details, subscription metadata, and token state for every researcher. `subscription_tier` uses a dedicated ENUM so application logic can rely on strict values (`free`, `pro`, `team`). Token counters (`tokens_remaining`, `tokens_reset_date`) live here to avoid an extra join on every quota check. `stripe_customer_id` links back to billing events.

### papers (central corpus)
Holds only public metadata per Redac policy (titles, abstracts, provenance). `authors` is JSONB to capture `{name, affiliation, orcid}` tuples. `provenance_log` keeps the enrichment metadata (API source, retrieved_at, checksum) to meet the transparency/audit requirement. `source_database` flags whether a record came from Crossref, OpenAlex, etc.

Indexes enable the hybrid search strategy:
- **GIN full-text index** over `to_tsvector('english', abstract)` feeds BM25/pg_search queries.
- **IVFFLAT vector index** on `embedding vector(1536)` powers semantic similarity via pgvector.
- **BTREE on `year`** enables fast filtering for recency windows.

### private_documents
Per-user encrypted corpus. Only ciphertext (`title_encrypted`, `content_encrypted`, `notes_encrypted`) plus a `content_hash` for integrity checks are stored. `embedding vector(1536)` is computed on decrypted content inside the trusted runtime so we can offer semantic search without persisting plaintext. `tags` stays as a TEXT[] for lightweight faceting.

Row Level Security is mandatory: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` plus a policy that pins access to `current_setting('app.current_user_id')::UUID`. Application sessions must set `SET app.current_user_id = '<uuid>'` before queries so PostgreSQL enforces isolation even if an application bug leaks SQL.

### token_logs
Immutable ledger for token deductions (searches, generations). Tracks `user_id`, `action`, `tokens_deducted`, and a timestamp. Separate indexes on `user_id` and `timestamp` allow dashboard lookups (per-user history) and compliance exports (e.g., prior 30 days). If a user is deleted we retain historic token spend by leaving the record with a NULL user_id.

## Hybrid Search (BM25 + Vector)
Search endpoints will run two queries:
1. BM25 via `pg_search`/`ts_rank_cd` against the GIN index on `abstract` (and later titles).
2. Vector similarity via `embedding <=> query_embedding` using the IVFFLAT index.
Results are rescored in application code (weighted blend) to return the top-k items while tracking provenance for each hit.

## Private Data Encryption
All encrypted blobs use AES-256-GCM provided by the application service. The database only stores ciphertext; authentication tags live alongside the payload inside the BYTEA columns. Key management strategy:
- A root KMS key (e.g., AWS KMS) derives per-user data keys.
- Derived keys are stored encrypted (envelope encryption) and cached in memory only during a request.
- Rotation happens by re-encrypting the per-user key and re-wrapping document blobs lazily the next time they are accessed.

## Provenance Logging
`provenance_log` (JSONB) records the enrichment pipeline metadata: API source, query params, retrieval timestamp, checksum of the original payload, and any normalization steps. This powers the “radical transparency” pillar and lets us regenerate the exact steps that led to a paper entering the corpus.

## Enrichment Pipeline
A scheduled job (cron + worker) pulls deltas from Crossref/OpenAlex, normalizes records, calculates embeddings, and upserts into `papers`. Each run writes provenance details, updates `citation_count`, and refreshes `updated_at`. Failed ingests get retried with exponential backoff and logged for manual review.
