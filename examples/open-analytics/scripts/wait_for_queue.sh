#!/bin/sh

QUEUE_URL="$1"
ENDPOINT_URL="$2"

if [ -z "$QUEUE_URL" ] || [ -z "$ENDPOINT_URL" ]; then
  echo "Usage: wait_for_queue.sh <queue_url> <endpoint_url>" >&2
  exit 1
fi

i=1
while [ $i -le 30 ]; do
  if aws sqs get-queue-attributes \
        --queue-url="${QUEUE_URL}" \
        --endpoint-url="${ENDPOINT_URL}" \
        --region eu-west-1 > /dev/null 2>&1; then
    echo "Queue ready"
    exit 0
  fi
  echo "Waiting for queue ($i/30)..."
  i=$((i+1))
  sleep 5
done

echo "FATAL: Queue not ready after 150 seconds" >&2
exit 1
