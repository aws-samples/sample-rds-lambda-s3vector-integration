# Sample RDS Lambda S3Vector Integration - Data Flow Architecture

The architecture shows a 7-step data flow: (1) Database client sends SQL query to Aurora PostgreSQL, (2) s3vl schema functions process the request, (3) aws_lambda extension invokes Lambda function, (4) Lambda calls S3 Vector API, (5) S3 Vector returns results, (6) Lambda formats response, (7) Results returned to client

## Complete Data Flow Diagram

<!-- ASCII diagram showing data flow from Database Client through Aurora PostgreSQL, Lambda, to S3 Vectors Service -->

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                          Sample RDS Lambda S3Vector Integration                │
│                              Data Flow Architecture                            │
└────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    1. SQL Query
│                 │    ──────────────────────────────────────────────────────────┐
│  Database       │                                                              │
│  Client         │    SELECT * FROM s3vl.query_vectors(                         │
│  Application    │        index_name => 'products',                             │
│                 │        query_vector => ARRAY[0.1, 0.2, 0.3],                 │
└─────────────────┘        top_k => 10                                           │
         │                 );                                                    │
         │                                                                       │
         ▼                                                                       │
┌────────────────────────────────────────────────────────────────────────────────┤
│                        Amazon Aurora PostgreSQL Cluster                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                           s3vl Schema                                   │   │
│  │                                                                         │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐      │   │
│  │  │   s3vl.config   │  │  s3vl.indexes   │  │  s3vl Functions     │      │   │
│  │  │                 │  │                 │  │                     │      │   │
│  │  │ • lambda_arn    │  │ • index_name    │  │ • query_vectors()   │      │   │
│  │  │ • aws_region    │  │ • index_arn     │  │ • get_vectors()     │      │   │
│  │  │                 │  │ • description   │  │ • list_vectors()    │      │   │
│  │  └─────────────────┘  └─────────────────┘  │ • validate_config() │      │   │
│  │                                            └─────────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                         │
│                                      │ 2. Function Processing                  │
│                                      │ • Validate parameters                   │
│                                      │ • Lookup index ARN                      │
│                                      │ • Retrieve Lambda ARN                   │
│                                      │ • Construct JSON payload                │
│                                      ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    aws_lambda Extension                                 │   │
│  │                                                                         │   │
│  │  aws_lambda_invoke(                                                     │   │
│  │    lambda_arn,                                                          │   │
│  │    '{"operation": "query_vectors",                                      │   │
│  │      "index_arn": "arn:aws:s3vectors:...",                              │   │
│  │      "query_vector": [0.1, 0.2, 0.3],                                   │   │
│  │      "top_k": 10}'                                                      │   │
│  │  )                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────┘
         │
         │ 3. Lambda Invocation (via IAM Role)
         │ Aurora Lambda Role: rds-s3vl-aurora-lambda-role
         │ Permissions: lambda:InvokeFunction
         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Lambda Function                                │
│                          rds-s3vl-vector-query                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        lambda_handler()                                 │    │
│  │                                                                         │    │
│  │  1. Parse event payload                                                 │    │
│  │  2. Validate operation and parameters                                   │    │
│  │  3. Initialize boto3 S3 Vector client                                   │    │
│  │  4. Call appropriate S3 Vector API                                      │    │
│  │  5. Format response for PostgreSQL                                      │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                          │
│  Execution Role: rds-s3vl-lambda-execution-role                                 │
│  Permissions:                                                                   │
│  • s3vectors:QueryVectors, GetVectors, ListVectors                              │
│  • VPC access (egress TCP 443 for S3 Vectors API)                               │
│  • CloudWatch logging                                                           │
└─────────────────────────────────────────────────────────────────────────────────┘
         │
         │ 4. S3 Vector API Call
         │ boto3.client('s3vectors').query_vectors(...)
         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Amazon S3 Vectors Service                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        Vector Index Storage                             │    │
