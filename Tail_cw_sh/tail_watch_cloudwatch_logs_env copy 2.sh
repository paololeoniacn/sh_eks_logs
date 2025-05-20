#!/usr/bin/env sh
set -o errexit
set -o nounset
set -o pipefail
trap '' PIPE    # ignora SIGPIPE per non vedere BrokenPipeError

# Defaults
SINCE="30m"
LOG_GROUP="/aws/eks/eks-tibco-test-cluster"
REGION="${AWS_DEFAULT_REGION:-eu-south-1}"
PATTERN=""
STREAM_PREFIX=""
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

usage() {
  cat <<EOF
Usage: $0 [-s SINCE] [-g LOG_GROUP] [-r REGION] [-p PATTERN] [-x STREAM_PREFIX] [-h]
  -s SINCE           intervallo (es. 5m,2h,1d)        (default: $SINCE)
  -g LOG_GROUP       gruppo CloudWatch Logs          (default: $LOG_GROUP)
  -r REGION          AWS region                       (default: $REGION)
  -p PATTERN         filtro CloudWatch (es. "ERROR")
  -x STREAM_PREFIX   prefisso nome stream (es. "spring-app")
  -h                 mostra questo help
EOF
  exit 1
}

# Parsing opzioni
while getopts "s:g:r:p:x:h" opt; do
  case "$opt" in
    s) SINCE="$OPTARG" ;;
    g) LOG_GROUP="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    p) PATTERN="$OPTARG" ;;
    x) STREAM_PREFIX="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Verifica dipendenze
for cmd in aws jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Errore: comando '$cmd' non trovato. Installalo prima di proseguire." >&2
    exit 1
  fi
done

# Validazione SINCE
if ! echo "$SINCE" | grep -Eq '^[0-9]+[smhd]$'; then
  echo "Errore: SINCE deve essere del formato '5m', '2h', '1d'." >&2
  exit 1
fi

# Caricamento .env (se esiste)
if [ -f "$ENV_FILE" ]; then
  set -o allexport
  . "$ENV_FILE"
  set +o allexport
fi

# Controllo credenziali AWS
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "Errore: credenziali AWS mancanti (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)." >&2
  exit 1
fi

# Costruzione dinamica degli argomenti per aws logs tail
# ricostruisco i parametri POSIX-compatibili
set -- "$LOG_GROUP" \
  --follow \
  --since "$SINCE" \
  --region "$REGION"

[ -n "$PATTERN"      ] && set -- "$@" --filter-pattern "$PATTERN"
[ -n "$STREAM_PREFIX" ] && set -- "$@" --log-stream-name-prefix "$STREAM_PREFIX"

echo "AWS VERSION"
aws --version
ECHO "JS VERSION"
jq --version
echo ">> aws logs tail $@"

# tail senza --format, e awk per dividere su: ts, stream, messaggio
aws logs tail "$@" --format short \
| awk '{ $1=""; sub(/^ /,""); print }' \
| jq -R 'fromjson? | .log // .'