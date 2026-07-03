#!/bin/bash

uso() {
    echo "Uso: $0 -n <número_de_nodos> -ip <direccion_ip>"
    echo "Ejemplo: $0 -n 4 -ip 192.168.1.10"
    exit 1
}

N=0
IP=""
PUERTO_BASE=8000

while getopts "n:i:" opt; do
    case ${opt} in
        n) N=$OPTARG ;;
        i) IP=$OPTARG ;;
        *) uso ;;
    esac
done

if [ $N -le 0 ] || [ -z "$IP" ]; then
    echo "Error: Faltan los flags -n o -ip o el número de nodos es inválido."
    uso
fi

echo "--- Iniciando $N nodos Chord en $IP ---"

./server/chord init --addr "$IP" --port $PUERTO_BASE &

for i in $(seq 1 $((N - 1))); do
    NUEVO_PUERTO=$((PUERTO_BASE + i))
    COMANDO="./server/chord join $IP $PUERTO_BASE --addr $IP --port $NUEVO_PUERTO"
    echo "Nodo $((i + 1)): $COMANDO"
    $COMANDO &
    sleep 0.5
done

echo "--- Todos los $N nodos se están iniciando. ---"
