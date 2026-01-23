-- PostgreSQL return types for S3VL schema (S3 Vector Lambda Integration)
-- Defines structured return types for vector operations in s3vl schema
-- These types align with AWS S3 Vector API naming conventions

-- Return type for individual search results
CREATE TYPE s3vl.search_result AS (
    vector_id TEXT,
    distance FLOAT8,
    similarity_score FLOAT8,
    metadata JSONB
);

-- Return type for individual query results
CREATE TYPE s3vl.query_result AS (
    vector_id TEXT,
    found BOOLEAN,
    vector FLOAT8[],
    metadata JSONB
);

-- Return type for individual vector entries in list operations
CREATE TYPE s3vl.list_result AS (
    vector_id TEXT,
    vector_data FLOAT8[],
    metadata JSONB
);

-- Return type for paginated list responses
CREATE TYPE s3vl.list_response AS (
    vectors s3vl.list_result[],
    next_token TEXT,
    total_count INTEGER
);