#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <endpoint-url> <bucket-name>"
    echo "Example: $0 http://localhost:9000 my-bucket"
    echo ""
    exit 1
}

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    usage
fi

ENDPOINT_URL=$1
BUCKET_NAME=$2


RESOURCE="arn:aws:s3:::${BUCKET_NAME}/*"

echo "Setting public read access for bucket: $BUCKET_NAME"

# Create temporary policy file
POLICY_FILE=$(mktemp)
cat > "$POLICY_FILE" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "$RESOURCE"
    }
  ]
}
EOF

echo "Created policy file: $POLICY_FILE"
echo "Policy content:"
cat "$POLICY_FILE"
echo ""

# Retry configuration
MAX_RETRIES=30
RETRY_DELAY=10
retry_count=0

# Function to apply policy
apply_policy() {
    aws --endpoint-url "$ENDPOINT_URL" s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy "file://$POLICY_FILE" 2>&1
}

# Retry loop
echo "Attempting to apply policy (max $MAX_RETRIES retries)..."
while [ $retry_count -lt $MAX_RETRIES ]; do
    result=$(apply_policy)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "✓ Successfully applied public read policy to $BUCKET_NAME"
        
        # Verify the policy was applied
        echo ""
        echo "Verifying policy..."
        aws --endpoint-url "$ENDPOINT_URL" s3api get-bucket-policy \
            --bucket "$BUCKET_NAME" --output json 2>/dev/null
        
        # Cleanup
        rm -f "$POLICY_FILE"
        exit 0
    else
        retry_count=$((retry_count + 1))
        
        # Check if it's a "bucket doesn't exist" error
        if echo "$result" | grep -q -i "NoSuchBucket\|does not exist\|not found"; then
            echo "⟳ Attempt $retry_count/$MAX_RETRIES: Bucket not found yet, retrying in ${RETRY_DELAY}s..."
        else
            echo "⟳ Attempt $retry_count/$MAX_RETRIES: Failed with error:"
            echo "$result"
            echo "Retrying in ${RETRY_DELAY}s..."
        fi
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    fi
done

# If we get here, all retries failed
echo "✗ Failed to apply policy after $MAX_RETRIES attempts"
echo "Last error:"
echo "$result"

# Cleanup
rm -f "$POLICY_FILE"
exit 1