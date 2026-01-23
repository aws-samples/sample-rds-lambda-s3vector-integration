-- RDS Lambda S3Vector Integration Installation Script
-- This script installs the s3vl schema with AWS API aligned functions
-- Creates organized s3vl schema structure for S3 Vector Lambda integration

-- Check prerequisites
DO $$
BEGIN
    -- Check if aws_lambda extension is available
    IF NOT EXISTS (
        SELECT 1 FROM pg_available_extensions WHERE name = 'aws_lambda'
    ) THEN
        RAISE EXCEPTION 'aws_lambda extension is required but not available. Please install aws_lambda extension first.';
    END IF;
    
    -- Create aws_lambda extension if not exists
    CREATE EXTENSION IF NOT EXISTS aws_lambda CASCADE;
    
    RAISE NOTICE 'Prerequisites check passed. Installing Sample RDS Lambda S3Vector Integration with s3vl schema...';
END
$$;

-- Create the s3vl schema
CREATE SCHEMA IF NOT EXISTS s3vl;

-- Create s3vl schema and new return types
\i sql/types/s3vl_return_types.sql

-- Create s3vl schema tables (config and index_registry)
\i sql/tables/s3vl_schema_tables.sql

-- Install s3vl configuration management functions
\i sql/functions/s3vl_config_functions.sql

-- Install s3vl index registry management functions
\i sql/functions/s3vl_index_registry_functions.sql

-- Install s3vl query functions (AWS API aligned: query_vectors, get_vectors, list_vectors)
\i sql/functions/s3vl_query_functions.sql

-- Verify installation
DO $$
DECLARE
    missing_objects TEXT[];
    expected_objects TEXT[] := ARRAY[
        'activate_index:FUNCTION',
        'configure:FUNCTION', 
        'deactivate_index:FUNCTION',
        'get_config:FUNCTION', 
        'get_index_info:FUNCTION', 
        'get_vectors:FUNCTION',
        'list_indexes:FUNCTION', 
        'list_vectors:FUNCTION', 
        'query_vectors:FUNCTION',
        'register_index:FUNCTION', 
        'resolve_index_arn:FUNCTION', 
        'unregister_index:FUNCTION',
        'update_config_timestamp:FUNCTION', 
        'update_index_registry_timestamp:FUNCTION',
        'validate_config:FUNCTION', 
        'config:TABLE', 
        'index_registry:TABLE'
    ];
    obj TEXT;
    obj_name TEXT;
    obj_type TEXT;
BEGIN
    FOREACH obj IN ARRAY expected_objects LOOP
        obj_name := split_part(obj, ':', 1);
        obj_type := split_part(obj, ':', 2);
        
        IF obj_type = 'FUNCTION' THEN
            IF NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 's3vl' AND routine_name = obj_name) THEN
                missing_objects := array_append(missing_objects, obj_name || ' (FUNCTION)');
            END IF;
        ELSIF obj_type = 'TABLE' THEN
            IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 's3vl' AND table_name = obj_name) THEN
                missing_objects := array_append(missing_objects, obj_name || ' (TABLE)');
            END IF;
        END IF;
    END LOOP;
    
    IF array_length(missing_objects, 1) > 0 THEN
        RAISE NOTICE 'Missing objects: %', array_to_string(missing_objects, ', ');
    ELSE
        RAISE NOTICE 'All expected objects found in s3vl schema';
    END IF;
END $$;
