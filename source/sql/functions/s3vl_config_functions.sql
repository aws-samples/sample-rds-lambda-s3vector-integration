-- S3VL Configuration Management Functions
-- AWS API aligned configuration functions for Sample RDS Lambda S3Vector Integration
-- These functions work with the s3vl.config table in the dedicated s3vl schema

-- Function to configure Lambda function endpoint and settings with enhanced error handling
CREATE OR REPLACE FUNCTION s3vl.configure(
    lambda_arn TEXT,
    aws_region TEXT DEFAULT 'us-west-2',
    timeout_seconds INTEGER DEFAULT 30
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    test_result RECORD;
BEGIN
    -- Enhanced input validation with detailed error messages
    IF lambda_arn IS NULL OR trim(lambda_arn) = '' THEN
        RAISE EXCEPTION USING 
            ERRCODE = 'invalid_parameter_value',
            MESSAGE = 'Parameter "lambda_arn" cannot be null or empty',
            DETAIL = 'Lambda ARN is required to configure the S3 Vector integration',
            HINT = 'Provide a valid Lambda function ARN: arn:aws:lambda:region:account:function:function-name';
    END IF;
    
    IF aws_region IS NULL OR trim(aws_region) = '' THEN
        RAISE EXCEPTION USING 
            ERRCODE = 'invalid_parameter_value',
            MESSAGE = 'Parameter "aws_region" cannot be null or empty',
            DETAIL = 'AWS region is required for Lambda function configuration',
            HINT = 'Provide a valid AWS region code (e.g., us-west-2, us-west-2, eu-west-1)';
    END IF;
    
    IF timeout_seconds IS NULL OR timeout_seconds <= 0 OR timeout_seconds > 900 THEN
        RAISE EXCEPTION USING 
            ERRCODE = 'invalid_parameter_value',
            MESSAGE = format('Parameter "timeout_seconds" must be between 1 and 900, got: %s', timeout_seconds),
            DETAIL = 'Timeout controls how long to wait for Lambda function responses',
            HINT = 'Use 30-60 seconds for typical operations';
    END IF;

    -- Clear existing configuration and insert new one with error handling
    BEGIN
        DELETE FROM s3vl.config;
        
        INSERT INTO s3vl.config (lambda_arn, aws_region, timeout_seconds, updated_at)
        VALUES (lambda_arn, aws_region, timeout_seconds, CURRENT_TIMESTAMP);
        
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION USING 
            ERRCODE = 'configuration_error',
            MESSAGE = format('Failed to save Lambda configuration: %s', SQLERRM),
            DETAIL = 'Unable to update s3vl.config table',
            HINT = 'Check database permissions and table structure';
    END;
    
    -- Test the configuration immediately after setting it
    BEGIN
        SELECT * INTO test_result FROM s3vl.validate_config() LIMIT 1;
        
        IF test_result.is_valid THEN
            RAISE NOTICE 'Lambda integration configuration updated and validated successfully. Lambda ARN: %, Region: %, Response time: % ms', 
                lambda_arn, aws_region, test_result.response_time_ms;
        ELSE
            RAISE WARNING 'Lambda integration configuration saved but validation failed: %', test_result.error_message;
            RAISE NOTICE 'Configuration saved anyway. You can test connectivity later with s3vl.validate_config()';
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Lambda integration configuration saved but immediate validation failed: %', SQLERRM;
        RAISE NOTICE 'Configuration saved. Test connectivity with s3vl.validate_config() when ready';
    END;
    
    RETURN TRUE;
END;
$$;

-- Simplified function to validate Lambda connectivity using availability_check operation
-- 
-- This function performs a lightweight connectivity test by invoking the Lambda function
-- with a minimal "availability_check" operation. It validates that:
-- 1. Lambda configuration exists in s3vl.config table
-- 2. PostgreSQL can successfully invoke the Lambda function
-- 3. Lambda responds with a valid JSON containing success field
--
-- The function has been simplified from ~250 lines to ~80 lines by removing:
-- - Complex health checking and service status parsing
-- - Nested error categorization and hint generation
-- - Response time performance warnings
-- - Multi-level health checks
--
-- Returns a single row with validation status, configuration details, and response time.
-- Use this function after calling s3vl.configure() to verify the integration is working.
CREATE OR REPLACE FUNCTION s3vl.validate_config() 
RETURNS TABLE(
    is_valid BOOLEAN,
    lambda_arn TEXT,
    aws_region TEXT,
    error_message TEXT,
    response_time_ms INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    config_record RECORD;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    response_time INTEGER;
    lambda_response TEXT;
    test_payload TEXT;
    response_json JSON;
    success_value TEXT;
BEGIN
    -- Get current configuration
    SELECT * INTO config_record 
    FROM s3vl.config 
    ORDER BY updated_at DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            FALSE, 
            NULL::TEXT, 
            NULL::TEXT, 
            'No Lambda configuration found'::TEXT, 
            NULL::INTEGER;
        RETURN;
    END IF;
    
    -- Prepare minimal test payload for availability check
    test_payload := '{"operation": "availability_check"}';
    
    -- Record start time
    start_time := clock_timestamp();
    
    BEGIN
        -- Invoke Lambda function
        SELECT payload INTO lambda_response
        FROM aws_lambda.invoke(
            config_record.lambda_arn,
            test_payload::jsonb
        );
        
        -- Calculate response time
        end_time := clock_timestamp();
        response_time := extract(milliseconds from (end_time - start_time))::INTEGER;
        
        -- Check for null response
        IF lambda_response IS NULL THEN
            RETURN QUERY SELECT 
                FALSE, 
                config_record.lambda_arn, 
                config_record.aws_region, 
                'Lambda returned null response'::TEXT, 
                response_time;
            RETURN;
        END IF;
        
        -- Parse JSON response
        BEGIN
            response_json := lambda_response::JSON;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT 
                FALSE, 
                config_record.lambda_arn, 
                config_record.aws_region, 
                'Invalid JSON response'::TEXT, 
                response_time;
            RETURN;
        END;
        
        -- Check for success field
        success_value := json_extract_path_text(response_json, 'success');
        
        IF success_value IS NULL THEN
            RETURN QUERY SELECT 
                FALSE, 
                config_record.lambda_arn, 
                config_record.aws_region, 
                'Missing success field in response'::TEXT, 
                response_time;
            RETURN;
        END IF;
        
        -- Check success value
        IF success_value::BOOLEAN = TRUE THEN
            RETURN QUERY SELECT 
                TRUE, 
                config_record.lambda_arn, 
                config_record.aws_region, 
                NULL::TEXT, 
                response_time;
        ELSE
            -- Return error from Lambda response
            RETURN QUERY SELECT 
                FALSE, 
                config_record.lambda_arn, 
                config_record.aws_region, 
                COALESCE(json_extract_path_text(response_json, 'error'), 'Lambda returned success=false')::TEXT, 
                response_time;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        end_time := clock_timestamp();
        response_time := extract(milliseconds from (end_time - start_time))::INTEGER;
        
        RETURN QUERY SELECT 
            FALSE, 
            config_record.lambda_arn, 
            config_record.aws_region, 
            SQLERRM::TEXT, 
            response_time;
    END;
END;
$$;

-- Enhanced function to get current Lambda configuration with validation status
CREATE OR REPLACE FUNCTION s3vl.get_config()
RETURNS TABLE(
    lambda_arn TEXT,
    aws_region TEXT,
    timeout_seconds INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    config_age_hours NUMERIC,
    last_validation_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    validation_result RECORD;
BEGIN
    -- Return configuration with enhanced metadata
    FOR lambda_arn, aws_region, timeout_seconds, created_at, updated_at IN
        SELECT 
            c.lambda_arn,
            c.aws_region,
            c.timeout_seconds,
            c.created_at,
            c.updated_at
        FROM s3vl.config c
        ORDER BY c.updated_at DESC
        LIMIT 1
    LOOP
        -- Calculate configuration age
        config_age_hours := extract(hours from (now() - updated_at));
        
        -- Get last validation status (quick check)
        BEGIN
            SELECT error_message INTO validation_result 
            FROM s3vl.validate_config() 
            LIMIT 1;
            
            IF validation_result.error_message IS NULL THEN
                last_validation_status := 'HEALTHY';
            ELSE
                last_validation_status := 'ERROR: ' || left(validation_result.error_message, 100);
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            last_validation_status := 'VALIDATION_FAILED: ' || SQLERRM;
        END;
        
        RETURN NEXT;
    END LOOP;
    
    -- If no configuration found, return a helpful message
    IF NOT FOUND THEN
        RAISE NOTICE 'No Lambda configuration found. Use s3vl.configure() to set up the integration.';
        RAISE NOTICE 'Example: SELECT s3vl.configure(''arn:aws:lambda:us-west-2:123456789012:function:my-function'', ''us-west-2'');';
    END IF;
END;
$$;

-- Add helpful comments for the functions
COMMENT ON FUNCTION s3vl.configure(TEXT, TEXT, INTEGER) IS 'Configure Lambda function ARN and settings for S3 Vector integration. Automatically validates configuration after setup.';
COMMENT ON FUNCTION s3vl.validate_config() IS 'Validate Lambda connectivity using lightweight availability_check operation. Returns validation status, configuration details, and response time. Simplified from complex health checking to focus on basic connectivity.';
COMMENT ON FUNCTION s3vl.get_config() IS 'Get current Lambda configuration with validation status and configuration age';
