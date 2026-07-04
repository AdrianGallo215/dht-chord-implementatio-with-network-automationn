#!/usr/bin/env bash
#
# Experimento 4 — Automatizacion de red sobre la DHT (el diferenciador).
#
# Que demuestra: que el anillo enruta un `run <dispositivo> <comando>` al nodo
# dueno de hash(dispositivo), ese nodo ejecuta el comando (SSH via Netmiko) y el
# resultado queda CACHEADO en el mismo almacen replicado que usan put/get: un
# `get <dispositivo>` posterior devuelve la ultima salida.
#
# Dos modos (variable MODE):
#   MODE=real (default) -> corre contra el dispositivo real de network-automation/.env
#   MODE=mock           -> usa scripts/experiments/mock-runner.py (sin hardware)

source "$(dirname "$0")/lib.sh"

require_binaries

MODE="${MODE:-real}"
COMMAND="${COMMAND:-show ip interface brief}"
export AUTOMATIONINTERPRETER="${AUTOMATIONINTERPRETER:-python3}"

if [ "$MODE" = "mock" ]; then
  export AUTOMATIONSCRIPT="$LIB_DIR/mock-runner.py"
  DEVICE="${DEVICE:-192.0.2.10}"
  info "Experimento 4: automatizacion (MODO MOCK, sin hardware)"
  note "script: $AUTOMATIONSCRIPT"
else
  ENV_FILE="$ROOT/network-automation/.env"
  if [ ! -f "$ENV_FILE" ]; then
    fail "MODE=real pero no existe $ENV_FILE (credenciales NETMIKO_*). Usa MODE=mock o crea el .env."
  fi
  # cargar y exportar NETMIKO_* para que cada nodo las herede
  set -a; source "$ENV_FILE"; set +a
  export AUTOMATIONSCRIPT="$ROOT/network-automation/netmiko-runner.py"
  DEVICE="${DEVICE:-${NETMIKO_HOST:-}}"
  if [ -z "$DEVICE" ]; then
    fail "MODE=real pero NETMIKO_HOST no esta definido en $ENV_FILE (y no pasaste DEVICE)."
  fi
  info "Experimento 4: automatizacion (MODO REAL contra $DEVICE)"
  note "script: $AUTOMATIONSCRIPT  comando: '$COMMAND'"
fi

start_ring
reader="$BASE_PORT"

# 1) ejecutar el comando via la DHT
run_out="$(client "$reader" run "$DEVICE" "$COMMAND" | sed -n 's/.* --> //p' | sed 's/"$//' | head -n1)"
assert_nonempty "$run_out" "run('$DEVICE', '$COMMAND') devuelve salida a traves del anillo"
note "salida (recortada): ${run_out:0:70}..."

# 2) el resultado quedo cacheado en la DHT: un get de la misma clave lo trae
sleep 1
get_out="$(get_value "$DEVICE" "$reader")"
assert_eq "$get_out" "$run_out" "get('$DEVICE') devuelve la MISMA salida que cacheo run (resultado replicado en la DHT)"

info "Experimento 4 OK"
