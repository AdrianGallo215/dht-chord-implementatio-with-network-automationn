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
start_ring

info "Experimento 3: replicacion y tolerancia a fallos"

# guardar varias claves (via el bootstrap; el put ya replica a la successor list)
declare -A expected
expected[db-primary]="datos-criticos-1"
expected[db-replica]="datos-criticos-2"
expected[cache-node]="datos-criticos-3"
expected[edge-gw]="datos-criticos-4"
expected[core-sw]="datos-criticos-5"
for k in "${!expected[@]}"; do
  client "$BASE_PORT" put "$k" "${expected[$k]}" >/dev/null
done

# La replicacion es eventual: se propaga a la successor list en las rondas
# periodicas de estabilizacion, no de forma sincrona con el put. Damos tiempo a
# que las replicas queden en su sitio ANTES de provocar el fallo.
REPLICATION_SETTLE="${REPLICATION_SETTLE:-12}"
info "Esperando a que la replicacion se asiente (${REPLICATION_SETTLE}s)"
sleep "$REPLICATION_SETTLE"

# elegir una clave y matar a su nodo dueno (sea quien sea, incluido el bootstrap:
# tras el join ningun nodo tiene rol especial). El cliente leera desde OTRO nodo
# superviviente, asi que el unico requisito es contacto != victima.
victim_key="db-primary"
victim_port="$(owner_port "$victim_key" "$BASE_PORT")"
reader="$(a_survivor_other_than "$victim_port")"

want="${expected[$victim_key]}"
note "clave victima: '$victim_key' (valor '$want'), dueno = nodo $victim_port"
note "el cliente leera desde el nodo superviviente $reader"

# baseline: se lee bien antes del fallo (desde el superviviente)
got_before="$(get_value "$victim_key" "$reader")"
assert_eq "$got_before" "$want" "get('$victim_key') funciona ANTES de matar al dueno"

# matar al nodo dueno
info "Matando al nodo dueno (puerto $victim_port)"
kill_node "$victim_port"

# el nuevo dueno tarda unos segundos en detectar la caida y promover la replica:
# reintentamos la lectura desde el superviviente durante una ventana.
info "Esperando el failover (reintentando la lectura hasta ${FAILOVER_WAIT:-25}s)"
got_after="$(get_expect "$victim_key" "$want" "$reader" "${FAILOVER_WAIT:-25}")"
assert_eq "$got_after" "$want" "get('$victim_key') SIGUE devolviendo el valor tras la caida del dueno"

info "Experimento 3 OK — el dato sobrevivio a la caida de su nodo dueno"
