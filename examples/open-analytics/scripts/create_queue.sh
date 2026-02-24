#!/bin/sh
set -e

INSTANCE_URL="$1"
QUEUE_NAME="$2"

if [ -z "$INSTANCE_URL" ] || [ -z "$QUEUE_NAME" ]; then
  echo "Usage: create_queue.sh <instance_url> <queue_name>" >&2
  exit 1
fi

i=1
while [ $i -le 30 ]; do
  echo "[$i/30] Checking SmoothMQ at ${INSTANCE_URL} …"

  if aws --endpoint-url "${INSTANCE_URL}" \
         --region eu-west-1 \
         sqs list-queues > /tmp/out.$$ 2>&1; then

    echo "Instance ready, creating queue '${QUEUE_NAME}' …"
    QUEUE_JSON=$(aws --endpoint-url "${INSTANCE_URL}" \
                     --region eu-west-1 \
                     sqs create-queue --queue-name "${QUEUE_NAME}") || {
      echo "FATAL: aws sqs create-queue failed" >&2
      exit 1
    }

    # Validate that the response contains a QueueUrl
    if ! echo "$QUEUE_JSON" | grep -q '"QueueUrl"'; then
      echo "FATAL: create-queue response missing QueueUrl: $QUEUE_JSON" >&2
      exit 1
    fi

    echo "Queue creation output:"
    echo "$QUEUE_JSON"

    echo "$QUEUE_JSON" > "${PWD}/queue_output.json"
    echo "Saved to ${PWD}/queue_output.json"
    exit 0
  fi

  echo "Still not ready:"
  cat /tmp/out.$$
  i=$((i+1))
  sleep 5
done

echo "FATAL: SmoothMQ instance not ready after 150 seconds" >&2
exit 1
