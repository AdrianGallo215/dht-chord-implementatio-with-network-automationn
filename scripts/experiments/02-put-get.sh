#!/usr/bin/env bash
#
# Experimento 2 — Almacenamiento distribuido (put/get con forwarding).
#
# Que demuestra: que un valor guardado a traves de UN nodo se puede leer a traves
# de OTRO nodo distinto del anillo, aunque ninguno de los dos sea el dueno de la
# clave. Prueba el almacenamiento distribuido + el reenvio (forwarding) de RPC.

source "$(dirname "$0")/lib.sh"

require_binaries
start_ring

info "Experimento 2: put desde un nodo, get desde otro"

declare -A expected
expected[router1]="show-version-cached"
expected[vlan10]="10.0.10.0/24"
expected[site-lima]="peru-datacenter"
expected[config-backup]="hostname R1"

writer="$BASE_PORT"
reader="$(a_survivor_other_than "$BASE_PORT")"
note "escribiendo por el nodo $writer, leyendo por el nodo $reader"

# escribir todas las claves a traves del nodo 'writer'
for k in "${!expected[@]}"; do
  client "$writer" put "$k" "${expected[$k]}" >/dev/null
done
sleep 1

# leer cada clave a traves del nodo 'reader' y comparar
for k in "${!expected[@]}"; do
  got="$(get_value "$k" "$reader")"
  assert_eq "$got" "${expected[$k]}" "get('$k') via nodo $reader devuelve el valor puesto via nodo $writer"
done

info "Experimento 2 OK"
