#!/usr/bin/env bash
# tail_eks_tibco.sh
# Uso: ./tail_eks_tibco.sh [env_file]
# - env_file: percorso al file .env con AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (opzionale), AWS_DEFAULT_REGION o AWS_REGION

set -eo pipefail

ENV_FILE=${1:-.env}
if [[ ! -f "$ENV_FILE" ]]; then
  echo "File ENV non trovato: $ENV_FILE" >&2
  exit 1
fi

# Esporta tutte le variabili dal file env
set -a
source "$ENV_FILE"
set +a

LOG_GROUP="/aws/eks/eks-tibco-test-cluster"
STREAM_PATTERN="utility"
N=100
REGION=${AWS_DEFAULT_REGION:-$AWS_REGION}

# 1) Elenca tutti i log stream che contengono "utility"
STREAMS=( $(
  aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --query "logStreams[?contains(logStreamName, \`$STREAM_PATTERN\`)].logStreamName" \
    --output text \
    --region "$REGION"
) )

if [[ ${#STREAMS[@]} -eq 0 ]]; then
  echo "❌ Nessun log stream trovato con pattern '$STREAM_PATTERN' in '$LOG_GROUP'" >&2
  exit 1
fi

# 2) Stampa le ultime N voci di log (solo messaggi)
echo -e "\n=== Ultime $N voci di log ==="
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-names "${STREAMS[@]}" \
  --limit "$N" \
  --query "events[].message" \
  --output text \
  --region "$REGION"
echo -e "\n=== Fine delle ultime $N voci ==="

# 3) Avvia il live tail (rimane in esecuzione finché non premi CTRL+C)
echo -e "\n=== Avvio live tail (CTRL+C per uscire) ==="
aws logs tail "$LOG_GROUP" \
  --log-stream-names "${STREAMS[@]}" \
  --follow \
  --region "$REGION"
