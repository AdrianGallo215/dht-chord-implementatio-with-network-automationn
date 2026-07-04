#!/usr/bin/env bash
#
# run-all.sh — corre todos los experimentos en secuencia, cada uno con un anillo
# limpio, e imprime un resumen final PASS/FAIL. Sale con codigo != 0 si alguno falla.
#
# Uso:
#   ./scripts/experiments/run-all.sh            # exp. de automatizacion en MODO REAL
#   MODE=mock ./scripts/experiments/run-all.sh  # todo sin hardware ni credenciales
#   N=8 BASE_PORT=9200 ./scripts/experiments/run-all.sh   # anillo mas grande / otros puertos
#
# Las perillas (N, BASE_PORT, WAIT_STABILIZE, MODE, DEVICE, COMMAND) se heredan
# por el entorno a cada experimento.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; B=$'\033[34m'; O=$'\033[0m'; else G=""; R=""; B=""; O=""; fi

experiments=(
  "01-ring-formation.sh"
  "02-put-get.sh"
  "03-fault-tolerance.sh"
  "04-automation.sh"
)

declare -a results
fails=0

for exp in "${experiments[@]}"; do
  echo
  echo "${B}########################################################################${O}"
  echo "${B}# $exp${O}"
  echo "${B}########################################################################${O}"
  if bash "$DIR/$exp"; then
    results+=("${G}PASS${O}  $exp")
  else
    results+=("${R}FAIL${O}  $exp")
    fails=$((fails+1))
  fi
done

echo
echo "========================================================================"
echo "RESUMEN"
echo "========================================================================"
for r in "${results[@]}"; do
  echo "  $r"
done
echo

if [ "$fails" -eq 0 ]; then
  echo "${G}Todos los experimentos pasaron.${O}"
  exit 0
else
  echo "${R}$fails experimento(s) fallaron.${O}"
  exit 1
fi
