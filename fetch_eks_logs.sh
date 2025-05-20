# ------------------------------------------------------------
# USAGE
# ------------------------------------------------------------

# Solo errori (default 3 righe di contesto):
# ./fetch-eks-logs.sh -e my-log-group my-prefix eu-south-1

# Errori + 5 righe di contesto:
# ./fetch-eks-logs.sh -e -c 5 my-log-group my-prefix

# Tutti i log (senza filtro):
# ./fetch-eks-logs.sh my-log-group

# Il flag -e attiva il filtro sui messaggi contenenti “ERROR” 
# (tipico di stacktrace Java), mentre -c N ti mostra N righe prima e dopo ogni match. 
# Se non specifichi -e, tornerai al comportamento originale.


#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# 1) Parametri e flags
# ------------------------------------------------------------
ERRORS=false
CONTEXT=3

# parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--errors)
      ERRORS=true
      shift
      ;;
    -c|--context)
      CONTEXT="$2"
      shift 2
      ;;
    --) # end of flags
      shift
      break
      ;;
    -*) # unexpected flag
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *) 
      break
      ;;
  esac
done

LOG_GROUP="${1:-}"
STREAM_PREFIX="${2:-}"
REGION="${3:-eu-south-1}"

if [[ -z "$LOG_GROUP" ]]; then
  echo "Usage: $0 [-e|--errors] [-c N|--context N] <LOG_GROUP> [STREAM_PREFIX] [REGION]" >&2
  exit 1
fi

# ------------------------------------------------------------
# 2) Funzione di errore
# ------------------------------------------------------------
err() {
  echo "ERROR: $*" >&2
  exit 1
}

# ------------------------------------------------------------
# 3) Controlli dipendenze
# ------------------------------------------------------------
command -v aws >/dev/null 2>&1 || {
  cat <<EOF >&2
'aws' non trovato. Per installare AWS CLI v2:
  • Linux:
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip awscliv2.zip && sudo ./aws/install
  • macOS (Homebrew):
      brew install awscli
EOF
  exit 1
}

aws sts get-caller-identity --output json >/dev/null 2>&1 || {
  echo "AWS CLI non configurato. Esegui: aws configure" >&2
  exit 1
}

# GNU date
if date --version 2>&1 | grep -qi 'gnu'; then
  DATE_CMD=date
elif command -v gdate >/dev/null 2>&1; then
  DATE_CMD=gdate
else
  cat <<EOF >&2
Serve GNU date (opzione -d). Su macOS:
  brew install coreutils
e riprova (usando 'gdate').
EOF
  exit 1
fi

# ------------------------------------------------------------
# 4) Verifica Log Group esistente
# ------------------------------------------------------------
if ! aws logs describe-log-groups \
      --log-group-name-prefix "$LOG_GROUP" \
      --region "$REGION" \
      --query 'logGroups[?logGroupName==`'"$LOG_GROUP"'`]' \
      --output text | grep -q .; then
  err "Log group '$LOG_GROUP' non trovato in '$REGION'."
fi

# ------------------------------------------------------------
# 5) (Opzionale) Elenco stream
# ------------------------------------------------------------
if [[ -n "$STREAM_PREFIX" ]]; then
  echo "=== Matching streams in $LOG_GROUP with prefix '$STREAM_PREFIX' ==="
  aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name-prefix "$STREAM_PREFIX" \
    --order-by LastEventTime --descending \
    --limit 5 \
    --region "$REGION" \
    --query 'logStreams[].logStreamName' \
    --output text \
    || err "Impossibile elencare i log stream"
  echo
fi

# ------------------------------------------------------------
# 6) Fetch, conversione e filtro
# ------------------------------------------------------------
# 6.1 scarica timestamp(ms) + message
raw_events=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  ${STREAM_PREFIX:+--log-stream-name-prefix "$STREAM_PREFIX"} \
  --limit 1000 \
  --region "$REGION" \
  --query 'events[].{time:timestamp,message:message}' \
  --output text)

# 6.2 mappa in array, converte timestamp e costruisce output
mapfile -t lines <<<"$raw_events"
converted=()
for line in "${lines[@]}"; do
  ts_ms="${line%%$'\t'*}"
  msg="${line#*$'\t'}"
  iso=$($DATE_CMD -d "@$((ts_ms/1000))" --utc +"%Y-%m-%dT%H:%M:%SZ")
  converted+=("[$iso] $msg")
done

# 6.3 stampa, con eventuale filtro e contesto
if $ERRORS; then
  printf "%s\n" "${converted[@]}" | \
    grep -E -C "$CONTEXT" "ERROR" || true
else
  printf "%s\n" "${converted[@]}"
fi
