#!/bin/bash
# Seed parameter store with configuration values
# Requires: CONFIG_URL, MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET, VALKEY_URL

set -e
MAX_RETRIES=10
RETRY_DELAY=5

echo "Waiting for config service at $CONFIG_URL..."

for i in $(seq 1 $MAX_RETRIES); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$CONFIG_URL/api/v1/config" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "Config service is ready."
    break
  fi
  echo "Attempt $i/$MAX_RETRIES (status=$STATUS), retrying in ${RETRY_DELAY}s..."
  sleep $RETRY_DELAY
  if [ "$i" = "$MAX_RETRIES" ]; then
    echo "ERROR: Config service not ready after $MAX_RETRIES attempts"
    exit 1
  fi
done

echo "Setting configuration values..."

set_config() {
  local key=$1
  local value=$2
  curl -sf -X PUT "$CONFIG_URL/api/v1/config/$key" \
    -H "Content-Type: application/json" \
    -d "{\"value\": \"$value\"}" > /dev/null
  echo "  $key = set"
}

set_config "MINIO_ENDPOINT" "$MINIO_ENDPOINT"
set_config "MINIO_ACCESS_KEY" "$MINIO_ACCESS_KEY"
set_config "MINIO_SECRET_KEY" "$MINIO_SECRET_KEY"
set_config "MINIO_BUCKET" "$MINIO_BUCKET"
set_config "VALKEY_URL" "$VALKEY_URL"

echo "Configuration seeded successfully."
