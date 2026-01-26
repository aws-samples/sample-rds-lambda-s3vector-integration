"""
Sample RDS Lambda S3Vector Integration
Lambda function for Aurora PostgreSQL to S3 Vector integration using real AWS S3 Vector service
"""

import json
import logging
import time
import boto3
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def validate_s3vector_index_arn(index_arn: Any, parameter_name: str = "index_arn") -> str:
    """
    Validate S3 Vector index ARN format and return sanitized ARN
    
    Args:
        index_arn: The ARN to validate
        parameter_name: Name of the parameter for error messages
    
    Returns:
        str: Validated and sanitized ARN
    
    Raises:
        ValueError: If ARN is invalid
    """
    if not index_arn:
        raise ValueError(f"Missing required parameter: {parameter_name}")
    
    if not isinstance(index_arn, str):
        raise ValueError(f"{parameter_name} must be a string, got {type(index_arn).__name__}")
    
    # Strip whitespace and validate non-empty
    index_arn = index_arn.strip()
    if not index_arn:
        raise ValueError(f"{parameter_name} cannot be empty or whitespace")
    
    # Basic ARN format validation
    if not index_arn.startswith('arn:aws:s3vectors:'):
        raise ValueError(f"{parameter_name} must be a valid S3 Vector index ARN starting with 'arn:aws:s3vectors:'")
    
    # Basic ARN structure validation (arn:partition:service:region:account:resource)
    arn_parts = index_arn.split(':')
    if len(arn_parts) < 6:
        raise ValueError(f"{parameter_name} has invalid ARN format - insufficient parts")
    
    # Validate reasonable ARN length
    if len(index_arn) > 2048:  # AWS ARN length limit
        raise ValueError(f"{parameter_name} exceeds maximum ARN length of 2048 characters")
    
    return index_arn


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Sample-RDS-S3Vector integration operations
    
    Supports AWS API aligned operations:
    - availability_check: Basic connectivity test for Lambda validation
    - query_vectors: Query vectors using S3 Vector QueryVectors API
    - get_vectors: Get vectors by ID using S3 Vector GetVectors API
    - list_vectors: List vectors using S3 Vector ListVectors API
    """
    start_time = time.time()
    request_id = context.aws_request_id if context else 'unknown'
    
    try:
        logger.info(f"Request {request_id}: Processing {event.get('operation', 'unknown')} operation")
        
        # Validate event structure
        if not isinstance(event, dict) or 'operation' not in event:
            raise ValueError("Event must contain 'operation' field")
        
        operation = event['operation']
        
        if operation == 'availability_check':
            result = handle_availability_check(event, request_id)
        elif operation == 'query_vectors':
            result = handle_query_vectors(event, request_id)
        elif operation == 'get_vectors':
            result = handle_get_vectors(event, request_id)
        elif operation == 'list_vectors':
            result = handle_list_vectors(event, request_id)
        else:
            raise ValueError(f"Unsupported operation: {operation}")
        
        execution_time_ms = int((time.time() - start_time) * 1000)
        
        return {
            'success': True,
            'result': result,
            'execution_time_ms': execution_time_ms,
            'request_id': request_id
        }
        
    except Exception as e:
        logger.warning(f"Request {request_id}: Error: {str(e)}", exc_info=True)
        execution_time_ms = int((time.time() - start_time) * 1000)
        
        return {
            'success': False,
            'error': {
                'message': str(e),
                'type': type(e).__name__
            },
            'execution_time_ms': execution_time_ms,
            'request_id': request_id
        }


def handle_availability_check(event: Dict[str, Any], request_id: str) -> Dict[str, Any]:
    """
    Handle availability check operation for Lambda validation
    
    This is a lightweight operation used by s3vl.validate_config() to verify
    that PostgreSQL can successfully invoke the Lambda function. It requires
    no parameters and returns immediately with a success response.
    
    This operation is used instead of complex health checks to simplify
    validation and reduce execution time.
    """
    # Validate that event is a dictionary (basic validation)
    if not isinstance(event, dict):
        raise ValueError("Event must be a dictionary")
    
    # No additional parameters required for availability check
    # This is intentionally lightweight for validation purposes
    
    logger.info(f"Request {request_id}: Availability check - Lambda is reachable")
    return {'status': 'available'}


def handle_query_vectors(event: Dict[str, Any], request_id: str) -> List[Dict[str, Any]]:
    """
    Handle query vectors using S3 Vector QueryVectors API (AWS API aligned)
    
    Required event fields:
    - index_arn: Full ARN of the S3 Vector index
    - query_vector: List of floats for the query vector
    - top_k: Maximum number of results (optional, default 10)
    - return_metadata: Whether to return metadata (optional, default True)
    - metadata_filter: Optional JSONB filter for metadata filtering (optional, default None)
    
    This function uses AWS API parameter names and is called by s3vl.query_vectors()
    """
    # Extract and validate parameters with AWS API names
    index_arn = event.get('index_arn')
    query_vector = event.get('query_vector')
    top_k = event.get('top_k', 10)
    return_metadata = event.get('return_metadata', True)
    metadata_filter = event.get('metadata_filter')  # New optional parameter
    
    # Validate index_arn
    index_arn = validate_s3vector_index_arn(index_arn)
    
    # Validate query_vector
    if not query_vector:
        raise ValueError("Missing required parameter: query_vector")
    
    if not isinstance(query_vector, list):
        raise ValueError("query_vector must be a list of numbers")
    
    if len(query_vector) == 0:
        raise ValueError("query_vector cannot be empty")
    
    if len(query_vector) > 10000:  # Reasonable upper limit for vector dimensions
        raise ValueError("query_vector dimensions cannot exceed 10000")
    
    # Validate all vector elements are numeric and finite
    for i, value in enumerate(query_vector):
        if not isinstance(value, (int, float)):
            raise ValueError(f"query_vector[{i}] must be a number, got {type(value).__name__}")
        
        # Check for NaN and infinite values
        if isinstance(value, float):
            import math
            if math.isnan(value):
                raise ValueError(f"query_vector[{i}] cannot be NaN")
            if math.isinf(value):
                raise ValueError(f"query_vector[{i}] cannot be infinite")
    
    # Validate top_k
    if not isinstance(top_k, int):
        raise ValueError("top_k must be an integer")
    
    if top_k < 1:
        raise ValueError("top_k must be at least 1")
    
    if top_k > 1000:  # AWS S3 Vector service limit
        raise ValueError("top_k cannot exceed 1000")
    
    # Validate return_metadata
    if not isinstance(return_metadata, bool):
        raise ValueError("return_metadata must be a boolean")
    
    # Validate metadata_filter if provided
    if metadata_filter is not None:
        if not isinstance(metadata_filter, dict):
            raise ValueError("metadata_filter must be a dictionary/object")
    
    # Log metadata filter presence
    if metadata_filter is not None:
        logger.info(f"Request {request_id}: Query vectors with index_arn={index_arn}, top_k={top_k}, metadata_filter present")
    else:
        logger.info(f"Request {request_id}: Query vectors with index_arn={index_arn}, top_k={top_k}")
    
    # Initialize S3 Vector client
    s3vectors_client = boto3.client('s3vectors', region_name='us-west-2')
    
    try:
        # Call S3 Vector QueryVectors API with AWS API parameter names
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_S3VectorBuckets_QueryVectors.html
        query_vector_dict = {
            'float32': query_vector
        }
        
        # Build query parameters dictionary
        query_params = {
            'indexArn': index_arn,
            'topK': top_k,
            'queryVector': query_vector_dict,
            'returnMetadata': return_metadata,
            'returnDistance': True  # Always return distance for similarity calculation
        }
        
        # Conditionally add filter when metadata_filter is not None
        # boto3 S3 Vector API uses 'filter' parameter name
        if metadata_filter is not None:
            query_params['filter'] = metadata_filter
        
        # Call S3 Vector QueryVectors API with query_params
        response = s3vectors_client.query_vectors(**query_params)
        
        # Format results for PostgreSQL consumption
        results = []
        vectors = response.get('vectors', [])
        
        for vector in vectors:
            results.append({
                'vector_id': vector['key'],  # 'key' field contains the vector ID
                'distance': vector['distance'],  # Distance is already provided
                'similarity_score': 1.0 - vector['distance'],  # Convert distance to similarity
                'metadata': vector.get('metadata', {})
            })
        
        logger.info(f"Request {request_id}: Found {len(results)} similar vectors")
        return results
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.warning(f"Request {request_id}: S3 Vector QueryVectors API error: {error_code} - {str(e)}")
        raise Exception(f"S3 Vector QueryVectors failed: {error_code} - {str(e)}")


def handle_get_vectors(event: Dict[str, Any], request_id: str) -> List[Dict[str, Any]]:
    """
    Handle vector retrieval by ID(s) using S3 Vector GetVectors API (AWS API aligned)
    
    Required event fields:
    - index_arn: Full ARN of the S3 Vector index
    - vector_ids: List of vector IDs to retrieve
    - include_vector_data: Whether to include vector data (optional, default True)
    - include_metadata: Whether to include metadata (optional, default True)
    
    This function uses AWS API parameter names and is called by s3vl.get_vectors()
    """
    # Extract and validate parameters with AWS API names
    index_arn = event.get('index_arn')
    vector_ids = event.get('vector_ids')
    include_vector_data = event.get('include_vector_data', True)
    include_metadata = event.get('include_metadata', True)
    
    # Validate index_arn
    index_arn = validate_s3vector_index_arn(index_arn)
    
    # Validate vector_ids
    if not vector_ids:
        raise ValueError("Missing required parameter: vector_ids")
    
    if not isinstance(vector_ids, list):
        raise ValueError("vector_ids must be a list")
    
    if len(vector_ids) == 0:
        raise ValueError("vector_ids cannot be empty")
    
    if len(vector_ids) > 100:  # Reasonable limit for batch operations
        raise ValueError("vector_ids cannot contain more than 100 IDs")
    
    # Validate each vector ID
    for i, vector_id in enumerate(vector_ids):
        if not isinstance(vector_id, str):
            raise ValueError(f"vector_ids[{i}] must be a string, got {type(vector_id).__name__}")
        
        if not vector_id.strip():
            raise ValueError(f"vector_ids[{i}] cannot be empty or whitespace")
        
        # Basic sanitization - check for reasonable length
        if len(vector_id) > 1024:  # Reasonable limit for vector ID length
            raise ValueError(f"vector_ids[{i}] exceeds maximum length of 1024 characters")
        
        # Check for potentially problematic characters (basic sanitization)
        if any(char in vector_id for char in ['\x00', '\n', '\r', '\t']):
            raise ValueError(f"vector_ids[{i}] contains invalid control characters")
    
    # Remove duplicates while preserving order
    seen = set()
    unique_vector_ids = []
    for vector_id in vector_ids:
        if vector_id not in seen:
            seen.add(vector_id)
            unique_vector_ids.append(vector_id)
    
    # Update vector_ids to use deduplicated list
    vector_ids = unique_vector_ids
    
    # Validate boolean parameters
    if not isinstance(include_vector_data, bool):
        raise ValueError("include_vector_data must be a boolean")
    
    if not isinstance(include_metadata, bool):
        raise ValueError("include_metadata must be a boolean")
    
    logger.info(f"Request {request_id}: Getting {len(vector_ids)} vectors from index_arn={index_arn}")
    
    # Initialize S3 Vector client
    s3vectors_client = boto3.client('s3vectors', region_name='us-west-2')
    
    try:
        # Call S3 Vector GetVectors API with AWS API parameter names
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_S3VectorBuckets_GetVectors.html
        response = s3vectors_client.get_vectors(
            indexArn=index_arn,
            keys=vector_ids,
            returnData=include_vector_data,
            returnMetadata=include_metadata
        )
        
        # Create a map of found vectors for efficient lookup
        # Handle both 'Vectors' and 'vectors' response formats
        vectors_list = response.get('Vectors', response.get('vectors', []))
        found_vectors = {}
        
        for v in vectors_list:
            # Handle both 'VectorId'/'key' and 'VectorData'/'data' formats
            vector_id = v.get('VectorId', v.get('key'))
            if vector_id:
                found_vectors[vector_id] = v
        
        # Format results for PostgreSQL consumption, maintaining order and including not found vectors
        results = []
        for vector_id in vector_ids:
            if vector_id in found_vectors:
                vector = found_vectors[vector_id]
                
                # Extract vector data - handle different response formats
                vector_data = None
                if include_vector_data:
                    # Try different possible formats
                    vector_data = (
                        vector.get('VectorData') or 
                        vector.get('data', {}).get('float32') or
                        vector.get('embedding') or
                        []
                    )
                
                results.append({
                    'vector_id': vector_id,
                    'embedding': vector_data,
                    'metadata': vector.get('Metadata', vector.get('metadata', {})) if include_metadata else {},
                    'found': True
                })
            else:
                # Vector not found
                results.append({
                    'vector_id': vector_id,
                    'embedding': None,
                    'metadata': {},
                    'found': False
                })
        
        found_count = sum(1 for r in results if r['found'])
        logger.info(f"Request {request_id}: Found {found_count}/{len(vector_ids)} vectors")
        return results
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.warning(f"Request {request_id}: S3 Vector GetVectors API error: {error_code} - {str(e)}")
        raise Exception(f"S3 Vector GetVectors failed: {error_code} - {str(e)}")




def handle_list_vectors(event: Dict[str, Any], request_id: str) -> Dict[str, Any]:
    """
    Handle vector listing using S3 Vector ListVectors API (AWS API aligned)
    
    Required event fields:
    - index_arn: Full ARN of the S3 Vector index
    
    Optional event fields:
    - max_results: Maximum number of vectors to return (default 100, max 1000)
    - next_token: Pagination token for continuing from prior request
    - return_data: Whether to include vector data in response (default False)
    - return_metadata: Whether to include metadata in response (default True)
    
    This function uses AWS API parameter names and is called by s3vl.list_vectors()
    """
    # Extract and validate parameters with AWS API names
    index_arn = event.get('index_arn')
    max_results = event.get('max_results', 100)
    next_token = event.get('next_token')
    return_data = event.get('return_data', False)
    return_metadata = event.get('return_metadata', True)
    
    # Validate index_arn
    index_arn = validate_s3vector_index_arn(index_arn)
    
    # Validate max_results parameter
    if not isinstance(max_results, int):
        raise ValueError("max_results must be an integer")
    
    if max_results < 1 or max_results > 1000:
        raise ValueError("max_results must be between 1 and 1000")
    
    # Validate next_token if provided
    if next_token is not None:
        if not isinstance(next_token, str):
            raise ValueError("next_token must be a string")
        
        if not next_token.strip():
            raise ValueError("next_token cannot be empty or whitespace")
        
        # Basic length validation for pagination token
        if len(next_token) > 4096:  # Reasonable limit for pagination tokens
            raise ValueError("next_token exceeds maximum length of 4096 characters")
    
    # Validate boolean parameters
    if not isinstance(return_data, bool):
        raise ValueError("return_data must be a boolean")
    
    if not isinstance(return_metadata, bool):
        raise ValueError("return_metadata must be a boolean")
    
    logger.info(f"Request {request_id}: Listing vectors from index_arn={index_arn}, max_results={max_results}, return_data={return_data}")
    
    # Initialize S3 Vector client
    s3vectors_client = boto3.client('s3vectors', region_name='us-west-2')
    
    try:
        # Prepare ListVectors API call parameters with AWS API parameter names
        list_params = {
            'indexArn': index_arn,
            'maxResults': max_results,
            'returnData': return_data,
            'returnMetadata': return_metadata
        }
        
        # Add next_token if provided for pagination
        if next_token:
            list_params['nextToken'] = next_token
        
        # Call S3 Vector ListVectors API
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_S3VectorBuckets_ListVectors.html
        response = s3vectors_client.list_vectors(**list_params)
        
        # Format results for PostgreSQL consumption
        vectors = []
        vectors_list = response.get('vectors', [])
        
        for vector in vectors_list:
            vector_entry = {
                'vector_id': vector.get('key', ''),
            }
            
            # Include vector data if requested
            if return_data:
                vector_data = vector.get('data', {}).get('float32', [])
                vector_entry['vector_data'] = vector_data
            
            # Include metadata if requested
            if return_metadata:
                vector_entry['metadata'] = vector.get('metadata', {})
            
            vectors.append(vector_entry)
        
        # Prepare response with pagination information
        result = {
            'vectors': vectors,
            'total_count': len(vectors)
        }
        
        # Include next_token if provided by the API for pagination
        response_next_token = response.get('nextToken')
        if response_next_token:
            result['next_token'] = response_next_token
        
        logger.info(f"Request {request_id}: Listed {len(vectors)} vectors, has_more={bool(response_next_token)}")
        return result
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.warning(f"Request {request_id}: S3 Vector ListVectors API error: {error_code} - {str(e)}")
        raise Exception(f"S3 Vector ListVectors failed: {error_code} - {str(e)}")


