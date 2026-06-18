#!/bin/bash
# Create S3 bucket on MinIO instance
# Usage: create_bucket.sh <minio_url> <bucket_name>
# Requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env vars

MINIO_URL=$1
BUCKET=$2
MAX_RETRIES=10
RETRY_DELAY=5

echo "Creating bucket '$BUCKET' on $MINIO_URL..."

for i in $(seq 1 $MAX_RETRIES); do
  aws s3 mb "s3://$BUCKET" \
    --endpoint-url "$MINIO_URL" \
    --region us-east-1 \
    2>/dev/null && {
    echo "Bucket '$BUCKET' created successfully."
    exit 0
  }

  # Check if bucket already exists
  aws s3 ls "s3://$BUCKET" \
    --endpoint-url "$MINIO_URL" \
    --region us-east-1 \
    2>/dev/null && {
    echo "Bucket '$BUCKET' already exists."
    exit 0
  }

  echo "Attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_DELAY}s..."
  sleep $RETRY_DELAY
done

echo "ERROR: Failed to create bucket after $MAX_RETRIES attempts"
exit 1
