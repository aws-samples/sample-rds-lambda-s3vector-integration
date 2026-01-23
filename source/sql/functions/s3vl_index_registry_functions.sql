-- S3VL Index Registry Management Functions
-- Functions to manage friendly index names and ARN mappings in s3vl schema
-- Functions provide AWS API aligned naming for index registry management

-- Function to register a new index name mapping
CREATE OR REPLACE FUNCTION s3vl.register_index(
    index_name_param TEXT,
    index_arn_param TEXT,
    description_param TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    bucket_name_extracted TEXT;
    region_extracted TEXT;
    account_id_extracted TEXT;
    arn_parts TEXT[];
BEGIN
    -- Validate input parameters
    IF index_name_param IS NULL OR trim(index_name_param) = '' THEN
        RAISE EXCEPTION 's3vl.register_index: index_name cannot be null or empty';
    END IF;
    
    IF index_arn_param IS NULL OR trim(index_arn_param) = '' THEN
        RAISE EXCEPTION 's3vl.register_index: index_arn cannot be null or empty';
    END IF;
    
    -- Parse ARN to extract components
    -- ARN format: arn:aws:s3vectors:region:account:bucket/bucket-name/index/index-name
    arn_parts := string_to_array(index_arn_param, ':');
    
    IF array_length(arn_parts, 1) != 6 OR arn_parts[1] != 'arn' OR arn_parts[2] != 'aws' OR arn_parts[3] != 's3vectors' THEN
        RAISE EXCEPTION 's3vl.register_index: Invalid S3 Vector ARN format: %', index_arn_param;
    END IF;
    
    region_extracted := arn_parts[4];
    account_id_extracted := arn_parts[5];
    
    -- Extract bucket name from the resource part (arn_parts[6])
    -- Resource format: bucket/bucket-name/index/index-name
    IF NOT (arn_parts[6] ~ '^bucket/[^/]+/index/[^/]+$') THEN
        RAISE EXCEPTION 's3vl.register_index: Invalid S3 Vector resource format in ARN: %', arn_parts[6];
    END IF;
    
    bucket_name_extracted := split_part(split_part(arn_parts[6], '/', 2), '/', 1);
    
    -- Insert or update the registry entry
    INSERT INTO s3vl.index_registry (
        index_name, 
        index_arn, 
        description, 
        bucket_name, 
        region, 
        account_id,
        is_active
    ) VALUES (
        index_name_param,
        index_arn_param,
        description_param,
        bucket_name_extracted,
        region_extracted,
        account_id_extracted,
        TRUE
    )
    ON CONFLICT (index_name) DO UPDATE SET
        index_arn = EXCLUDED.index_arn,
        description = COALESCE(EXCLUDED.description, s3vl.index_registry.description),
        bucket_name = EXCLUDED.bucket_name,
        region = EXCLUDED.region,
        account_id = EXCLUDED.account_id,
        is_active = TRUE,
        updated_at = CURRENT_TIMESTAMP;
    
    RAISE NOTICE 's3vl.register_index: Index "%" registered successfully with ARN: %', index_name_param, index_arn_param;
    RETURN TRUE;
    
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 's3vl.register_index: Failed to register index "%": %', index_name_param, SQLERRM;
END;
$$;

-- Function to resolve index name to ARN
CREATE OR REPLACE FUNCTION s3vl.resolve_index_arn(
    index_name_param TEXT
) RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    resolved_arn TEXT;
BEGIN
    -- Validate input
    IF index_name_param IS NULL OR trim(index_name_param) = '' THEN
        RAISE EXCEPTION 's3vl.resolve_index_arn: index_name cannot be null or empty';
    END IF;
    
    -- If the parameter is already an ARN, return it as-is
    IF index_name_param ~ '^arn:aws:s3vectors:' THEN
        RETURN index_name_param;
    END IF;
    
    -- Look up the ARN from the registry
    SELECT index_arn INTO resolved_arn
    FROM s3vl.index_registry
    WHERE index_name = index_name_param 
    AND is_active = TRUE;
    
    IF resolved_arn IS NULL THEN
        RAISE EXCEPTION 's3vl.resolve_index_arn: Index name "%" not found in registry. Register it first with s3vl.register_index()', index_name_param;
    END IF;
    
    RETURN resolved_arn;
END;
$$;

-- Function to list all registered indexes
CREATE OR REPLACE FUNCTION s3vl.list_indexes()
RETURNS TABLE(
    index_name TEXT,
    index_arn TEXT,
    description TEXT,
    bucket_name TEXT,
    region TEXT,
    account_id TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    is_active BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.index_name,
        r.index_arn,
        r.description,
        r.bucket_name,
        r.region,
        r.account_id,
        r.created_at,
        r.updated_at,
        r.is_active
    FROM s3vl.index_registry r
    ORDER BY r.is_active DESC, r.index_name ASC;
END;
$$;

-- Function to get index details by name
CREATE OR REPLACE FUNCTION s3vl.get_index_info(
    index_name_param TEXT
) RETURNS TABLE(
    index_name TEXT,
    index_arn TEXT,
    description TEXT,
    bucket_name TEXT,
    region TEXT,
    account_id TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    is_active BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.index_name,
        r.index_arn,
        r.description,
        r.bucket_name,
        r.region,
        r.account_id,
        r.created_at,
        r.updated_at,
        r.is_active
    FROM s3vl.index_registry r
    WHERE r.index_name = index_name_param;
    
    IF NOT FOUND THEN
        RAISE NOTICE 's3vl.get_index_info: Index "%" not found in registry', index_name_param;
    END IF;
END;
$$;

-- Function to deactivate an index (soft delete)
CREATE OR REPLACE FUNCTION s3vl.deactivate_index(
    index_name_param TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    rows_affected INTEGER;
BEGIN
    UPDATE s3vl.index_registry
    SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
    WHERE index_name = index_name_param;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    IF rows_affected = 0 THEN
        RAISE EXCEPTION 's3vl.deactivate_index: Index "%" not found in registry', index_name_param;
    END IF;
    
    RAISE NOTICE 's3vl.deactivate_index: Index "%" deactivated successfully', index_name_param;
    RETURN TRUE;
END;
$$;

-- Function to reactivate an index
CREATE OR REPLACE FUNCTION s3vl.activate_index(
    index_name_param TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    rows_affected INTEGER;
BEGIN
    UPDATE s3vl.index_registry
    SET is_active = TRUE, updated_at = CURRENT_TIMESTAMP
    WHERE index_name = index_name_param;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    IF rows_affected = 0 THEN
        RAISE EXCEPTION 's3vl.activate_index: Index "%" not found in registry', index_name_param;
    END IF;
    
    RAISE NOTICE 's3vl.activate_index: Index "%" activated successfully', index_name_param;
    RETURN TRUE;
END;
$$;

-- Function to remove an index from registry (hard delete)
CREATE OR REPLACE FUNCTION s3vl.unregister_index(
    index_name_param TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    rows_affected INTEGER;
BEGIN
    DELETE FROM s3vl.index_registry
    WHERE index_name = index_name_param;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    IF rows_affected = 0 THEN
        RAISE EXCEPTION 's3vl.unregister_index: Index "%" not found in registry', index_name_param;
    END IF;
    
    RAISE NOTICE 's3vl.unregister_index: Index "%" removed from registry', index_name_param;
    RETURN TRUE;
END;
$$;

-- Add helpful comments for the functions
COMMENT ON FUNCTION s3vl.register_index(TEXT, TEXT, TEXT) IS 'Register a new S3 Vector index with friendly name mapping';
COMMENT ON FUNCTION s3vl.resolve_index_arn(TEXT) IS 'Resolve index name to full S3 Vector ARN, or return ARN if already provided';
COMMENT ON FUNCTION s3vl.list_indexes() IS 'List all registered S3 Vector indexes with their details';
COMMENT ON FUNCTION s3vl.get_index_info(TEXT) IS 'Get detailed information about a specific registered index';
COMMENT ON FUNCTION s3vl.deactivate_index(TEXT) IS 'Deactivate an index (soft delete) - keeps registry entry but marks as inactive';
COMMENT ON FUNCTION s3vl.activate_index(TEXT) IS 'Reactivate a deactivated index';
COMMENT ON FUNCTION s3vl.unregister_index(TEXT) IS 'Permanently remove an index from the registry (hard delete)';