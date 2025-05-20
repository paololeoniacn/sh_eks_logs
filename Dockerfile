# Usa una base leggera con Python
FROM python:3.11-slim

# Imposta la working directory
WORKDIR /app

# Copia i file necessari
COPY . /app/

# Installa le dipendenze
RUN pip install --no-cache-dir -r requirements.txt

# Comando di default
ENTRYPOINT ["python", "tail_watch_cw_log.py"]
