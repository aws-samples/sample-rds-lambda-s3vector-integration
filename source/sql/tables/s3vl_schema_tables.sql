-- S3VL Schema and Table Creation
-- Creates the s3vl schema and table structures for S3 Vector Lambda integration
-- Provides organized schema structure for configuration and index registry



-- Configuration table
-- Stores Lambda function ARNs and configuration parameters for the integration
CREATE TABLE IF NOT EXISTS s3vl.config (
    id SERIAL PRIMARY KEY,
    lambda_arn TEXT NOT NULL,
    aws_region TEXT NOT NULL DEFAULT 'us-west-2',
    timeout_seconds INTEGER DEFAULT 30,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_timeout CHECK (timeout_seconds > 0 AND timeout_seconds <= 900)
);

-- Create index for faster lookups on config table
CREATE INDEX IF NOT EXISTS idx_s3vl_config_region ON s3vl.config(aws_region);

-- Index registry table
-- Maps friendly index names to full S3 Vector ARNs for easier usage
CREATE TABLE IF NOT EXISTS s3vl.index_registry (
    id SERIAL PRIMARY KEY,
    index_name TEXT NOT NULL UNIQUE,
    index_arn TEXT NOT NULL,
    description TEXT,
    bucket_name TEXT NOT NULL,
    region TEXT NOT NULL DEFAULT 'us-west-2',
    account_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Constraints (preserved from original table)
    CONSTRAINT valid_index_name CHECK (
        index_name ~ '^[a-zA-Z][a-zA-Z0-9_-]*$' AND 
        length(index_name) >= 2 AND 
        length(index_name) <= 64
    ),
    CONSTRAINT valid_arn_format CHECK (
        index_arn ~ '^arn:aws:s3vectors:[^:]+:[^:]+:bucket/[^/]+/index/[^/]+$'
    ),
    CONSTRAINT valid_bucket_name CHECK (
        bucket_name ~ '^[a-z0-9][a-z0-9.-]*[a-z0-9]$' AND
        length(bucket_name) >= 3 AND
        length(bucket_name) <= 63
    ),
    CONSTRAINT valid_account_id CHECK (
        account_id ~ '^[0-9]{12}$'
    )
);

-- Create indexes for faster lookups on index_registry table
CREATE INDEX IF NOT EXISTS idx_s3vl_index_registry_name ON s3vl.index_registry(index_name) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_s3vl_index_registry_bucket ON s3vl.index_registry(bucket_name) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_s3vl_index_registry_region ON s3vl.index_registry(region) WHERE is_active = TRUE;

-- Create trigger function to update the updated_at timestamp for config table
CREATE OR REPLACE FUNCTION s3vl.update_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for config table
CREATE TRIGGER trigger_update_s3vl_config_timestamp
    BEFORE UPDATE ON s3vl.config
    FOR EACH ROW
    EXECUTE FUNCTION s3vl.update_config_timestamp();

-- Create trigger function to update the updated_at timestamp for index_registry table
CREATE OR REPLACE FUNCTION s3vl.update_index_registry_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for index_registry table
CREATE TRIGGER trigger_update_s3vl_index_registry_timestamp
    BEFORE UPDATE ON s3vl.index_registry
    FOR EACH ROW
    EXECUTE FUNCTION s3vl.update_index_registry_timestamp();

-- Add helpful comments
COMMENT ON SCHEMA s3vl IS 'S3 Vector Lambda integration schema containing all related objects';
COMMENT ON TABLE s3vl.config IS 'Configuration table for Sample RDS Lambda S3Vector Integration';
COMMENT ON COLUMN s3vl.config.lambda_arn IS 'AWS Lambda function ARN for S3 Vector integration';
COMMENT ON COLUMN s3vl.config.aws_region IS 'AWS region where Lambda function is deployed';
COMMENT ON COLUMN s3vl.config.timeout_seconds IS 'Lambda invocation timeout in seconds (1-900)';

COMMENT ON TABLE s3vl.index_registry IS 'Registry mapping friendly index names to S3 Vector ARNs';
COMMENT ON COLUMN s3vl.index_registry.index_name IS 'Friendly name for the index (e.g., "products", "embeddings")';
COMMENT ON COLUMN s3vl.index_registry.index_arn IS 'Full S3 Vector index ARN';
COMMENT ON COLUMN s3vl.index_registry.description IS 'Human-readable description of the index purpose';
COMMENT ON COLUMN s3vl.index_registry.bucket_name IS 'S3 bucket name containing the vector index';
COMMENT ON COLUMN s3vl.index_registry.region IS 'AWS region where the S3 Vector index is located';
COMMENT ON COLUMN s3vl.index_registry.account_id IS 'AWS account ID that owns the S3 Vector index';
COMMENT ON COLUMN s3vl.index_registry.is_active IS 'Whether this index mapping is currently active';