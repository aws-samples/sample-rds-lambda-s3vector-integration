# Setup with Existing Lambda Role

If your Aurora cluster already has a Lambda role associated, you have two options for exploring this S3 Vector integration example.

## Recommended: Use a Separate Aurora Cluster

The safest approach is to create a separate Aurora PostgreSQL cluster for testing this integration example. This avoids any risk to your existing Lambda integrations.

See the [AWS Aurora PostgreSQL documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.CreateInstance.html) for cluster creation instructions.

**Requirements:**
- Aurora PostgreSQL 13.7+ (for `aws_lambda` extension support)
- No existing Lambda role associations

## Alternative: Update Existing Lambda Role Permissions

If you must use your existing cluster, you'll need to add Lambda invoke permissions for the S3 Vector function to your existing Aurora Lambda role.

**Steps:**
1. Deploy the CloudFormation template normally (the created Aurora role won't be used)
2. Add `lambda:InvokeFunction` permission for the `s3vl-vector-query` function to your existing Aurora Lambda role
3. Continue with the normal setup process

**Note:** This approach assumes you understand IAM role management and the potential impact on existing Lambda integrations.