│  │                                                                         │    │
│  │  Bucket: your-vector-bucket                                             │    │
│  │  Index: test-index-5d                                                   │    │
│  │  • Dimension: 5                                                         │    │
│  │  • Distance Metric: cosine                                              │    │
│  │  • Vector Count: 50 (sample data)                                       │    │
│  │                                                                         │    │
│  │  Operations:                                                            │    │
│  │  • QueryVectors (similarity search)                                     │    │
│  │  • GetVectors (retrieve by ID)                                          │    │
│  │  • ListVectors (browse index)                                           │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                          │
│                                      │ 5. Vector Search Results                 │
│                                      │ {                                        │
│                                      │   "vectors": [                           │
│                                      │     {"id": "vec_001", "score": 0.95},    │
│                                      │     {"id": "vec_002", "score": 0.89}     │
│                                      │   ]                                      │
│                                      │ }                                        │
│                                      ▼                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
         ▲
         │ 6. Response Processing in Lambda
         │ Format S3 Vector response for PostgreSQL:
         │ {
         │   "success": true,
         │   "result": {"vectors": [...]}
         │ }
         ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                        Return Path to Aurora PostgreSQL                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    PostgreSQL Result Processing                         │   │
│  │                                                                         │   │
│  │  1. Parse Lambda JSON response                                          │   │
│  │  2. Extract vector results                                              │   │
│  │  3. Convert to PostgreSQL table format                                  │   │
│  │  4. Return result set to client                                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────┘
         │
         │ 7. Final SQL Result Set
         ▼
┌─────────────────┐    vector_id | similarity_score | metadata
│                 │    ──────────┼──────────────────┼──────────
│  Database       │    vec_001   | 0.95             | {...}
│  Client         │    vec_002   | 0.89             | {...}
│  Application    │    vec_003   | 0.82             | {...}
│                 │
└─────────────────┘

┌────────────────────────────────────────────────────────────────────────────────┐
│                              Security Architecture                             │
│                                                                                │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐     │
│  │   Aurora IAM    │    │   Lambda IAM    │    │      VPC Security       │     │
│  │      Role       │    │      Role       │    │                         │     │
│  │                 │    │                 │    │  • Same VPC deployment  │     │
│  │ • Lambda invoke │    │ • S3 Vector API │    │  • Dedicated Lambda SG  │     │
│  │   permissions   │    │ • CloudWatch    │    │    (egress 443 only)    │     │
│  │                 │    │   logging       │    │  • Private subnets      │     │
│  │                 │    │                 │    │  • NAT Gateway access   │     │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Key Integration Points

### 1. SQL Interface Layer
- **s3vl Schema**: Dedicated PostgreSQL schema for vector functions and configuration tables
- **Configuration Management**: Stores Lambda ARN and index registry
- **Function Mapping**: SQL functions mirror S3 Vector API operations

### 2. Lambda Translation Layer  
- **Event Processing**: Converts PostgreSQL requests to S3 Vector API calls
- **Authentication**: Uses IAM roles for secure service-to-service communication
- **Response Formatting**: Transforms S3 Vector responses for PostgreSQL consumption

### 3. Security Boundaries
- **Role Separation**: Distinct IAM roles for Aurora (invoke Lambda) and Lambda (call S3 Vector)
- **Network Isolation**: Lambda runs in a dedicated security group allowing only outbound HTTPS (port 443) for S3 Vectors API access. No inbound rules — Aurora invokes Lambda via the AWS service API, not over the VPC network.
- **Least Privilege**: Each component has minimal required permissions at both the IAM and network layers

### 4. Data Flow Characteristics
- **Synchronous**: SQL queries wait for complete S3 Vector results
- **Stateless**: No persistent connections between Aurora and S3 Vector
- **Scalable**: Lambda handles concurrent requests from multiple Aurora connections

This architecture demonstrates how to bridge Aurora PostgreSQL's relational capabilities with S3 Vector's specialized vector storage using AWS Lambda as a secure, scalable translation layer.