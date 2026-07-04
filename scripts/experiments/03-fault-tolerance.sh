#!/usr/bin/env bash
#
# Experimento 3 — Replicacion y tolerancia a fallos (el experimento estrella).
#
# Que demuestra: que los datos sobreviven a la caida del nodo dueno. Se guardan
# claves, se mata el proceso del nodo dueno de una de ellas y, tras la
# re-estabilizacion del anillo, el valor se sigue pudiendo leer desde un nodo
# superviviente (prueba la replicacion a la successor list + el failover).
#
# Limite: mata 1 nodo, dentro de SuccessorListSize=2. Matar >=2 consecutivos
# podria perder datos (limite teorico de la config actual).

source "$(dirname "$0")/lib.sh"

require_binaries
# necesitamos margen para la reconciliacion de la successor list y moveReplicas
WAIT_STABILIZE="${WAIT_STABILIZE:-5}"
start_ring

info "Experimento 3: replicacion y tolerancia a fallos"

# leeremos SIEMPRE desde el bootstrap (nunca lo matamos), asi el cliente
# tiene un punto de contacto estable.
reader="$BASE_PORT"

# guardar varias claves
declare -A expected
expected[db-primary]="datos-criticos-1"
expected[db-replica]="datos-criticos-2"
expected[cache-node]="datos-criticos-3"
expected[edge-gw]="datos-criticos-4"
expected[core-sw]="datos-criticos-5"
for k in "${!expected[@]}"; do
  client "$reader" put "$k" "${expected[$k]}" >/dev/null
done
sleep 1

# elegir una clave cuyo dueno NO sea el bootstrap (para poder matar al dueno
# sin tumbar nuestro nodo de contacto)
victim_key=""; victim_port=""
for k in "${!expected[@]}"; do
  op="$(owner_port "$k" "$reader")"
  if [ -n "$op" ] && [ "$op" != "$BASE_PORT" ]; then
    victim_key="$k"; victim_port="$op"; break
  fi
done

if [ -z "$victim_key" ]; then
  note "aviso: el bootstrap resulto dueno de todas las claves; sube N para repartir mas."
  note "no hay un nodo-dueno matable sin tumbar el contacto; se omite el corte."
  info "Experimento 3 OK (sin caso de fallo aplicable en esta corrida)"
  exit 0
fi

want="${expected[$victim_key]}"
note "clave victima: '$victim_key' (valor '$want'), dueno = nodo $victim_port"

# baseline: se lee bien antes del fallo
got_before="$(get_value "$victim_key" "$reader")"
assert_eq "$got_before" "$want" "get('$victim_key') funciona ANTES de matar al dueno"

# matar al nodo dueno
info "Matando al nodo dueno (puerto $victim_port)"
kill_node "$victim_port"

info "Esperando re-estabilizacion del anillo (${WAIT_STABILIZE}s)"
sleep "$WAIT_STABILIZE"

# el dato debe seguir disponible desde un superviviente (replica + failover)
got_after="$(get_value "$victim_key" "$reader")"
assert_eq "$got_after" "$want" "get('$victim_key') SIGUE devolviendo el valor tras la caida del dueno"

info "Experimento 3 OK — el dato sobrevivio a la caida de su nodo dueno"
