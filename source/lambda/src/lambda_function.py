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
        logger.error(f"Request {request_id}: Error: {str(e)}", exc_info=True)
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
    
    if not index_arn:
        raise ValueError("Missing required parameter: index_arn")
    
    if not query_vector:
        raise ValueError("Missing required parameter: query_vector")
    
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
        logger.error(f"Request {request_id}: S3 Vector QueryVectors API error: {error_code} - {str(e)}")
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
    
    if not index_arn:
        raise ValueError("Missing required parameter: index_arn")
    
    if not vector_ids:
        raise ValueError("Missing required parameter: vector_ids")
    
    if not isinstance(vector_ids, list):
        raise ValueError("vector_ids must be a list")
    
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
        logger.error(f"Request {request_id}: S3 Vector GetVectors API error: {error_code} - {str(e)}")
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
    
    if not index_arn:
        raise ValueError("Missing required parameter: index_arn")
    
    # Validate max_results parameter
    if not isinstance(max_results, int) or max_results < 1 or max_results > 1000:
        raise ValueError("max_results must be an integer between 1 and 1000")
    
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
        logger.error(f"Request {request_id}: S3 Vector ListVectors API error: {error_code} - {str(e)}")
        raise Exception(f"S3 Vector ListVectors failed: {error_code} - {str(e)}")


