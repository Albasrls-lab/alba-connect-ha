#!/usr/bin/with-contenv bashio
# Alba Connect 0.4 – app: tunnel WireGuard in uscita verso il concentratore Alba
set -euo pipefail

IF=alba0
ADDRESS=$(bashio::config 'address')
PRIVKEY=$(bashio::config 'private_key')
SRVKEY=$(bashio::config 'server_public_key')
ENDPOINT=$(bashio::config 'endpoint')
TECHNET=$(bashio::config 'tech_network')
PORTS=$(bashio::config 'allowed_tcp_ports')
SERVER_IP="10.88.0.1"
[[ "${ADDRESS}" =~ ^10\.88\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || bashio::exit.nok "Indirizzo non valido: ${ADDRESS}"

for v in ADDRESS PRIVKEY SRVKEY ENDPOINT TECHNET PORTS; do
    [[ -n "${!v}" && "${!v}" != "null" ]] || bashio::exit.nok "Configurazione incompleta: manca ${v}. Incollare il blocco fornito da alba-connect client-add."
done

cleanup() {
    bashio::log.info "Arresto del tunnel ${IF}"
    nft delete table inet alba_connect 2>/dev/null || true
    ip link del "${IF}" 2>/dev/null || true
    exit 0
}
trap cleanup TERM INT

# Interfaccia WireGuard (modulo del kernel di Home Assistant OS)
ip link del "${IF}" 2>/dev/null || true
ip link add "${IF}" type wireguard || bashio::exit.nok "Impossibile creare l'interfaccia WireGuard (kernel senza modulo wireguard?)"
umask 077
printf '%s\n' "${PRIVKEY}" >/tmp/alba.key
wg set "${IF}" private-key /tmp/alba.key \
    peer "${SRVKEY}" endpoint "${ENDPOINT}" persistent-keepalive 25 \
    allowed-ips "${TECHNET},${SERVER_IP}/32"
rm -f /tmp/alba.key
ip address add "${ADDRESS}/32" dev "${IF}"
ip link set "${IF}" up
ip route replace "${TECHNET}" dev "${IF}"
ip route replace "${SERVER_IP}/32" dev "${IF}"
bashio::log.info "Tunnel ${IF} attivo: ${ADDRESS} -> ${ENDPOINT}"

# Firewall locale: dal tunnel solo le porte consentite (default 80) e il ping; mai verso la LAN o i container
nft -f - <<EOF
table inet alba_connect
delete table inet alba_connect
table inet alba_connect {
    chain input {
        type filter hook input priority filter - 5; policy accept;
        iifname "${IF}" ct state established,related accept
        iifname "${IF}" ip saddr ${TECHNET} tcp dport { ${PORTS} } accept
        iifname "${IF}" ip saddr ${TECHNET} icmp type echo-request accept
        iifname "${IF}" counter drop
    }
    chain forward {
        type filter hook forward priority filter - 5; policy accept;
        iifname "${IF}" counter drop
        oifname "${IF}" ct state established,related accept
        oifname "${IF}" counter drop
    }
}
EOF
bashio::log.info "Firewall del tunnel attivo: consentite porte ${PORTS} dalla rete tecnici ${TECHNET}"

# Controllo periodico del collegamento.
# Se il concentratore è indicato con un nome DNS e il contatto manca da più di 3 minuti,
# ogni 2 minuti si risolve di nuovo il nome (il concentratore può aver cambiato indirizzo).
HOST="${ENDPOINT%:*}"
IS_NAME=0
[[ "${HOST}" =~ ^[0-9.]+$ || "${HOST}" == \[* ]] || IS_NAME=1
last=""
last_resolve=$(date +%s)
while true; do
    hs=$(wg show "${IF}" latest-handshakes | awk '{print $2}')
    now=$(date +%s)
    if [[ -n "${hs}" && "${hs}" != 0 && $((now - hs)) -lt 180 ]]; then
        state="Collegato al server Alba"
    else
        state="In attesa del server Alba (nessun contatto negli ultimi 3 minuti)"
        if [[ "${IS_NAME}" == 1 && $((now - last_resolve)) -ge 120 ]]; then
            last_resolve=${now}
            if wg set "${IF}" peer "${SRVKEY}" endpoint "${ENDPOINT}" 2>/dev/null; then
                bashio::log.info "Indirizzo del concentratore risolto di nuovo: $(wg show "${IF}" endpoints | awk '{print $2}')"
            else
                bashio::log.warning "Impossibile risolvere ${HOST}: controllare la connessione a internet e il DNS"
            fi
        fi
    fi
    if [[ "${state}" != "${last}" ]]; then
        bashio::log.info "${state}"
        last="${state}"
    fi
    sleep 30 &
    wait $!
done
