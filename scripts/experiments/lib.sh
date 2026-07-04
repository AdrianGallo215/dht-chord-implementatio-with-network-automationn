#!/usr/bin/env bash
#
# lib.sh — primitivas compartidas por todos los experimentos del anillo Chord.
#
# Se sourcea desde cada script de experimento (`source "$(dirname "$0")/lib.sh"`).
# Da funciones reutilizables para levantar/tumbar un anillo de nodos independientes,
# hablar con el cliente, localizar al dueño de una clave, matar un nodo concreto y
# hacer aserciones con salida PASS/FAIL. Escribir un experimento nuevo es sourcear
# esto y llamar a estas funciones (ver README.md).
#
# Perillas por variable de entorno (con valores por defecto):
#   N          numero de nodos del anillo                          (default 4)
#   BASE_PORT  puerto del nodo bootstrap                           (default 9100)
#   WAIT_MAX   segundos maximos a esperar la convergencia del anillo (default 30)
#
# Requiere: los binarios server/chord y client/chord (se compilan solos si faltan).

set -u

# --- rutas ------------------------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LIB_DIR/../.." && pwd)"
SERVER="$ROOT/server/chord"
CLIENT="$ROOT/client/chord"

# --- perillas ---------------------------------------------------------------
N="${N:-4}"
BASE_PORT="${BASE_PORT:-9100}"
WAIT_MAX="${WAIT_MAX:-30}"

# --- estado interno ---------------------------------------------------------
RUNDIR=""          # directorio temporal de esta corrida (logs + nodes.txt)
declare -a KILLED  # puertos de nodos que matamos a proposito

# --- colores (solo si stdout es un tty) -------------------------------------
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_BLUE=""; C_DIM=""; C_OFF=""
fi

info() { echo "${C_BLUE}==>${C_OFF} $*"; }
note() { echo "${C_DIM}    $*${C_OFF}"; }

# --- aserciones -------------------------------------------------------------
pass() { echo "${C_GREEN}  PASS${C_OFF} $*"; }

fail() {
  echo "${C_RED}  FAIL${C_OFF} $*" >&2
  exit 1   # el trap EXIT llama a stop_ring; run-all.sh detecta el codigo != 0
}

assert_eq() {   # assert_eq GOT WANT MENSAJE
  local got="$1" want="$2" msg="$3"
  if [ "$got" = "$want" ]; then
    pass "$msg"
  else
    fail "$msg (obtuve '$got', esperaba '$want')"
  fi
}

assert_nonempty() {  # assert_nonempty VALOR MENSAJE
  local val="$1" msg="$2"
  if [ -n "$val" ]; then
    pass "$msg"
  else
    fail "$msg (valor vacio)"
  fi
}

assert_contains() {  # assert_contains CADENA SUBCADENA MENSAJE
  local hay="$1" needle="$2" msg="$3"
  case "$hay" in
    *"$needle"*) pass "$msg" ;;
    *)           fail "$msg ('$needle' no esta en la salida)" ;;
  esac
}

# --- binarios ---------------------------------------------------------------
require_binaries() {
  if [ ! -x "$SERVER" ] || [ ! -x "$CLIENT" ]; then
    info "Compilando binarios (make server client)..."
    ( cd "$ROOT" && make server client ) >/dev/null || {
      echo "error: no se pudieron compilar los binarios" >&2; exit 1; }
  fi
}

# --- anillo -----------------------------------------------------------------
# start_ring [N] [BASE_PORT]
#   Levanta un anillo de N procesos independientes (uno por puerto), cada uno con
#   su propio log. El nodo bootstrap usa `create` (lee ADDR/PORT del entorno); el
#   resto usa `join ... --addr --port`. Las vars AUTOMATIONSCRIPT / AUTOMATIONINTERPRETER
#   / NETMIKO_* que esten exportadas se heredan a cada nodo (para el exp. de automatizacion).
start_ring() {
  local n="${1:-$N}" base="${2:-$BASE_PORT}"
  RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/chord-exp.XXXXXX")"
  KILLED=()
  : > "$RUNDIR/nodes.txt"

  info "Levantando anillo de $n nodos (puertos $base..$((base+n-1)))"
  note "logs y PIDs en $RUNDIR"

  # nodo 0: bootstrap
  ADDR=127.0.0.1 PORT="$base" nohup "$SERVER" create \
      >"$RUNDIR/node-$base.log" 2>&1 &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$base $pid" >> "$RUNDIR/nodes.txt"
  sleep 1

  # nodos 1..n-1: join
  local i port
  for (( i=1; i<n; i++ )); do
    port=$((base+i))
    nohup "$SERVER" join 127.0.0.1 "$base" --addr 127.0.0.1 --port "$port" \
        >"$RUNDIR/node-$port.log" 2>&1 &
    pid=$!
    disown "$pid" 2>/dev/null || true
    echo "$port $pid" >> "$RUNDIR/nodes.txt"
    sleep 0.3
  done

  wait_ring
}

# alive_ports: imprime (uno por linea) los puertos de nodos que siguen vivos
# (los de nodes.txt menos los que matamos con kill_node).
alive_ports() {
  local port pid k skip
  while read -r port pid; do
    skip=0
    for k in "${KILLED[@]:-}"; do [ "$k" = "$port" ] && skip=1; done
    [ "$skip" = "0" ] && echo "$port"
  done < "$RUNDIR/nodes.txt"
}

