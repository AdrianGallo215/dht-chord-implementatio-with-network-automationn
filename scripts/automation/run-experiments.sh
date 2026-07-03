#!/bin/bash

# Script para ejecutar experimentos de escalabilidad
# Ejecutar desde cada VM después de configurar el ring

set -e

if [ $# -ne 1 ]; then
    echo "Uso: $0 <BOOTSTRAP_IP>"
    echo "Ejemplo: $0 34.123.45.67"
    exit 1
fi

BOOTSTRAP_IP=$1
HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Experimentos de Escalabilidad Chord DHT ==="
echo "VM: $HOSTNAME"
echo "Bootstrap: $BOOTSTRAP_IP"
echo "Timestamp: $TIMESTAMP"

# Función para ejecutar un experimento
run_experiment() {
    local nodes=$1
    local duration=$2
    local exp_name=$3
    
    echo ""
    echo "--- Experimento: $exp_name ---"
    echo "Nodos: $nodes, Duración: $duration"
    
    local output_dir="results/${HOSTNAME}_${exp_name}_${TIMESTAMP}"
    
    echo "Iniciando simulador..."
    ./chord-simulator \
        -nodes $nodes \
        -start-port 8001 \
        -bootstrap-addr $BOOTSTRAP_IP \
        -bootstrap-port 8000 \
        -duration $duration \
        -output $output_dir \
        -lookup-interval 1s \
        -keyspace 1000
        
    echo "Experimento $exp_name completado. Resultados en: $output_dir"
    
    # Pequeña pausa entre experimentos
    sleep 10
}

# Verificar que el simulador esté compilado
if [ ! -f "./chord-simulator" ]; then
    echo "Error: chord-simulator no encontrado. Ejecuta ./compile.sh primero."
    exit 1
fi

# Experimento 1: Pocos nodos (5 nodos, 60 segundos)
run_experiment 5 "60s" "exp1_5nodes"

# Experimento 2: Nodos medianos (15 nodos, 120 segundos)  
run_experiment 15 "120s" "exp2_15nodes"

# Experimento 3: Muchos nodos (30 nodos, 180 segundos)
run_experiment 30 "180s" "exp3_30nodes"

# Experimento 4: Máximo nodos (50 nodos, 300 segundos)
run_experiment 50 "300s" "exp4_50nodes"

echo ""
echo "=== Todos los experimentos completados ==="

# Generar resumen de resultados
echo "Generando resumen de resultados..."

cat > results/experiment_summary_${HOSTNAME}_${TIMESTAMP}.txt << EOF
Resumen de Experimentos de Escalabilidad
========================================
VM: $HOSTNAME
Bootstrap: $BOOTSTRAP_IP  
Fecha: $(date)

Experimentos ejecutados:
1. exp1_5nodes: 5 nodos locales, 60 segundos
2. exp2_15nodes: 15 nodos locales, 120 segundos
3. exp3_30nodes: 30 nodos locales, 180 segundos
4. exp4_50nodes: 50 nodos locales, 300 segundos

Archivos generados por experimento:
- node_*_metrics.csv: Métricas individuales por nodo
- global_metrics.csv: Métricas agregadas del experimento

Métricas registradas:
- timestamp: Marca de tiempo
- nodes: Número de nodos en el ring
- messages: Mensajes enviados  
- lookups: Lookups realizados
- avg_lookup_ms: Latencia promedio de lookup en ms

Para análisis posterior, usar los scripts de Python proporcionados.
EOF

echo "Resumen guardado en: results/experiment_summary_${HOSTNAME}_${TIMESTAMP}.txt"

# Listar todos los archivos de resultados
echo ""
echo "Archivos de resultados generados:"
find results/ -name "*.csv" -o -name "*.txt" | sort

echo ""
echo "Para recolectar todos los resultados ejecuta: ./collect-results.sh"