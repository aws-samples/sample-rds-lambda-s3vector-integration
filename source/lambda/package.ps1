# Lambda Deployment Package Creation Script (PowerShell)
# Creates a deployment package for the Sample RDS Lambda S3Vector Integration

$ErrorActionPreference = "Stop"

# Project directories
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BUILD_DIR = Join-Path $SCRIPT_DIR "build"
$ZIP_FILE = Join-Path $BUILD_DIR "sample-rds-lambda-s3vector.zip"

# Check if Compress-Archive is available (PowerShell 5.0+)
try {
    Get-Command Compress-Archive -ErrorAction Stop | Out-Null
} catch {
    Write-Error "Error: Compress-Archive cmdlet is required but not available. Please use PowerShell 5.0 or later."
    exit 1
}

# Clean build directory
if (Test-Path $BUILD_DIR) {
    Remove-Item $BUILD_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null

# Create deployment package with only lambda_function.py
$lambdaFile = Join-Path $SCRIPT_DIR "src\lambda_function.py"
if (Test-Path $lambdaFile) {
    Compress-Archive -Path $lambdaFile -DestinationPath $ZIP_FILE -Force
} else {
    Write-Error "Error: lambda_function.py not found at $lambdaFile"
    exit 1
}

# Output the package location
Write-Host $ZIP_FILE