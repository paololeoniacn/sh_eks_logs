### Cosa fa questo script

1. **Verifica presenza di `aws`**: se manca, mostra come installare AWS CLI v2 su Linux o macOS.
2. **Controlla credenziali** con `aws sts get-caller-identity`: se non sono state configurate, chiede di eseguire `aws configure`.
3. **Verifica che `date` supporti `-d`** (GNU date): su macOS consiglia l’installazione di `coreutils` (`brew install coreutils`) per avere `gdate`.
4. **Controlla esistenza del Log Group** chiamando `describe-log-groups` e cercando il nome esatto.
5. (Opzionale) Elenca i primi 5 log stream che corrispondono al prefisso, per aiutarti a scegliere.
6. **Esegue la fetch** degli ultimi 50 eventi, converte i timestamp in ISO 8601 e li stampa più recenti per primi.