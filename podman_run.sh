#!/bin/bash

# ./run_podman.sh --filter utility --since 30m

# Nome immagine
IMAGE_NAME=cloudwatch-tail

# Costruisce l'immagine (solo se vuoi sempre ricostruire, altrimenti rimuovi questa riga)
podman build -t $IMAGE_NAME .

# Avvia il container con file .env e parametri personalizzati
podman run --rm -it \
  --env-file .env \
  $IMAGE_NAME "$@"
