# Sample Amazon Aurora Postgres Lambda S3 Vectors Integration

## Overview

This sample demonstrates how to integrate Amazon Aurora PostgreSQL databases with Amazon S3 Vectorsindexes through AWS Lambda functions. The integration provides PostgreSQL functions that use AWS Lambda to call S3 Vectors service APIs, allowing you to perform vector similarity searches, retrieve vectors by ID, and list vectors directly from your Aurora PostgreSQL database using familiar SQL syntax.

**Important: This application uses various AWS services and there are costs associated with these services after the Free Tier usage - please see the [AWS Pricing page](https://aws.amazon.com/pricing/) for details. You are responsible for any AWS costs incurred. No warranty is implied in this sample.**

This sample integration is useful for:
- Learning how to combine Aurora's relational capabilities with Amazon S3 Vector's specialized vector storage
- Prototyping applications that need both relational and vector data
- Building upon this foundation for your specific use cases

### Architecture

The sample solution consists of:

- **PostgreSQL Functions**: SQL functions in the `s3vl` schema that invoke AWS Lambda using `aws_lambda_invoke`
- **AWS Lambda Function**: Python-based function that integrates Aurora PostgreSQL requests with S3 Vectors service API calls
- **Amazon CloudFormation Infrastructure**: Automated deployment of S3 Vectors bucket/index, IAM roles, policies, and Lambda function
- **S3 Vectors Service Integration**: Direct integration with S3 Vectors indexes for similarity search and vector operations
- **IAM Roles**: Minimal permissions for Lambda invocation from Aurora and S3 Vectors service access from Lambda


### How It Works

1. **SQL Function Invocation**: User calls PostgreSQL functions in the `s3vl` schema (e.g., `s3vl.query_vectors()`)
2. **Lambda Invocation**: PostgreSQL functions use `aws_lambda_invoke` to call the Lambda function with operation parameters
3. **S3 Vectors API Call**: Lambda function translates the request and calls the appropriate S3 Vectors service API (QueryVectors, GetVectors, or ListVectors)
4. **Response Processing**: Lambda function processes the S3 Vectors API response and returns structured JSON to PostgreSQL
5. **Result Formatting**: PostgreSQL function parses the JSON response and returns results as SQL table rows

## Project Structure

```
├── deployment/                     # Infrastructure deployment
│   └── cloudformation/
│       ├── template.yaml           # Main CloudFormation template
│       ├── parameters-example.json # Example parameters file
│       └── README.md               # Deployment instructions
├── source/                         # Source code
│   ├── lambda/                     # Lambda function code
│   │   ├── src/                    # Lambda source code
│   │   ├── tests/                  # Lambda tests
│   │   ├── requirements.txt        # Python dependencies
│   │   └── package.sh              # Packaging script
│   └── sql/                        # PostgreSQL extension
│       ├── functions/              # SQL function definitions
│       ├── tables/                 # Configuration tables
│       ├── types/                  # Custom data types
│       ├── examples/               # Usage examples
│       └── install.sql             # Extension installer
├── sample-data/                    # Sample data generator
│   ├── generate-vectors.py         # Vector data generator
│   └── sample-vectors.json         # Sample vector data
└── docs/                           # Documentation
    ├── ARCHITECTURE.md             # Architecture overview
    └── TROUBLESHOOTING.md          # Troubleshooting guide
```

## Setup

**Expected setup time: 30 minutes**

### Prerequisites

**⚠️ IMPORTANT**: This sample is designed for learning and testing. Use a dedicated test or development Aurora cluster, not a production environment.

**🔒 Security Note**: This sample demonstrates integration patterns but requires additional hardening for production use: (1) Enable Amazon Virtual Private Cloud (Amazon VPC) Flow Logs for network monitoring, (2) Implement AWS WAF if exposed via API Gateway, (3) Use AWS Secrets Manager for configuration, (4) Enable AWS GuardDuty for threat detection, (5) Implement automated security scanning in CI/CD pipeline, (6) Conduct security review of IAM policies before production deployment.

- **Aurora PostgreSQL Cluster**: Aurora PostgreSQL 13.7+ with `aws_lambda` extension support (test/development environment only)
- **No Existing Lambda Role**: Aurora cluster should not have an existing Lambda role associated (Aurora supports only one Lambda role per cluster)
- **AWS CLI**: Configured with appropriate permissions
- **VPC Configuration**: Aurora cluster deployed in VPC with proper networking (note: an account's default VPC does not have Lambda integration enabled by default - see [Aurora PostgreSQL Lambda integration documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/PostgreSQL-Lambda.html))

**Note**: If your Aurora cluster already has a Lambda role associated, see [docs/existing-lambda-role-setup.md](docs/existing-lambda-role-setup.md) for alternative setup options.

### 1. Deploying Infrastructure with CloudFormation

The CloudFormation template creates all necessary AWS resources including the S3 Vectors bucket, index, Lambda function, and IAM roles. You can deploy using either the AWS CLI or AWS Console.

#### Option A: Deploying using AWS CLI

```bash
# Navigate to CloudFormation directory
cd deployment/cloudformation

# Create parameters file from example
cp parameters-example.json parameters.json

# Edit parameters.json with your Aurora cluster details:
# - AuroraClusterArn: Full Amazon Resource Name (ARN) of your Aurora cluster (find in RDS Console > Configuration tab)
# - VpcId: VPC ID where Aurora cluster is deployed (find in RDS Console > Connectivity & security tab)
# - SubnetIds: Comma-separated subnet IDs used by Aurora cluster (find in RDS Console > Subnet groups)
# - SecurityGroupIds: Comma-separated security group IDs for Aurora cluster (find in RDS Console > VPC security groups)
# - ResourcePrefix: Prefix for naming resources (default: s3vl)
# - LambdaTimeout: Lambda timeout in seconds (default: 10 for demonstration)
# - LambdaMemorySize: Lambda memory in MB (default: 128 for demonstration)

# Alternatively, use the sample file with detailed comments:
# cp parameters-example.json parameters.json

# Deploy the stack
aws cloudformation create-stack \
    --stack-name sample-rds-lambda-s3vector-integration \
    --template-body file://template.yaml \
    --parameters file://parameters.json \
    --capabilities CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].StackStatus'
```

#### Option B: Deploying using AWS Console

1. **Navigate to CloudFormation Console**:
   - Open the [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation/)
   - Choose "Create stack" → "With new resources (standard)"

2. **Upload Template**:
   - Select "Upload a template file"
   - Choose `deployment/cloudformation/template.yaml` from this project
   - Choose "Next"

3. **Configure Stack Parameters**:
   - **Stack name**: `sample-rds-lambda-s3vector-integration`
   - **AuroraClusterArn**: Full ARN of your Aurora cluster (find in RDS Console → Databases → Configuration tab)
   - **VpcId**: VPC ID where Aurora cluster is deployed (find in RDS Console → Connectivity & security tab)
   - **SubnetIds**: Select 2-3 subnets used by Aurora cluster (same AZs as Aurora)
   - **SecurityGroupIds**: Select security groups used by Aurora cluster
   - **ResourcePrefix**: Leave as `s3vl` or customize (1-20 chars, lowercase, numbers, hyphens)
   - **LambdaTimeout**: Leave as `10` seconds for demonstration
   - **LambdaMemorySize**: Leave as `128` MB for demonstration
   - Choose "Next"

4. **Configure Stack Options**:
   - Add tags if desired (optional)
   - Leave other settings as default
   - Choose "Next"

5. **Review and Deploy**:
   - Review all parameters
   - Check "I acknowledge that AWS CloudFormation might create IAM resources with custom names"
   - Choose "Submit"

6. **Monitor Deployment**:
   - Watch the "Events" tab for deployment progress
   - Wait for stack status to show "CREATE_COMPLETE" (typically 2-5 minutes)

### 2. Associating Aurora Cluster with Lambda Role

After CloudFormation deployment completes, associate the Aurora cluster with the Lambda execution role. You can do this using either the AWS Command Line Interface (AWS CLI) or AWS Console.

**Note**: If your Aurora cluster already has a Lambda role associated, this step will fail. See [docs/existing-lambda-role-setup.md](docs/existing-lambda-role-setup.md) for guidance on handling existing Lambda roles.

#### Option A: Using AWS CLI

```bash
# Get the command from CloudFormation outputs
aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`AuroraRoleAttachmentCommand`].OutputValue' \
    --output text

# Execute the returned command (sample):
aws rds add-role-to-db-cluster \
    --db-cluster-identifier your-cluster-name \
    --role-arn arn:aws:iam::123456789012:role/s3vl-aurora-lambda-role \
    --feature-name Lambda \
    --region us-west-2
```

#### Option B: Using AWS Console

1. **Get Role ARN from CloudFormation**:
   - Go to CloudFormation Console → Stacks → `sample-rds-lambda-s3vector-integration`
   - Choose "Outputs" tab
   - Copy the `AuroraLambdaRoleArn` value

2. **Associate Role with Aurora Cluster**:
   - Go to [RDS Console](https://console.aws.amazon.com/rds/)
   - Choose "Databases" → Select your Aurora cluster
   - Choose "Modify"
   - Scroll to "Additional configuration" → "Associated roles"
   - Choose "Add role"
   - **Role ARN**: Paste the ARN from step 1
   - **Feature**: Select "Lambda"
   - Choose "Continue" → "Modify cluster"

3. **Wait for Modification**:
   - Monitor the cluster status until modification completes
   - This typically takes 1-2 minutes

### 3. Updating Lambda Function Code

The CloudFormation template deploys a placeholder Lambda function. Update it with the actual implementation using either the AWS CLI or AWS Console.

#### Option A: Using AWS CLI

```bash
# Package the Lambda function
cd source/lambda
./package.sh

# Update the Lambda function with the packaged code
aws lambda update-function-code \
    --function-name s3vl-vector-query \
    --zip-file fileb://lambda-deployment-package.zip

# Verify the update
aws lambda get-function --function-name s3vl-vector-query \
    --query 'Configuration.[FunctionName,LastModified,CodeSize]'
```

#### Option B: Using AWS Console

1. **Package the Lambda Function**:
   ```bash
   cd source/lambda
   ./package.sh
   ```

2. **Upload via Lambda Console**:
   - Go to [Lambda Console](https://console.aws.amazon.com/lambda/)
   - Choose "Functions" → Find and Choose `s3vl-vector-query`
   - In the "Code" tab, Choose "Upload from" → ".zip file"
   - Select `lambda-deployment-package.zip` from the source/lambda directory
   - Choose "Save"

3. **Verify Upload**:
   - Check that "Last modified" timestamp updated
   - Verify the code size increased from the placeholder (~1KB to ~10KB+)

### 4. Installing PostgreSQL Extension

Connect to your Aurora PostgreSQL database and install the extension:

```sql
-- Connect to your Aurora PostgreSQL database
-- psql -h your-cluster.cluster-xyz.region.rds.amazonaws.com -U postgres -d your_database

-- Install the s3vl extension
\i source/sql/install.sql
```

### 5. Configuring Lambda Integration

Configure the PostgreSQL extension to use your deployed Lambda function:

```sql
-- Configure Lambda function ARN (get from CloudFormation outputs)
SELECT s3vl.configure(
    'arn:aws:lambda:us-west-2:123456789012:function:s3vl-vector-query', 
    'us-west-2'
);

-- Test the connection
SELECT * FROM s3vl.validate_config();
```

### 6. Register S3 Vectors Index

Register the S3 Vectors index created by CloudFormation for easy reference:

```sql
-- Register the index with a friendly name (get the index ARN from CloudFormation outputs)
SELECT s3vl.register_index(
    'demo-index',
    'arn:aws:s3vectors:us-west-2:123456789012:bucket/amzn-s3-demo-s3vectorbucket-xyz/index/s3vl-index-5d'
);

-- Verify registration
SELECT * FROM s3vl.list_indexes();
```

### 7. Populate S3 Vectors Index with Sample Data

Use the provided sample data generator to populate your index. **Note**: S3 Vectors operations are only available through AWS CLI and APIs - there is no console UI for vector management.

#### Generate Sample Data

```bash
# Generate sample vectors (5 dimensions)
cd sample-data
python3 generate-vectors.py --count 100 --output sample-vectors.json
```

#### Upload Vectors using AWS CLI

```bash
# Get the index ARN from CloudFormation outputs
INDEX_ARN=$(aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`S3VectorIndexArn`].OutputValue' \
    --output text)

echo "Using S3 Vectors Index ARN: $INDEX_ARN"

# Upload vectors to S3 Vectors index
aws s3vectors put-vectors \
    --index-arn "$INDEX_ARN" \
    --vectors file://sample-vectors.json

# Verify upload
aws s3vectors list-vectors \
    --index-arn "$INDEX_ARN" \
    --max-results 5

# Check index statistics
aws s3vectors get-index \
    --index-arn "$INDEX_ARN" \
    --query 'Index.[IndexName,VectorCount,Dimension,DistanceMetric]'
```

## What You'll Learn

This sample demonstrates:
- How to integrate PostgreSQL with AWS services using Lambda functions
- AWS API alignment patterns in database extensions
- CloudFormation automation for multi-service deployments
- PostgreSQL extension development with external service integration

## Core Functions

The integration provides AWS API aligned functions in the `s3vl` schema:

- **s3vl.query_vectors()** - Similarity search (matches AWS QueryVectors API)
- **s3vl.get_vectors()** - Retrieve vectors by ID (matches AWS GetVectors API)  
- **s3vl.list_vectors()** - List vectors in index (matches AWS ListVectors API)
- **s3vl.configure()** - Configure Lambda integration
- **s3vl.validate_config()** - Validate configuration and connectivity

## SQL Examples

Once setup is complete, you can use the S3 Vectors integration with familiar SQL syntax:

### Vector Similarity Search

```sql
-- Perform similarity search using registered index name
SELECT 
    vector_id,
    similarity_score,
    distance,
    metadata
FROM s3vl.query_vectors(
    query_vector => ARRAY[0.1, 0.2, 0.3, 0.4, 0.5],
    index_name => 'demo-index',
    top_k => 10,
    return_metadata => TRUE
);

-- Search with metadata filtering
SELECT 
    vector_id,
    similarity_score,
    metadata
FROM s3vl.query_vectors(
    query_vector => ARRAY[0.1, 0.2, 0.3, 0.4, 0.5],
    index_name => 'demo-index',
    top_k => 5,
    return_metadata => TRUE,
    metadata_filter => '{"category": "test"}'::jsonb
);
```

### Retrieve Specific Vectors

```sql
-- Get vectors by ID
SELECT 
    vector_id,
    embedding,
    metadata,
    found
FROM s3vl.get_vectors(
    vector_ids => ARRAY['vec_001', 'vec_002', 'vec_003'],
    index_name => 'demo-index',
    include_vector_data => TRUE,
    include_metadata => TRUE
);
```

### List Vectors in Index

```sql
-- List vectors with pagination
SELECT 
    vector_id,
    metadata,
    response_next_token,
    total_count
FROM s3vl.list_vectors(
    index_name => 'demo-index',
    max_results => 20,
    return_metadata => TRUE
);
```

### Join Vector Results with Relational Data

```sql
-- Sample: Join vector similarity results with product catalog
WITH similar_products AS (
    SELECT 
        vector_id,
        similarity_score,
        (metadata->>'id')::INTEGER as product_id
    FROM s3vl.query_vectors(
        query_vector => ARRAY[0.1, 0.2, 0.3, 0.4, 0.5],
        index_name => 'demo-index',
        top_k => 10
    )
)
SELECT 
    p.product_name,
    p.price,
    sp.similarity_score,
    sp.vector_id
FROM similar_products sp
JOIN products p ON p.id = sp.product_id
ORDER BY sp.similarity_score DESC;
```

### Configuration and Management

```sql
-- Check current configuration
SELECT * FROM s3vl.get_config();

-- Validate Lambda connectivity
SELECT * FROM s3vl.validate_config();

-- List registered indexes
SELECT * FROM s3vl.list_indexes();

-- Get index details
SELECT * FROM s3vl.get_index_info('demo-index');
```

## Cleanup

**Expected cleanup time: 10-15 minutes**

When you're finished exploring this sample integration, follow these steps to remove all created resources and avoid ongoing AWS charges.

### 1. Remove PostgreSQL Schema and Extension

Connect to your Aurora PostgreSQL database and remove the `s3vl` schema:

```sql
-- Connect to your Aurora PostgreSQL database
-- psql -h your-cluster.cluster-xyz.region.rds.amazonaws.com -U postgres -d your_database

-- Drop the s3vl schema and all its objects
DROP SCHEMA IF EXISTS s3vl CASCADE;

-- Verify schema removal
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 's3vl';
-- Should return no rows

-- Optional: Remove aws_lambda extension if not used elsewhere
-- DROP EXTENSION IF EXISTS aws_lambda CASCADE;
```

**Note**: The `CASCADE` option will remove all functions, tables, and other objects in the `s3vl` schema. This action cannot be undone.

### 2. Remove Aurora Cluster IAM Role Association

**⚠️ IMPORTANT**: Only perform this step if you used the CloudFormation template to create the Aurora Lambda role (`s3vl-aurora-lambda-role`). If your Aurora cluster has an existing Lambda role that was created outside of this sample, skip this step and proceed to CloudFormation deletion.

Remove the Lambda execution role created by this sample from your Aurora cluster:

#### Option A: Using AWS CLI

```bash
# Get the role ARN from CloudFormation outputs
ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`AuroraLambdaRoleArn`].OutputValue' \
    --output text)

# Get cluster identifier from CloudFormation outputs
CLUSTER_ID=$(aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`AuroraClusterIdentifier`].OutputValue' \
    --output text)

# Verify this is the role created by our CloudFormation template
echo "Role to be removed: $ROLE_ARN"
echo "Cluster: $CLUSTER_ID"
echo "Proceed only if the role name contains 's3vl-aurora-lambda-role'"

# Remove role from Aurora cluster (only if it's our role)
aws rds remove-role-from-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --role-arn "$ROLE_ARN" \
    --feature-name Lambda

# Verify removal
aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0].AssociatedRoles'
```

#### Option B: Using AWS Console

1. Go to [RDS Console](https://console.aws.amazon.com/rds/)
2. Choose "Databases" → Select your Aurora cluster
3. Choose "Modify"
4. Scroll to "Additional configuration" → "Associated roles"
5. **Verify the role name contains `s3vl-aurora-lambda-role`** before proceeding
6. Find the `s3vl-aurora-lambda-role` and Choose "Remove"
7. Choose "Continue" → "Modify cluster"

**Note**: If you see a different Lambda role or are unsure, do not remove it. Skip to step 3 and let CloudFormation handle the cleanup.

### 3. Delete CloudFormation Stack

This removes all AWS resources created by the CloudFormation template.

#### Option A: Using AWS CLI

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name sample-rds-lambda-s3vector-integration

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration \
    --query 'Stacks[0].StackStatus'

# Wait for deletion to complete (typically 2-5 minutes)
aws cloudformation wait stack-delete-complete \
    --stack-name sample-rds-lambda-s3vector-integration

echo "Stack deletion completed"
```

#### Option B: Using AWS Console

1. Go to [CloudFormation Console](https://console.aws.amazon.com/cloudformation/)
2. Find and select the `sample-rds-lambda-s3vector-integration` stack
3. Choose "Delete"
4. Confirm deletion by Choosing "Delete stack"
5. Monitor the "Events" tab until status shows "DELETE_COMPLETE"

### 4. Verify Resource Cleanup

After cleanup, verify that all resources have been removed:

```bash
# Verify CloudFormation stack is deleted
aws cloudformation describe-stacks \
    --stack-name sample-rds-lambda-s3vector-integration 2>/dev/null || echo "Stack successfully deleted"

# Verify Lambda function is deleted
aws lambda get-function \
    --function-name s3vl-vector-query 2>/dev/null || echo "Lambda function successfully deleted"

# Verify S3 Vectors resources are deleted (these should return empty or not found)
aws s3vectors list-vector-indexes --region us-west-2 --query 'VectorIndexes[?contains(IndexName, `s3vl`)]'
```

### Resources Removed by Cleanup

The cleanup process removes:

- **PostgreSQL Objects**: All functions, tables, and types in the `s3vl` schema
- **S3 Vectors Resources**: Vector bucket and index with all stored vectors
- **Lambda Function**: The vector query Lambda function and its code
- **IAM Roles**: Lambda execution role and Aurora Lambda role with their policies
- **CloudWatch Logs**: Lambda function log groups and log streams
- **Lambda VPC Configuration**: The Lambda function's VPC association (the actual VPC, subnets, and security groups remain unchanged)

**Note**: Your Aurora PostgreSQL cluster remains unchanged and will continue to incur its normal charges.

## Production Considerations

This sample integration is designed for learning and prototyping. For production deployments, consider:

- Reviewing AWS documentation for Aurora PostgreSQL and S3 Vectors best practices
- Implementing appropriate security, monitoring, and scaling strategies for your use case
- Engaging AWS Professional Services or certified partners for production architecture guidance
- Testing thoroughly in non-production environments before deployment

### Security Best Practices

- **Encryption**: Enable encryption-in-transit for all connections (Aurora to Lambda uses TLS automatically, Lambda to S3 Vectors API uses HTTPS)
- **Network Isolation**: Consider AWS PrivateLink for S3 Vectors API access to keep traffic within AWS network
- **Monitoring**: Enable CloudWatch alarms for Lambda errors, Aurora connection failures, and unusual API call patterns
- **IAM**: Review and minimize IAM permissions regularly. Use IAM Access Analyzer to validate policies
- **Rate Limiting**: Implement application-level rate limiting to prevent abuse
- **Secrets Management**: Use AWS Secrets Manager for any sensitive configuration values
- **Audit Logging**: Enable AWS CloudTrail for all API calls and review regularly

For comprehensive production guidance, see the official AWS documentation for [Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/) and [Amazon S3 Vectors](https://docs.aws.amazon.com/s3vectors/).


## Support

For deployment issues, check:
1. CloudFormation stack events for deployment errors
2. Lambda function logs in CloudWatch
3. Aurora PostgreSQL logs for extension issues
4. IAM role trust relationships and policies
5. S3vl schema objects and permissions