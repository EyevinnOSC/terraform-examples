#!/usr/bin/env bash
# Try to connect to the S3-compatible storage and create the buckets

endpoint="$1"
shift  # remove the first arg, leaving only bucket names

for bucket in "$@"; do
  echo "Creating bucket: $bucket"
  for i in {1..30}; do
    result=$(aws --endpoint-url "$endpoint" s3 mb "s3://$bucket" 2>&1)

    # Success if bucket created or already owned by you
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