-- ============================================================
-- Sam's RFP Agent - Supabase Vector Store Setup
-- Based on Cole Medin's patterns from ottomator-agents
-- ============================================================
-- This script sets up Supabase for the RFP AI Agent with
-- OpenAI text-embedding-3-small (1536 dimensions)
-- ============================================================

-- Enable the pgvector extension (Supabase has this built-in!)
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- Table: rfp_documents
-- Stores RFP Q&A pairs with vector embeddings
-- ============================================================
CREATE TABLE IF NOT EXISTS rfp_documents (
    id BIGSERIAL PRIMARY KEY,
    
    -- Document identification
    file_id TEXT NOT NULL,              -- Google Drive file ID
    file_name TEXT NOT NULL,            -- Original filename
    
    -- Content
    question TEXT NOT NULL,             -- The RFP question
    answer TEXT NOT NULL,               -- The official answer
    content TEXT NOT NULL,              -- Combined searchable content (Q + A)
    
    -- Vector embedding (OpenAI text-embedding-3-small = 1536 dimensions)
    embedding vector(1536),
    
    -- Metadata (for filtering and display)
    metadata JSONB DEFAULT '{}'::jsonb,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique entries per file/question combo
    CONSTRAINT unique_file_question UNIQUE (file_id, question)
);

-- Create index on the embedding column for fast similarity search
CREATE INDEX IF NOT EXISTS rfp_documents_embedding_idx 
ON rfp_documents 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Create index on file_id for fast lookups
CREATE INDEX IF NOT EXISTS rfp_documents_file_id_idx ON rfp_documents(file_id);

-- Create index on metadata for filtering
CREATE INDEX IF NOT EXISTS rfp_documents_metadata_idx ON rfp_documents USING gin(metadata);

-- ============================================================
-- Function: match_rfp_documents
-- Vector similarity search function (Cole's pattern)
-- ============================================================
DROP FUNCTION IF EXISTS match_rfp_documents(vector, integer, jsonb);

CREATE OR REPLACE FUNCTION match_rfp_documents(
    query_embedding vector(1536),
    match_count int DEFAULT 5,
    filter jsonb DEFAULT '{}'
) 
RETURNS TABLE (
    id bigint,
    file_id text,
    file_name text,
    question text,
    answer text,
    content text,
    metadata jsonb,
    similarity float
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT
        rfp_documents.id,
        rfp_documents.file_id,
        rfp_documents.file_name,
        rfp_documents.question,
        rfp_documents.answer,
        rfp_documents.content,
        rfp_documents.metadata,
        1 - (rfp_documents.embedding <=> query_embedding) AS similarity
    FROM rfp_documents
    WHERE 
        rfp_documents.embedding IS NOT NULL
        AND (filter = '{}'::jsonb OR rfp_documents.metadata @> filter)
    ORDER BY rfp_documents.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- ============================================================
-- Table: rfp_ingestion_log
-- Tracks ingestion status and errors
-- ============================================================
CREATE TABLE IF NOT EXISTS rfp_ingestion_log (
    id BIGSERIAL PRIMARY KEY,
    file_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    status TEXT NOT NULL,               -- 'success', 'error', 'skipped'
    chunks_processed INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS rfp_ingestion_log_file_id_idx ON rfp_ingestion_log(file_id);
CREATE INDEX IF NOT EXISTS rfp_ingestion_log_status_idx ON rfp_ingestion_log(status);

-- ============================================================
-- Function: upsert_rfp_document
-- Upsert with conflict handling (prevents duplicates)
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_rfp_document(
    p_file_id TEXT,
    p_file_name TEXT,
    p_question TEXT,
    p_answer TEXT,
    p_content TEXT,
    p_embedding vector(1536),
    p_metadata JSONB DEFAULT '{}'
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    result_id BIGINT;
BEGIN
    INSERT INTO rfp_documents (file_id, file_name, question, answer, content, embedding, metadata, updated_at)
    VALUES (p_file_id, p_file_name, p_question, p_answer, p_content, p_embedding, p_metadata, NOW())
    ON CONFLICT (file_id, question) 
    DO UPDATE SET
        file_name = EXCLUDED.file_name,
        answer = EXCLUDED.answer,
        content = EXCLUDED.content,
        embedding = EXCLUDED.embedding,
        metadata = EXCLUDED.metadata,
        updated_at = NOW()
    RETURNING id INTO result_id;
    
    RETURN result_id;
END;
$$;

-- ============================================================
-- Optional: Row Level Security (RLS)
-- Enable if you want user-specific document access
-- ============================================================
-- ALTER TABLE rfp_documents ENABLE ROW LEVEL SECURITY;
-- 
-- CREATE POLICY "Users can view all documents" ON rfp_documents
--     FOR SELECT USING (true);
-- 
-- CREATE POLICY "Service role can manage documents" ON rfp_documents
--     FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Helpful Views
-- ============================================================

-- View: Recent ingestions
CREATE OR REPLACE VIEW recent_ingestions AS
SELECT 
    file_name,
    status,
    chunks_processed,
    error_message,
    created_at
FROM rfp_ingestion_log
ORDER BY created_at DESC
LIMIT 50;

-- View: Document stats
CREATE OR REPLACE VIEW rfp_stats AS
SELECT 
    COUNT(*) as total_documents,
    COUNT(DISTINCT file_id) as total_files,
    COUNT(CASE WHEN embedding IS NOT NULL THEN 1 END) as embedded_documents,
    MAX(created_at) as last_document_added
FROM rfp_documents;

-- ============================================================
-- Test the setup
-- ============================================================
-- Run this to verify everything is working:
-- SELECT * FROM rfp_stats;

-- ============================================================
-- DONE! Your Supabase is ready for the RFP Agent
-- ============================================================
-- Next steps:
-- 1. Copy your Supabase URL and anon/service_role key
-- 2. Import the sam_rfp_agent_supabase.json workflow into n8n
-- 3. Configure the Supabase credentials in n8n
-- 4. Connect your Google Drive folder
-- 5. Test with a sample RFP document!