# _owner_snapshot KEYS...: imprime el "mapa de duenos" de esas claves visto desde
# CADA nodo vivo (clave@nodo=dueno ...). Si el anillo aun se mueve o los nodos
# discrepan, el snapshot cambia entre muestras; cuando deja de cambiar, convergio.
# Nota: al arrancar, todos los nodos creen que el bootstrap es dueno de todo (sus
# finger tables aun no se poblaron); esa es una "falsa convergencia" transitoria.
# Por eso wait_ring exige que el snapshot se mantenga ESTABLE varias muestras y
# tras un WARMUP inicial que salta ese transitorio.
_owner_snapshot() {
  local ports; ports=$(alive_ports)
  [ -n "$ports" ] || { echo ""; return; }
  local k p o out=""
  for k in "$@"; do
    for p in $ports; do
      o=$(owner_port "$k" "$p")
      [ -n "$o" ] || { echo ""; return; }   # nodo cayendose: fuerza reintento
      out="$out ${k}@${p}=${o}"
    done
  done
  echo "$out"
}

# wait_ring: espera a que el anillo se estabilice. Salta el transitorio inicial
# (WARMUP) y luego exige que el mapa de duenos sea IDENTICO durante STABLE_SAMPLES
# muestras seguidas, o hasta agotar WAIT_MAX. Se usa al levantar el anillo y tras
# matar un nodo (failover).
wait_ring() {
  local probes=(alpha bravo charlie delta echo foxtrot golf hotel)
  local need="${STABLE_SAMPLES:-3}" warmup="${WARMUP:-5}"
  info "Esperando estabilizacion del anillo (warmup ${warmup}s, max ${WAIT_MAX}s)"
  sleep "$warmup"
  local deadline=$(( SECONDS + WAIT_MAX )) stable=0 prev="__none__" snap
  while [ "$SECONDS" -lt "$deadline" ]; do
    snap="$(_owner_snapshot "${probes[@]}")"
    if [ -n "$snap" ] && [ "$snap" = "$prev" ]; then
      stable=$(( stable + 1 ))
      [ "$stable" -ge "$need" ] && { note "anillo estable"; return 0; }
    else
      stable=0
    fi
    prev="$snap"
    sleep 1.5
  done
  note "aviso: se agoto WAIT_MAX (${WAIT_MAX}s) sin estabilidad total; continuo igual"
}

# stop_ring: mata todos los nodos de la corrida y limpia. Idempotente.
stop_ring() {
  [ -n "$RUNDIR" ] || return 0
  if [ -f "$RUNDIR/nodes.txt" ]; then
    local port pid
    while read -r port pid; do
      [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true
    done < "$RUNDIR/nodes.txt"
  fi
  rm -rf "$RUNDIR" 2>/dev/null || true
  RUNDIR=""
}

# --- cliente ----------------------------------------------------------------
# client PORT SUBCMD...   -> habla con el nodo en 127.0.0.1:PORT (via ADDR env)
client() {
  local port="$1"; shift
  ADDR="127.0.0.1:$port" "$CLIENT" "$@" 2>&1
}

# get_value KEY [PORT]  -> imprime el valor devuelto por `get` (parsea la salida logrus)
get_value() {
  local key="$1" port="${2:-$BASE_PORT}"
  client "$port" get "$key" | sed -n 's/.* --> //p' | sed 's/"$//' | head -n1
}

# owner_port KEY [PORT]  -> imprime el puerto del nodo dueno de KEY (via `locate`)
owner_port() {
  local key="$1" port="${2:-$BASE_PORT}"
  client "$port" locate "$key" | grep -oE 'port: [0-9]+' | grep -oE '[0-9]+' | head -n1
}

# get_expect KEY WANT [PORT] [MAXSECS]: reintenta get(KEY) via PORT hasta leer WANT
# o agotar MAXSECS (util tras un failover, cuando el nuevo dueno tarda en promover
# la replica). Imprime el ultimo valor leido; devuelve 0 si coincidio, 1 si no.
get_expect() {
  local key="$1" want="$2" port="${3:-$BASE_PORT}" max="${4:-25}"
  local deadline=$(( SECONDS + max )) got=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    got="$(get_value "$key" "$port")"
    [ "$got" = "$want" ] && { echo "$got"; return 0; }
    sleep 2
  done
  echo "$got"; return 1
}

# --- fallos -----------------------------------------------------------------
# kill_node PORT: mata el proceso del nodo en PORT y lo marca como caido.
kill_node() {
  local target="$1" port pid
  while read -r port pid; do
    if [ "$port" = "$target" ]; then
      kill "$pid" 2>/dev/null || true
      KILLED+=("$target")
      note "nodo en puerto $target (pid $pid) terminado"
      return 0
    fi
  done < "$RUNDIR/nodes.txt"
  fail "kill_node: no encontre un nodo en el puerto $target"
}

# a_survivor_other_than PORT: imprime el puerto de un nodo vivo distinto de PORT.
a_survivor_other_than() {
  local avoid="$1" port pid k skip
  while read -r port pid; do
    [ "$port" = "$avoid" ] && continue
    skip=0
    for k in "${KILLED[@]:-}"; do [ "$k" = "$port" ] && skip=1; done
    [ "$skip" = "1" ] && continue
    echo "$port"; return 0
  done < "$RUNDIR/nodes.txt"
}

# limpieza garantizada aunque un assert aborte el experimento
trap stop_ring EXIT
