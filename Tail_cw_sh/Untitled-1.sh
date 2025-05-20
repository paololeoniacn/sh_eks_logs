#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# — Verifica dipendenze
command -v aws >/dev/null || { echo "❌ aws CLI non trovata"; exit 1; }
command -v jq  >/dev/null || { echo "❌ jq non trovata"; exit 1; }

# — Parametri di default
LOG_GROUP="${LOG_GROUP:-/aws/eks/eks-tibco-test-cluster}"
REGION="${AWS_DEFAULT_REGION:-eu-south-1}"
LOOKBACK_MS="${LOOKBACK_MS:-1800000}"

STREAM_SUBSTRING=""
PATTERN=""

usage(){
  cat <<EOF >&2
Usage: $0 -s <stream_substring> [-g log_group] [-r region] [-p pattern] [-l lookback_minutes]
  -s  sottostringa da cercare nei nomi dei log-stream (obbligatorio)
  -g  nome del log group (default: $LOG_GROUP)
  -r  AWS region (default: $REGION)
  -p  filter-pattern (facoltativo)
  -l  lookback iniziale in minuti se meno di 1000 eventi (default: $((LOOKBACK_MS/60000))m)
EOF
  exit 1
}

# — Parsing argomenti
while getopts "g:r:s:p:l:" opt; do
  case "$opt" in
    g) LOG_GROUP="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    s) STREAM_SUBSTRING="$OPTARG" ;;
    p) PATTERN="$OPTARG" ;;
    l)
      [[ "$OPTARG" =~ ^[0-9]+$ ]] || { echo "❌ -l deve essere un numero"; exit 1; }
      LOOKBACK_MS=$((OPTARG * 60 * 1000))
      ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
[[ -n "$STREAM_SUBSTRING" ]] || { echo "❌ Devi specificare -s <stream_substring>"; usage; }

# — Caricamento .env
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"
[[ -f "$ENV_FILE" ]] && { set -o allexport; . "$ENV_FILE"; set +o allexport; }

# — 1) SINCE_MS iniziale con Logs Insights
END_TIME_MS=$(( $(date +%s) * 1000 ))
QID=$(aws logs start-query \
       --log-group-names "$LOG_GROUP" \
       --start-time 0 \
       --end-time "$END_TIME_MS" \
       --query-string 'fields @timestamp | sort @timestamp desc | limit 1000' \
       --region "$REGION" \
       --output text --query 'queryId')

MAX_WAIT=30; WAITED=0
while :; do
  sleep 1; ((WAITED++))
  STATUS=$(aws logs get-query-results \
             --query-id "$QID" \
             --region "$REGION" \
             --output json \
           | jq -r '.status')
  [[ "$STATUS" == "Complete" ]] && break
  if (( WAITED >= MAX_WAIT )); then
    echo "⚠️ Timeout Logs Insights, fallback sul look-back temporale" >&2
    STATUS="TimedOut"; break
  fi
done

if [[ "$STATUS" == "Complete" ]]; then
  RES=$(aws logs get-query-results --query-id "$QID" --region "$REGION" --output json)
  SINCE_MS=$(echo "$RES" | jq -r '
    [ .results[][]
      | select(.field=="@timestamp")
      | .value
      | tonumber
    ]
    | min + 1
  ')
fi

if [[ -z "${SINCE_MS:-}" || "$SINCE_MS" == "null" ]]; then
  NOW_MS=$(( $(date +%s) * 1000 ))
  SINCE_MS=$(( NOW_MS - LOOKBACK_MS ))
fi

# — 2) Polling continuo
while :; do
  # a) filtro dei log-stream
  STREAM_NAMES=$(aws logs describe-log-streams \
                   --log-group-name "$LOG_GROUP" \
                   --region "$REGION" \
                   --no-paginate \
                   --max-items 10000 \
                   --output json \
                 | jq -r --arg s "$STREAM_SUBSTRING" '
                     .logStreams[].logStreamName
                     | select(contains($s))
                   ')
  set -- $STREAM_NAMES
  if [ $# -eq 0 ]; then
    echo "⚠️ Nessuno stream contiene '$STREAM_SUBSTRING', riprovo tra 30s…" >&2
    sleep 30; continue
  fi

  # b) estrazione log
  RESP=$(aws logs filter-log-events \
           --log-group-name "$LOG_GROUP" \
           --log-stream-names "$@" \
           --interleaved \
           --start-time "$SINCE_MS" \
           --filter-pattern "$PATTERN" \
           --limit 10000 \
           --region "$REGION" \
           --output json)

  # c) estraggo .log solo dai JSON, altrimenti plain-text
  echo "$RESP" | jq -r '
    .events[]
    | .message as $m
    | ($m | startswith("{") and $m | endswith("}")) as $isJson
    | if $isJson
      then (try($m | fromjson | .log) catch $m)
      else $m
      end
  '

  # d) aggiorno SINCE_MS
  LAST_TS=$(echo "$RESP" | jq -r '[.events[].timestamp] | max // empty')
  [[ -n "$LAST_TS" ]] && SINCE_MS=$(( LAST_TS + 1 ))

  sleep 5
done
