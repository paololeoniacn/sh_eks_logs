#!/usr/bin/env bash
set -euo pipefail

# ——————————————————————————————
# 1) Carica .env (AWS creds + region)
# ——————————————————————————————
ENV_FILE="./.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERRORE: non trovo '$ENV_FILE'." >&2
  exit 1
fi
set -a
. "$ENV_FILE"
set +a

: "${AWS_DEFAULT_REGION:?Devi definire AWS_DEFAULT_REGION nel tuo .env}"
: "${AWS_ACCESS_KEY_ID:?Devi definire AWS_ACCESS_KEY_ID nel tuo .env}"
: "${AWS_SECRET_ACCESS_KEY:?Devi definire AWS_SECRET_ACCESS_KEY nel tuo .env}"

# ——————————————————————————————
# 2) Parametri
# ——————————————————————————————
LOG_GROUP="/aws/eks/eks-tibco-test-cluster"
PATTERN="utility"
LIMIT=100

# ——————————————————————————————
# 3) Recupera TUTTI i log-streams in JSON (auto-paginati)
# ——————————————————————————————
echo "🔍 Scarico tutti i log-stream di '$LOG_GROUP'…"
TMP_JSON="$(mktemp)"
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --no-paginate \
  --output json \
  > "$TMP_JSON"

TOTAL=$(jq '.logStreams | length' "$TMP_JSON")
echo "📂 Trovati $TOTAL stream in totale."

# ——————————————————————————————
# 4) Filtra con jq per contains("$PATTERN") e prendi il primo [0]
# ——————————————————————————————
latest_stream=$(jq -r --arg pat "$PATTERN" '
  .logStreams
  | map(select(.logStreamName | contains($pat)))
  | .[0].logStreamName // empty
' "$TMP_JSON")

# Rimuovi il file temporaneo
rm -f "$TMP_JSON"

if [[ -z "$latest_stream" ]]; then
  echo "⚠️ Nessuno stream trovato con pattern '$PATTERN'." >&2
  exit 1
fi

echo "📄 Stream selezionato: $latest_stream"
echo

convert_date(){
  local epoch_s=$1
  if [[ "$(uname)" == "Darwin" ]]; then
    date -r "$epoch_s" +"%Y-%m-%dT%H:%M:%S"
  else
    date -d "@$epoch_s" +"%Y-%m-%dT%H:%M:%S"
  fi
}

# ——————————————————————————————
# 5) Se esiste `aws logs tail`, usalo col debug in ./logs/debug
# ——————————————————————————————
if aws logs help tail >/dev/null 2>&1; then
  echo "⏳ Facendo tail in realtime con 'aws logs tail'… (Ctrl+C per uscire)"

  # Abilita tracing solo per questo blocco
  set -x

  # Assicurati che la cartella esista
  mkdir -p logs/debug

  # Genera un nome univoco nella sottocartella locale
  TS=$(date +%Y%m%d%H%M%S)
  DBGLOG="$(mktemp logs/debug/aws-tail-debug.${TS}.log)"

  # Esegui il tail con --debug e salva tutto in DBGLOG, poi passa a jq
  aws logs tail "$LOG_GROUP" \
    --filter-pattern "$PATTERN" \
    --since 5h \
    --format detailed \
    --follow \
    --debug 2> "$DBGLOG" \
  | jq -r '.message | fromjson.log'

  # Disabilita tracing per il resto dello script
  set +x

  echo "— DEBUG LOG salvato in $DBGLOG —"
  exit 0
fi
