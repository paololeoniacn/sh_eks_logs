#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

LOG_GROUP="${LOG_GROUP:-/aws/eks/eks-tibco-test-cluster}"
REGION="${AWS_DEFAULT_REGION:-eu-south-1}"
SINCE_MS=$(( $(date +%s) * 1000 - ${SINCE_VALUE:-1800000} ))  # es. 30m = 1800000ms

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"
# Caricamento .env (se esiste)
if [ -f "$ENV_FILE" ]; then
  set -o allexport
  . "$ENV_FILE"
  set +o allexport
fi

while :; do
  RESP=$(aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --interleaved \
    --start-time "$SINCE_MS" \
    --filter-pattern "${PATTERN:-}" \
    --limit 1000 \
    --region "$REGION" \
    --output json)

  # Estrae solo .message, lo parsea come JSON e ne estrae .log;
  # se non è JSON valido, restituisce la stringa originale
  echo "$RESP" | jq -r '
    .events[]
    | .message
    | try (fromjson | .log) catch .
  '  

  LAST_TS=$(echo "$RESP" | jq -r '[.events[].timestamp] | max // empty')
  (( SINCE_MS = LAST_TS + 1 ))

  sleep 5
done

