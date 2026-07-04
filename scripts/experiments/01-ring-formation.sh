#!/usr/bin/env bash
#
# Experimento 1 — Formacion del anillo y enrutamiento (consistent hashing).
#
# Que demuestra: que N nodos forman un anillo consistente y que cada clave se
# enruta siempre al mismo nodo dueno sin importar a que nodo le preguntes
# (correctitud del lookup / consistent hashing).

source "$(dirname "$0")/lib.sh"

require_binaries
start_ring

info "Experimento 1: formacion del anillo y enrutamiento"

keys=(alpha bravo charlie delta echo foxtrot golf hotel)
declare -A owner_of
owners_seen=""

# (a) cada clave tiene un dueno; recolectamos que puertos aparecen como dueno
for k in "${keys[@]}"; do
  p="$(owner_port "$k")"
  assert_nonempty "$p" "locate('$k') devuelve un nodo dueno (puerto $p)"
  owner_of["$k"]="$p"
  case "$owners_seen" in *" $p "*) : ;; *) owners_seen="$owners_seen $p " ;; esac
done

distinct=$(echo $owners_seen | wc -w)
note "las $((${#keys[@]})) claves se reparten entre $distinct nodo(s) distinto(s)"
if [ "$distinct" -ge 2 ]; then
  pass "las claves se distribuyen entre varios nodos (no todo cae en uno)"
else
  note "aviso: todas las claves cayeron en el mismo nodo (posible con pocas claves/nodos)"
fi

# (b) consistencia: el dueno de una clave es el mismo preguntando desde otro nodo
probe_key="charlie"
from_bootstrap="${owner_of[$probe_key]}"
other="$(a_survivor_other_than "$BASE_PORT")"
from_other="$(owner_port "$probe_key" "$other")"
assert_eq "$from_other" "$from_bootstrap" \
  "locate('$probe_key') coincide preguntando al bootstrap y al nodo $other"

info "Experimento 1 OK"
