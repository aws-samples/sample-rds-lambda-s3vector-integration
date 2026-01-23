-- S3VL Query Functions for Sample-RDS-Lambda-S3Vector Integration
-- AWS API aligned query functions in s3vl schema
-- Implements query_vectors() function matching AWS QueryVectors API

-- Core vector similarity search function with AWS API alignment
-- Maps to AWS S3 Vector QueryVectors API
-- Supports optional metadata filtering to filter results based on metadata attributes
CREATE OR REPLACE FUNCTION s3vl.query_vectors(
    query_vector FLOAT8[],
    index_name TEXT DEFAULT NULL,
    index_arn TEXT DEFAULT NULL,
    top_k INTEGER DEFAULT 10,
    return_metadata BOOLEAN DEFAULT TRUE,
    metadata_filter JSONB DEFAULT NULL
) RETURNS TABLE(
    vector_id TEXT,
    distance FLOAT8,
    similarity_score FLOAT8,
    metadata JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    config_record RECORD;
    resolved_arn TEXT;
    lambda_payload TEXT;
    lambda_response TEXT;
    response_json JSON;
    result_record RECORD;
BEGIN
    -- Basic validation
    IF query_vector IS NULL OR array_length(query_vector, 1) IS NULL THEN
        RAISE EXCEPTION 's3vl.query_vectors: query_vector cannot be null or empty';
    END IF;
    
    IF top_k IS NULL OR top_k <= 0 THEN
        RAISE EXCEPTION 's3vl.query_vectors: top_k must be a positive integer';
    END IF;
    
    -- Validate that exactly one of index_name or index_arn is provided
    IF (index_name IS NULL AND index_arn IS NULL) THEN
        RAISE EXCEPTION 's3vl.query_vectors: Either index_name or index_arn must be provided';
    END IF;
    
    IF (index_name IS NOT NULL AND index_arn IS NOT NULL) THEN
        RAISE EXCEPTION 's3vl.query_vectors: Provide either index_name or index_arn, not both';
    END IF;
    
    -- Resolve ARN using s3vl schema function
    IF index_name IS NOT NULL THEN
        -- Use index registry to resolve ARN from name
        resolved_arn := s3vl.resolve_index_arn(index_name);
    ELSE
        resolved_arn := index_arn;
    END IF;
    
    -- Get Lambda configuration from s3vl.config table
    SELECT * INTO config_record 
    FROM s3vl.config 
    ORDER BY updated_at DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 's3vl.query_vectors: No Lambda configuration found. Run s3vl.configure() first.';
    END IF;
    
    -- Build Lambda payload with new operation name 'query_vectors'
    lambda_payload := json_build_object(
        'operation', 'query_vectors',
        'index_arn', resolved_arn,
        'query_vector', array_to_json(query_vector),
        'top_k', top_k,
        'return_metadata', return_metadata
    )::TEXT;
    
    -- Add metadata_filter to payload if provided
    IF metadata_filter IS NOT NULL THEN
        lambda_payload := (lambda_payload::jsonb || json_build_object('metadata_filter', metadata_filter)::jsonb)::TEXT;
    END IF;
    
    -- Invoke Lambda
    SELECT payload INTO lambda_response
    FROM aws_lambda.invoke(config_record.lambda_arn, lambda_payload::jsonb);
    
    IF lambda_response IS NULL THEN
        RAISE EXCEPTION 's3vl.query_vectors: Lambda function returned null response';
    END IF;
    
    -- Parse response
    response_json := lambda_response::JSON;
    
    IF (response_json->>'success')::BOOLEAN != TRUE THEN
        RAISE EXCEPTION 's3vl.query_vectors: Lambda error: %', COALESCE(response_json->'error'->>'message', 'Unknown error');
    END IF;
    
    -- Return results
    FOR result_record IN 
        SELECT 
            (result->>'vector_id')::TEXT as vector_id,
            (result->>'distance')::FLOAT8 as distance,
            (result->>'similarity_score')::FLOAT8 as similarity_score,
            COALESCE((result->>'metadata')::JSONB, '{}'::JSONB) as metadata
        FROM json_array_elements(response_json->'result') as result
    LOOP
        vector_id := result_record.vector_id;
        distance := result_record.distance;
        similarity_score := result_record.similarity_score;
        metadata := result_record.metadata;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END;
$$;

-- Add function comment
COMMENT ON FUNCTION s3vl.query_vectors(FLOAT8[], TEXT, TEXT, INTEGER, BOOLEAN, JSONB) IS 
'Query vectors using AWS S3 Vector QueryVectors API. Parameters align with AWS API: index_arn, query_vector, top_k, return_metadata, metadata_filter. Provide either index_name or index_arn. metadata_filter is optional and allows filtering results based on metadata attributes.';

-- Core vector retrieval function with AWS API alignment
-- Maps to AWS S3 Vector GetVectors API
CREATE OR REPLACE FUNCTION s3vl.get_vectors(
    vector_ids TEXT[],
    index_name TEXT DEFAULT NULL,
    index_arn TEXT DEFAULT NULL,
    include_vector_data BOOLEAN DEFAULT TRUE,
    include_metadata BOOLEAN DEFAULT TRUE
) RETURNS TABLE(
    vector_id TEXT,
    embedding FLOAT8[],
    metadata JSONB,
    found BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    config_record RECORD;
    resolved_arn TEXT;
    lambda_payload TEXT;
    lambda_response TEXT;
    response_json JSON;
    result_record RECORD;
BEGIN
    -- Basic validation
    IF vector_ids IS NULL OR array_length(vector_ids, 1) IS NULL THEN
        RAISE EXCEPTION 's3vl.get_vectors: vector_ids cannot be null or empty';
    END IF;
    
    -- Validate that exactly one of index_name or index_arn is provided
    IF (index_name IS NULL AND index_arn IS NULL) THEN
        RAISE EXCEPTION 's3vl.get_vectors: Either index_name or index_arn must be provided';
    END IF;
    
    IF (index_name IS NOT NULL AND index_arn IS NOT NULL) THEN
        RAISE EXCEPTION 's3vl.get_vectors: Provide either index_name or index_arn, not both';
    END IF;
    
    -- Resolve ARN using s3vl schema function
    IF index_name IS NOT NULL THEN
        -- Use index registry to resolve ARN from name
        resolved_arn := s3vl.resolve_index_arn(index_name);
    ELSE
        resolved_arn := index_arn;
    END IF;
    
    -- Get Lambda configuration from s3vl.config table
    SELECT * INTO config_record 
    FROM s3vl.config 
    ORDER BY updated_at DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 's3vl.get_vectors: No Lambda configuration found. Run s3vl.configure() first.';
    END IF;
    
    -- Build Lambda payload with new operation name 'get_vectors'
    lambda_payload := json_build_object(
        'operation', 'get_vectors',
        'index_arn', resolved_arn,
        'vector_ids', array_to_json(vector_ids),
        'include_vector_data', include_vector_data,
        'include_metadata', include_metadata
    )::TEXT;
    
    -- Invoke Lambda
    SELECT payload INTO lambda_response
    FROM aws_lambda.invoke(config_record.lambda_arn, lambda_payload::jsonb);
    
    IF lambda_response IS NULL THEN
        RAISE EXCEPTION 's3vl.get_vectors: Lambda function returned null response';
    END IF;
    
    -- Parse response
    response_json := lambda_response::JSON;
    
    IF (response_json->>'success')::BOOLEAN != TRUE THEN
        RAISE EXCEPTION 's3vl.get_vectors: Lambda error: %', COALESCE(response_json->'error'->>'message', 'Unknown error');
    END IF;
    
    -- Return results
    FOR result_record IN 
        SELECT 
            (result->>'vector_id')::TEXT as vector_id,
            CASE 
                WHEN (result->>'found')::BOOLEAN = TRUE AND (result->>'embedding') IS NOT NULL 
                THEN string_to_array(trim(both '[]' from (result->>'embedding')), ',')::FLOAT8[]
                ELSE NULL 
            END as embedding,
            COALESCE((result->>'metadata')::JSONB, '{}'::JSONB) as metadata,
            COALESCE((result->>'found')::BOOLEAN, FALSE) as found
        FROM json_array_elements(response_json->'result') as result
    LOOP
        vector_id := result_record.vector_id;
        embedding := result_record.embedding;
        metadata := result_record.metadata;
        found := result_record.found;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END;
$$;

-- Add function comment
COMMENT ON FUNCTION s3vl.get_vectors(TEXT[], TEXT, TEXT, BOOLEAN, BOOLEAN) IS 
'Get vectors by ID using AWS S3 Vector GetVectors API. Parameters align with AWS API: index_arn, vector_ids, include_vector_data, include_metadata. Provide either index_name or index_arn.';

-- Core vector list function with AWS API alignment and pagination support
-- Maps to AWS S3 Vector ListVectors API
CREATE OR REPLACE FUNCTION s3vl.list_vectors(
    index_arn TEXT DEFAULT NULL,
    index_name TEXT DEFAULT NULL,
    max_results INTEGER DEFAULT 100,
    next_token TEXT DEFAULT NULL,
    return_data BOOLEAN DEFAULT FALSE,
    return_metadata BOOLEAN DEFAULT TRUE
) RETURNS TABLE(
    vector_id TEXT,
    vector_data FLOAT8[],
    metadata JSONB,
    response_next_token TEXT,
    total_count INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    config_record RECORD;
    resolved_arn TEXT;
    lambda_payload TEXT;
    lambda_response TEXT;
    response_json JSON;
    result_record RECORD;
    response_next_token TEXT;
    response_total_count INTEGER;
BEGIN
    -- Basic validation
    IF max_results IS NULL OR max_results <= 0 OR max_results > 1000 THEN
        RAISE EXCEPTION 's3vl.list_vectors: max_results must be between 1 and 1000, got: %', max_results;
    END IF;
    
    -- Validate that exactly one of index_name or index_arn is provided
    IF (index_name IS NULL AND index_arn IS NULL) THEN
        RAISE EXCEPTION 's3vl.list_vectors: Either index_name or index_arn must be provided';
    END IF;
    
    IF (index_name IS NOT NULL AND index_arn IS NOT NULL) THEN
        RAISE EXCEPTION 's3vl.list_vectors: Provide either index_name or index_arn, not both';
    END IF;
    
    -- Resolve ARN using s3vl schema function
    IF index_name IS NOT NULL THEN
        -- Use index registry to resolve ARN from name
        resolved_arn := s3vl.resolve_index_arn(index_name);
    ELSE
        resolved_arn := index_arn;
    END IF;
    
    -- Get Lambda configuration from s3vl.config table
    SELECT * INTO config_record 
    FROM s3vl.config 
    ORDER BY updated_at DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 's3vl.list_vectors: No Lambda configuration found. Run s3vl.configure() first.';
    END IF;
    
    -- Build Lambda payload with new operation name 'list_vectors'
    lambda_payload := json_build_object(
        'operation', 'list_vectors',
        'index_arn', resolved_arn,
        'max_results', max_results,
        'return_data', return_data,
        'return_metadata', return_metadata
    )::TEXT;
    
    -- Add next_token if provided
    IF next_token IS NOT NULL THEN
        lambda_payload := (lambda_payload::jsonb || json_build_object('next_token', next_token)::jsonb)::TEXT;
    END IF;
    
    -- Invoke Lambda
    SELECT payload INTO lambda_response
    FROM aws_lambda.invoke(config_record.lambda_arn, lambda_payload::jsonb);
    
    IF lambda_response IS NULL THEN
        RAISE EXCEPTION 's3vl.list_vectors: Lambda function returned null response';
    END IF;
    
    -- Parse response
    response_json := lambda_response::JSON;
    
    IF (response_json->>'success')::BOOLEAN != TRUE THEN
        RAISE EXCEPTION 's3vl.list_vectors: Lambda error: %', COALESCE(response_json->'error'->>'message', 'Unknown error');
    END IF;
    
    -- Extract pagination information from response
    response_next_token := response_json->'result'->>'next_token';
    response_total_count := COALESCE((response_json->'result'->>'total_count')::INTEGER, 0);
    
    -- Return results
    FOR result_record IN 
        SELECT 
            (result->>'vector_id')::TEXT as vector_id,
            CASE 
                WHEN return_data AND json_extract_path_text(result, 'vector_data') IS NOT NULL 
                THEN ARRAY(SELECT json_array_elements_text(result->'vector_data'))::FLOAT8[]
                ELSE NULL
            END as vector_data,
            CASE 
                WHEN return_metadata 
                THEN COALESCE((result->>'metadata')::JSONB, '{}'::JSONB)
                ELSE NULL
            END as metadata
        FROM json_array_elements(response_json->'result'->'vectors') as result
    LOOP
        vector_id := result_record.vector_id;
        vector_data := result_record.vector_data;
        metadata := result_record.metadata;
        next_token := response_next_token;
        total_count := response_total_count;
        RETURN NEXT;
    END LOOP;
    
    -- If no vectors were returned, still return pagination info
    IF NOT FOUND THEN
        vector_id := NULL;
        vector_data := NULL;
        metadata := NULL;
        next_token := response_next_token;
        total_count := response_total_count;
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$$;

-- Add function comment
COMMENT ON FUNCTION s3vl.list_vectors(TEXT, TEXT, INTEGER, TEXT, BOOLEAN, BOOLEAN) IS 
'List vectors using AWS S3 Vector ListVectors API. Parameters align with AWS API: index_arn, max_results, next_token, return_data, return_metadata. Provide either index_name or index_arn.';