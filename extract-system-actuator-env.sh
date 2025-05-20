#!/bin/bash

# ============================================================================
# Script: extract-system-env.sh
# Descrizione:
#   Esegue una chiamata HTTP all'endpoint /actuator/env di Spring Boot
#   ed estrae tutte le variabili di ambiente contenute nel blocco "systemEnvironment",
#   stampandole nel formato:
#     - NOME_VARIABILE - VALORE
#
# Requisiti:
#   - Il servizio Spring Boot deve esporre l'endpoint /actuator/env
#   - Il tool `jq` deve essere installato nel sistema
#
# Uso:
#   chmod +x extract-system-env.sh
#   ./extract-system-env.sh
#
# Configurazione:
#   Modifica la variabile ACTUATOR_URL per puntare al tuo servizio
#
# Autenticazione:
#   Se l'endpoint è protetto, aggiungi le opzioni `-u user:pass` o il token Bearer
# ============================================================================

# === Configurazione ===
ACTUATOR_URL="http://k8s-infocame-infocame-d081d7a226-18d2ca58ef5a8983.elb.eu-south-1.amazonaws.com/actuator/env"

# === Controllo che 'jq' sia installato ===
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Errore: jq non è installato. Installalo prima di eseguire questo script."
  exit 1
fi

# === Chiamata a /actuator/env ===
echo "📡 Richiedo dati da: $ACTUATOR_URL"
response=$(curl -s -w "\n%{http_code}" "$ACTUATOR_URL")

# Separazione corpo e codice HTTP
http_body=$(echo "$response" | sed '$d')
http_code=$(echo "$response" | tail -n1)

# === Controllo codice HTTP ===
if [ "$http_code" -ne 200 ]; then
  echo "❌ Errore: risposta HTTP $http_code"
  exit 1
fi

# === Estrazione systemEnvironment ===
echo "📦 Estrazione delle variabili da 'systemEnvironment':"
# echo "$http_body" | jq -r '
#   .propertySources[]?
#   | select(.name == "systemEnvironment")
#   | .properties
#   | to_entries[]
#   | "\(.key)"
# '

# Aggiungi filtro my-app
echo "$http_body" | jq -r '
  .propertySources[]
  | select(.name == "systemEnvironment")
  | .properties
  | to_entries[]
  | select(.key | test("^SEND"))
  | "\(.key)"
'

