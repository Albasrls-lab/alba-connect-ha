# Alba Connect

App per l'**assistenza remota Alba** (servizio Dolomiti Connect).

## Cosa fa

- Apre un tunnel WireGuard **in uscita** verso il concentratore Alba: sul router di casa non si apre nessuna porta.
- Dal tunnel possono arrivare **solo i tecnici Alba autorizzati** su questo impianto, e **solo** alla pagina di Home Assistant (porta 80). Nessun accesso al resto della rete di casa.
- Ogni accesso dei tecnici è registrato dal concentratore Alba.

## Configurazione

La configurazione viene fornita da Alba al momento dell'installazione (pannello Dolomiti Connect):

1. scheda **Configurazione** → ⋮ → **Modifica in YAML**;
2. incollare il blocco ricevuto (`address`, `private_key`, `server_public_key`, `endpoint`, `tech_network`, `allowed_tcp_ports`);
3. **Salva**, poi **Avvia**; attivare **Avvio all'accensione** e **Watchdog**.

Nel **Registro** devono comparire *Tunnel alba0 attivo*, *Firewall del tunnel attivo* e *Collegato al server Alba*.

## Disattivare l'assistenza

Fermare l'app (o disinstallarla). Da quel momento Alba non può più collegarsi a questo impianto.

## Note

- La chiave privata resta solo in questa centrale; il codice dell'app non contiene chiavi né dati dei clienti.
- Se il concentratore cambia indirizzo, l'app ritrova il nuovo indirizzo da sola (nome DNS), senza riconfigurare.
