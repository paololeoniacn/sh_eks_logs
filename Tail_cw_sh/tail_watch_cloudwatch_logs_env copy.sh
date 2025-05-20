#!/usr/bin/env sh

# Uso:
#   ./tail_watch_cloudwatch_logs.sh [-s SINCE]
#
# - SINCE: intervallo di tempo relativo (es. 5m, 2h, 1d) da cui partire.
#          Default: 15m.

# 1) Verifica che AWS CLI sia installata
if ! command -v aws >/dev/null 2>&1; then
  echo "Errore: AWS CLI non trovata. Installa AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
  exit 1
fi

# 2) Carica le variabili da .env (se esiste)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  set -o allexport
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +o allexport
else
  echo "Avviso: file .env non trovato in $ENV_FILE. Assicurati di averlo creato con le credenziali AWS." >&2
fi

# 3) Controllo credenziali minime
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "Errore: credenziali AWS mancanti. Verifica che nel .env siano presenti AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY." >&2
  exit 1
fi

# 4) Default per SINCE
SINCE_DEFAULT="15m"
SINCE="$SINCE_DEFAULT"

# 5) Parsing opzione -s per SINCE
while getopts "s:" opt; do
  case "$opt" in
    s) SINCE="$OPTARG" ;;
    *)
      echo "Usage: $0 [-s SINCE]" >&2
      echo "  SINCE esempio: 5m, 2h, 1d (default: $SINCE_DEFAULT)" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# 6) Configurazioni fisse
LOG_GROUP="/aws/eks/eks-tibco-test-cluster"
REGION="${AWS_DEFAULT_REGION:-eu-south-1}"

# 7) Eseguiamo il tail con prefisso [stream] su ogni riga
# aws logs tail "$LOG_GROUP" \
#   --follow \
#   --format detailed \
#   --since "$SINCE" \
#   --region "$REGION" \
# | awk '{
#     # salva timestamp e nome dello stream
#     ts = $1
#     stream = $2
#     # rimuove i primi due campi per ottenere solo il messaggio
#     $1=""; $2=""
#     # elimina gli spazi iniziali restanti
#     sub(/^  */, "", $0)
#     # output: timestamp [stream] message
#     print ts " [" stream "] " $0
#   }'

# # 30 minuti
# # ./tail_watch_cloudwatch_logs.sh -s 30m

echo ">> aws logs tail $@"

# 7) Eseguiamo il tail ed estraiamo solo il campo "log"
aws logs tail "$LOG_GROUP" \
  --follow \
  --format detailed \
  --since "$SINCE" \
  --region "$REGION" \
| while IFS= read -r line; do
    # Estrai la parte JSON (tutto dopo il primo `{`)
    json_part=$(echo "$line" | sed 's/^[^{]*//')

    # Estrai il campo log (se valido JSON)
    log=$(echo "$json_part" | jq -r '.log // empty' 2>/dev/null)

    # Se esiste, stampalo
    if [ -n "$log" ]; then
      echo "$log"
    fi
  done
