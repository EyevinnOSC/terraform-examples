#!/usr/bin/env bash

INSTANCE_URL="$1"
QUEUE_NAME="$2"

i=1
while [ $i -le 30 ]; do
  echo "[$i/30] Checking SmoothMQ at ${INSTANCE_URL} …"

  if aws --endpoint-url "${INSTANCE_URL}" \
         --region eu-west-1 \
         sqs list-queues > /tmp/out.$$ 2>&1; then

    echo "Instance ready, creating queue '${QUEUE_NAME}' …"
    QUEUE_JSON=$(aws --endpoint-url "${INSTANCE_URL}" \
                     --region eu-west-1 \
                     sqs create-queue --queue-name "${QUEUE_NAME}")

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

echo "Instance not ready in time" >&2
exit 1