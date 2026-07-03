#!/bin/bash

# Script de demostración para Chord DHT
# Ejecuta una demostración completa del sistema localmente

set -e

DEMO_DIR="demo_results"
BOOTSTRAP_PORT=8000
NODE_PORTS=(8001 8002)

echo "=== DEMOSTRACIÓN CHORD DHT ==="
echo "Esta demostración ejecutará:"
echo "1. Un nodo bootstrap en puerto $BOOTSTRAP_PORT"
echo "2. Dos nodos adicionales en puertos ${NODE_PORTS[*]}"
echo "3. Un simulador con múltiples nodos"
echo "4. Análisis de resultados"
echo ""

# Verificar que los binarios existen
if [ ! -f "bin/chord-server" ] || [ ! -f "bin/chord-client" ] || [ ! -f "bin/chord-simulator" ]; then
    echo "Compilando proyecto..."
    ./build.sh
fi

# Crear directorio de demostración
rm -rf $DEMO_DIR
mkdir -p $DEMO_DIR

echo "Iniciando nodos..."

# Función para matar procesos al salir
cleanup() {
    echo ""
    echo "Cerrando nodos..."
    pkill -f "chord-server" || true
    wait
    echo "Demostración terminada."
}
trap cleanup EXIT

# 1. Iniciar nodo bootstrap
echo "1. Iniciando nodo bootstrap en puerto $BOOTSTRAP_PORT..."
./bin/chord-server create --addr 127.0.0.1 --port $BOOTSTRAP_PORT --metrics --metrics-dir $DEMO_DIR/bootstrap &
BOOTSTRAP_PID=$!
sleep 3

# 2. Iniciar nodos adicionales
for port in "${NODE_PORTS[@]}"; do
    echo "2. Iniciando nodo en puerto $port..."
    ./bin/chord-server join 127.0.0.1 $BOOTSTRAP_PORT --addr 127.0.0.1 --port $port --metrics --metrics-dir $DEMO_DIR/node_$port &
    sleep 2
done

echo "3. Esperando estabilización del ring..."
sleep 10

# 3. Probar cliente
echo "4. Probando operaciones básicas con cliente..."
echo "   - Guardando clave 'test_key' = 'Hello Chord!'"
echo "Hello Chord!" | ./bin/chord-client put 127.0.0.1:$BOOTSTRAP_PORT test_key

echo "   - Recuperando clave 'test_key'"
RESULT=$(./bin/chord-client get 127.0.0.1:$BOOTSTRAP_PORT test_key)
echo "   - Resultado: $RESULT"

# 4. Ejecutar simulador pequeño
echo "5. Ejecutando simulador con 10 nodos por 30 segundos..."
./bin/chord-simulator \
    -nodes 10 \
    -start-port 8010 \
    -bootstrap-addr 127.0.0.1 \
    -bootstrap-port $BOOTSTRAP_PORT \
    -duration 30s \
    -output $DEMO_DIR/simulator \
    -lookup-interval 1s \
    -keyspace 100

echo "6. Esperando finalización de métricas..."
sleep 5

echo ""
echo "=== RESULTADOS DE LA DEMOSTRACIÓN ==="

# Mostrar archivos generados
echo "Archivos de métricas generados:"
find $DEMO_DIR -name "*.csv" | sort

echo ""
echo "Resumen de métricas:"

# Leer métricas del simulador si existe
if [ -f "$DEMO_DIR/simulator/global_metrics.csv" ]; then
    echo "Métricas del simulador:"
    tail -n 1 $DEMO_DIR/simulator/global_metrics.csv | while IFS=',' read timestamp nodes messages lookups latency; do
        echo "  - Nodos totales: $nodes"
        echo "  - Mensajes enviados: $messages"  
        echo "  - Lookups realizados: $lookups"
        echo "  - Latencia promedio: ${latency}ms"
    done
fi

# Contar archivos de nodos individuales
NODE_COUNT=$(find $DEMO_DIR -name "node_*_metrics.csv" | wc -l)
echo "  - Nodos individuales con métricas: $NODE_COUNT"

echo ""
echo "Para análizar los resultados ejecuta:"
echo "  python analyze_results.py $DEMO_DIR"

echo ""
echo "Archivos de demostración guardados en: $DEMO_DIR/"

echo ""
echo "=== DEMOSTRACIÓN COMPLETADA EXITOSAMENTE ==="