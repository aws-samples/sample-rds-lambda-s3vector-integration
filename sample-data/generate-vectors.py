#!/usr/bin/env python3
"""
Sample Vector Data Generator for S3 Vector Testing

This script generates sample vector data with 5 dimensions for testing
the sample-rds-lambda-s3vector integration. It creates vectors with simple metadata
and outputs them in AWS CLI batch format for loading into an S3 Vector Index.
"""

import json
import random
import argparse
import sys
from typing import List, Dict, Any


class SampleVectorGenerator:
    """Generates sample vector data for testing purposes."""
    
    def __init__(self, count: int = 50):
        """
        Initialize the generator.
        
        Args:
            count: Number of vectors to generate (minimum 50)
        """
        self.dimensions = 5  # Fixed to 5 dimensions
        self.count = count
        self.categories = ["test", "sample", "demo", "example"]
        
    def _generate_random_vector(self) -> List[float]:
        """Generate a random normalized vector."""
        # Generate random values between -1 and 1
        vector = [random.uniform(-1.0, 1.0) for _ in range(self.dimensions)]
        
        # Normalize the vector
        magnitude = sum(x * x for x in vector) ** 0.5
        if magnitude > 0:
            vector = [x / magnitude for x in vector]
        
        return vector
    
    def _generate_similar_vector(self, base_vector: List[float], similarity: float = 0.8) -> List[float]:
        """
        Generate a vector similar to the base vector.
        
        Args:
            base_vector: The base vector to create similarity with
            similarity: Similarity factor (0.0 to 1.0)
        """
        # Create a similar vector by adding small random noise
        noise_factor = 1.0 - similarity
        similar_vector = []
        
        for val in base_vector:
            noise = random.uniform(-noise_factor, noise_factor) * 0.5
            similar_vector.append(val + noise)
        
        # Normalize the result
        magnitude = sum(x * x for x in similar_vector) ** 0.5
        if magnitude > 0:
            similar_vector = [x / magnitude for x in similar_vector]
        
        return similar_vector
    
    def generate_vectors(self) -> List[Dict[str, Any]]:
        """
        Generate the complete set of sample vectors.
        
        Returns:
            List of vector dictionaries with id, values, and metadata
        """
        vectors = []
        
        # Generate base vectors (70% of total)
        base_count = int(self.count * 0.7)
        base_vectors = []
        
        for i in range(base_count):
            vector_id = f"vec_{i+1:03d}"
            values = self._generate_random_vector()
            category = random.choice(self.categories)
            
            vector_data = {
                "id": vector_id,
                "values": [round(v, 6) for v in values],  # Round to 6 decimal places
                "metadata": {
                    "category": category,
                    "id": str(i + 1)
                }
            }
            
            vectors.append(vector_data)
            base_vectors.append(values)
        
        # Generate similar vectors (25% of total)
        similar_count = int(self.count * 0.25)
        for i in range(similar_count):
            vector_id = f"vec_{base_count + i + 1:03d}"
            # Pick a random base vector to create similarity with
            base_vector = random.choice(base_vectors)
            values = self._generate_similar_vector(base_vector, similarity=0.85)
            category = random.choice(self.categories)
            
            vector_data = {
                "id": vector_id,
                "values": [round(v, 6) for v in values],
                "metadata": {
                    "category": category,
                    "id": str(base_count + i + 1)
                }
            }
            
            vectors.append(vector_data)
        
        # Generate identical vectors for exact match testing (5% of total)
        identical_count = self.count - base_count - similar_count
        if identical_count > 0:
            # Create a few identical vectors
            test_vector = self._generate_random_vector()
            for i in range(identical_count):
                vector_id = f"vec_{base_count + similar_count + i + 1:03d}"
                
                vector_data = {
                    "id": vector_id,
                    "values": [round(v, 6) for v in test_vector],
                    "metadata": {
                        "category": "identical",
                        "id": str(base_count + similar_count + i + 1)
                    }
                }
                
                vectors.append(vector_data)
        
        return vectors
    
    def save_aws_cli_format(self, vectors: List[Dict[str, Any]], filename: str) -> None:
        """Save vectors in AWS CLI batch format (JSON array of objects)."""
        aws_vectors = []
        for vector in vectors:
            # Format for AWS S3 Vector CLI put-vectors batch operation
            aws_format = {
                "key": vector["id"],
                "data": {
                    "float32": vector["values"]
                },
                "metadata": vector["metadata"]
            }
            aws_vectors.append(aws_format)
        
        with open(filename, 'w') as f:
            json.dump(aws_vectors, f, indent=2)
        
        print(f"AWS CLI batch format saved to: {filename}")


def main():
    """Main function to handle command line arguments and generate vectors."""
    parser = argparse.ArgumentParser(
        description="Generate sample vector data for S3 Vector testing (5 dimensions, AWS CLI format)"
    )
    
    parser.add_argument(
        "--count", "-c",
        type=int,
        default=50,
        help="Number of vectors to generate (minimum 50) - default: 50"
    )
    
    parser.add_argument(
        "--output", "-o",
        type=str,
        default="sample_vectors_aws_cli.json",
        help="Output filename - default: sample_vectors_aws_cli.json"
    )
    
    args = parser.parse_args()
    
    # Validate arguments
    if args.count < 50:
        print("Warning: Minimum recommended count is 50 vectors, using 50")
        args.count = 50
    
    # Generate vectors
    generator = SampleVectorGenerator(count=args.count)
    vectors = generator.generate_vectors()
    
    # Save in AWS CLI format
    generator.save_aws_cli_format(vectors, args.output)
    
    # Print summary
    print(f"\nSummary:")
    print(f"- Dimensions: 5 (fixed)")
    print(f"- Total vectors: {len(vectors)}")
    print(f"- Categories: {generator.categories}")
    print(f"- Format: AWS CLI")
    
    # Show sample vector
    if vectors:
        print(f"\nSample vector:")
        sample = vectors[0]
        print(f"ID: {sample['id']}")
        print(f"Values: {sample['values']}")
        print(f"Metadata: {sample['metadata']}")
        
        print(f"\nAWS CLI format example:")
        aws_format = {
            "key": sample["id"],
            "data": {"float32": sample["values"]},
            "metadata": sample["metadata"]
        }
        print(json.dumps(aws_format, indent=2))


if __name__ == "__main__":
    main()