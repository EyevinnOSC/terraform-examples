#!/usr/bin/env bash
# Create the S3 bucket(s) on a (possibly just-started) S3-compatible endpoint.
# Retries to ride out MinIO startup propagation. Same pattern as the shipped OSC
# example pipelines (EyevinnOSC/terraform-examples). Authenticates with the
# instance's own root credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# (set by the Terraform local-exec environment), so it never hits the
# create-storage-bucket MCP path that fails on dedicated MinIO instances.
#
# Requires: aws-cli and bash on the machine running `terraform apply`.

endpoint="$1"
shift # remaining args are bucket names

for bucket in "$@"; do
  echo "Creating bucket: $bucket"
  for i in {1..30}; do
    result=$(aws --endpoint-url "$endpoint" s3 mb "s3://$bucket" 2>&1)

    # Success if the bucket was created or already owned by us.
    if [[ $result == *"make_bucket:"* ]] || [[ $result == *"BucketAlreadyOwnedByYou"* ]]; then
      echo "Bucket $bucket created or already exists ($result)"
      break
    fi

    echo "Waiting for storage... (attempt $i/30, result: $result)"
    sleep 10

    if [[ $i -eq 30 ]]; then
      echo "Failed to create bucket $bucket after $i attempts" >&2
      exit 1
    fi
  done
done

echo "All buckets are ready!"
exit 0
