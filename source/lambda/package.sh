#!/bin/bash

# Lambda Deployment Package Creation Script
# Creates a deployment package for the Sample RDS Lambda S3Vector Integration

set -e

# Project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ZIP_FILE="$BUILD_DIR/sample-rds-lambda-s3vector.zip"

# Check zip utility
if ! command -v zip &> /dev/null; then
    echo "Error: zip utility is required but not installed"
    exit 1
fi

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create deployment package with only lambda_function.py
LAMBDA_FILE="$SCRIPT_DIR/src/lambda_function.py"
if [ -f "$LAMBDA_FILE" ]; then
    cd "$SCRIPT_DIR/src"
    zip -q "$ZIP_FILE" lambda_function.py
else
    echo "Error: lambda_function.py not found at $LAMBDA_FILE"
    exit 1
fi

# Output the package location
echo "$ZIP_FILE"