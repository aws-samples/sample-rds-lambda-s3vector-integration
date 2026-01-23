# Troubleshooting Guide

This guide helps you resolve common issues when working with this sample RDS Lambda S3Vector integration.

## Quick Health Check

Start with these basic commands to check if everything is working:

```sql
-- Check if the extension is configured
SELECT * FROM s3vl.validate_config();

-- Test a simple vector query
SELECT * FROM s3vl.query_vectors(
    'your-index-name',
    ARRAY[0.1, 0.2, 0.3]::FLOAT8[],
    5
);
```

## Common Issues

### 1. "No Lambda configuration found"

**Problem**: You see this error when trying to use vector functions.

**Solution**: Configure the Lambda function ARN first:
```sql
-- Get the Lambda ARN from your CloudFormation stack outputs
SELECT s3vl.configure(
    'arn:aws:lambda:us-west-2:123456789012:function:your-function-name',
    'us-west-2'
);
```

### 2. "Lambda function returned null response"

**Problem**: The Lambda function isn't responding.

**Check these**:
1. Lambda function exists and is deployed
2. Aurora cluster has the Lambda integration role attached
3. IAM permissions are correct

**Quick fix**:
```bash
# Verify Lambda function exists
aws lambda get-function --function-name your-function-name

# Check Aurora cluster roles
aws rds describe-db-clusters --db-cluster-identifier your-cluster
```

### 3. "Index not found" errors

**Problem**: S3 Vector index doesn't exist or ARN is wrong.

**Solution**:
```bash
# List available indexes
aws s3vectors list-vector-indexes --bucket-name your-bucket

# Use the correct index ARN in your queries
```

### 4. Vector dimension mismatch

**Problem**: Your query vector has wrong number of dimensions.

**Solution**: Check your index dimensions and match them:
```bash
# Check index configuration
aws s3vectors describe-vector-index --index-arn "your-index-arn"
```

### 5. Slow responses or timeouts

**Problem**: Lambda takes too long to respond.

**Quick fixes**:
- Increase Lambda memory (improves performance)
- Increase timeout in configuration:
```sql
SELECT s3vl.configure('your-lambda-arn', 'us-west-2', 60); -- 60 second timeout
```

## CloudFormation Deployment Issues

### Stack creation fails

**Check**:
1. You have proper IAM permissions to create resources
2. Aurora cluster name is correct in parameters
3. VPC and subnet configurations are valid

**Debug**:
```bash
# Check stack events for specific error messages
aws cloudformation describe-stack-events --stack-name your-stack-name
```

## Getting Help

### Collect this information when asking for help:

```sql
-- Current configuration
SELECT * FROM s3vl.get_config();

-- Validation results
SELECT * FROM s3vl.validate_config();
```

```bash
# Lambda function logs
aws logs tail /aws/lambda/your-function-name --follow

# CloudFormation stack status
aws cloudformation describe-stacks --stack-name your-stack-name
```

### Useful AWS Documentation:
- [Aurora Lambda Integration](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Integrating.Lambda.html)
- [S3 Vector Service](https://docs.aws.amazon.com/s3/latest/userguide/s3-vector-search.html)

Remember: This is a sample integration for learning purposes. For production use, consider additional monitoring, error handling, and performance optimization.