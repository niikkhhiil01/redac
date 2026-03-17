-- SQL DDL for Phase 1 Database Schema

-- Required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS vector;

-- Enumerated types
CREATE TYPE IF NOT EXISTS subscription_tier AS ENUM ('free','pro','team');

-- Table: users
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    subscription_tier subscription_tier DEFAULT 'free',
    stripe_customer_id VARCHAR(255),
    tokens_remaining INTEGER DEFAULT 50000,
    tokens_reset_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP
);

-- Table: papers (central corpus)
CREATE TABLE IF NOT EXISTS papers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doi VARCHAR(255) UNIQUE,
    title TEXT NOT NULL,
    abstract TEXT,
    authors JSONB NOT NULL,
    year INTEGER,
    journal TEXT,
    citation_count INTEGER DEFAULT 0,
    embedding vector(1536),
    source_database VARCHAR(50),
    provenance_log JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for papers (hybrid search support)
CREATE INDEX IF NOT EXISTS idx_papers_embedding
    ON papers USING ivfflat (embedding vector_l2_ops)
    WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_papers_abstract_fts
    ON papers USING gin (to_tsvector('english', coalesce(abstract, '')));

CREATE INDEX IF NOT EXISTS idx_papers_year ON papers (year);

-- Table: private_documents
CREATE TABLE IF NOT EXISTS private_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    doi VARCHAR(255),
    title_encrypted BYTEA NOT NULL,
    content_encrypted BYTEA NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    embedding vector(1536),
    tags TEXT[],
    notes_encrypted BYTEA,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_private_documents_user ON private_documents (user_id);

-- Row Level Security for private_documents
ALTER TABLE private_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS private_documents_owner_policy
    ON private_documents
    USING (user_id = current_setting('app.current_user_id')::UUID)
    WITH CHECK (user_id = current_setting('app.current_user_id')::UUID);

-- Table: token_logs
CREATE TABLE IF NOT EXISTS token_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(50),
    tokens_deducted INTEGER,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Indexes for token_logs
CREATE INDEX IF NOT EXISTS idx_token_logs_user ON token_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_token_logs_timestamp ON token_logs (timestamp);
