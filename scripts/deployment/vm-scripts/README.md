# Scripts de Configuración para VMs

## setup-vm.sh - Script para instalar dependencias
```bash
#!/bin/bash

echo "=== Configurando VM para Chord DHT ==="

# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependencias básicas
sudo apt install -y wget curl git build-essential

# Instalar Go 1.21
echo "Instalando Go 1.21..."
GO_VERSION="1.21.5"
wget https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go 
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

# Configurar PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc

# Verificar instalación
/usr/local/go/bin/go version

echo "=== VM configurada correctamente ==="
```

## quick-start-vm1.sh - Bootstrap Node (España)
```bash
#!/bin/bash

echo "=== Iniciando Bootstrap Node VM1 (España) ==="

cd ~/chord

# Crear directorios
mkdir -p results/metrics/vm1_bootstrap
mkdir -p results/logs

# Compilar si es necesario
echo "Compilando proyecto..."
go mod tidy
go build -o bin/chord-server ./server
go build -o bin/chord-client ./client  
go build -o bin/chord-simulator ./cmd/simulator

# Iniciar bootstrap node
echo "Iniciando bootstrap node en 34.38.96.126:8000..."
./bin/chord-server create \
    --addr 0.0.0.0 \
    --port 8000 \
    --metrics \
    --metrics-dir results/metrics/vm1_bootstrap \
    --log-level info \
    > results/logs/vm1_bootstrap.log 2>&1 &

BOOTSTRAP_PID=$!
echo $BOOTSTRAP_PID > vm1_bootstrap.pid

echo "Bootstrap node iniciado con PID: $BOOTSTRAP_PID"
echo "Logs: tail -f results/logs/vm1_bootstrap.log"
echo "Métricas: ls results/metrics/vm1_bootstrap/"

# Esperar que se inicialice
echo "Esperando 10 segundos para inicialización..."
sleep 10

# Verificar que está corriendo
if ps -p $BOOTSTRAP_PID > /dev/null; then
    echo "✓ Bootstrap node está corriendo correctamente"
    echo "✓ Listo para que otros nodos se conecten"
else
    echo "✗ Error: Bootstrap node no está corriendo"
    cat results/logs/vm1_bootstrap.log | tail -20
fi
```

## quick-start-vm2.sh - Join Node (US Central)
```bash
#!/bin/bash

echo "=== Iniciando Node VM2 (US Central) ==="

cd ~/chord

# Crear directorios
mkdir -p results/metrics/vm2_node
mkdir -p results/logs

# Compilar si es necesario
echo "Compilando proyecto..."
go mod tidy
go build -o bin/chord-server ./server
go build -o bin/chord-client ./client
go build -o bin/chord-simulator ./cmd/simulator

# Verificar conectividad con bootstrap
echo "Verificando conectividad con bootstrap (34.38.96.126:8000)..."
if timeout 10 bash -c "</dev/tcp/34.38.96.126/8000"; then
    echo "✓ Conectividad con bootstrap OK"
else
    echo "✗ No se puede conectar con bootstrap"
    echo "Verificar que VM1 esté corriendo y firewall configurado"
    exit 1
fi

# Iniciar nodo para unirse al ring
echo "Uniéndose al ring via 34.38.96.126:8000..."
./bin/chord-server join 34.38.96.126 8000 \
    --addr 0.0.0.0 \
    --port 8000 \
    --metrics \
    --metrics-dir results/metrics/vm2_node \
    --log-level info \
    > results/logs/vm2_node.log 2>&1 &

NODE_PID=$!
echo $NODE_PID > vm2_node.pid

echo "Nodo VM2 iniciado con PID: $NODE_PID"
echo "Logs: tail -f results/logs/vm2_node.log"

# Esperar y verificar
sleep 15

if ps -p $NODE_PID > /dev/null; then
    echo "✓ Nodo VM2 está corriendo"
    echo "✓ IP: 35.199.69.216:8000"
else
    echo "✗ Error: Nodo VM2 no está corriendo"
    cat results/logs/vm2_node.log | tail -20
fi
```

## quick-start-vm3.sh - Join Node (US East)
```bash
#!/bin/bash

echo "=== Iniciando Node VM3 (US East) ==="

cd ~/chord

# Crear directorios
mkdir -p results/metrics/vm3_node
mkdir -p results/logs

# Compilar si es necesario
echo "Compilando proyecto..."
go mod tidy
go build -o bin/chord-server ./server
go build -o bin/chord-client ./client
go build -o bin/chord-simulator ./cmd/simulator

# Verificar conectividad con bootstrap
echo "Verificando conectividad con bootstrap (34.38.96.126:8000)..."
if timeout 10 bash -c "</dev/tcp/34.38.96.126/8000"; then
    echo "✓ Conectividad con bootstrap OK"
else
    echo "✗ No se puede conectar con bootstrap"
    echo "Verificar que VM1 esté corriendo y firewall configurado"
    exit 1
fi

# Iniciar nodo para unirse al ring
echo "Uniéndose al ring via 34.38.96.126:8000..."
./bin/chord-server join 34.38.96.126 8000 \
    --addr 0.0.0.0 \
    --port 8000 \
    --metrics \
    --metrics-dir results/metrics/vm3_node \
    --log-level info \
    > results/logs/vm3_node.log 2>&1 &

NODE_PID=$!
echo $NODE_PID > vm3_node.pid

echo "Nodo VM3 iniciado con PID: $NODE_PID"
echo "Logs: tail -f results/logs/vm3_node.log"

# Esperar y verificar
sleep 15

if ps -p $NODE_PID > /dev/null; then
    echo "✓ Nodo VM3 está corriendo"
    echo "✓ IP: 34.58.253.117:8000"
else
    echo "✗ Error: Nodo VM3 no está corriendo"
    cat results/logs/vm3_node.log | tail -20
fi
```

## test-connectivity.sh - Script de pruebas
```bash
#!/bin/bash

echo "=== Test de Conectividad del Ring Chord ==="

VMS=(
    "34.38.96.126:8000"  # VM1 España
    "35.199.69.216:8000" # VM2 US Central  
    "34.58.253.117:8000" # VM3 US East
)

cd ~/chord

echo "1. Probando operaciones PUT/GET básicas..."

# Test 1: PUT desde cada VM
echo "Guardando datos desde cada VM..."
echo "Datos desde España" | ./bin/chord-client put 34.38.96.126:8000 key_spain
echo "Datos desde US Central" | ./bin/chord-client put 35.199.69.216:8000 key_us_central  
echo "Datos desde US East" | ./bin/chord-client put 34.58.253.117:8000 key_us_east

echo "2. Verificando replicación cross-region..."

# Test 2: GET desde todas las VMs
for vm in "${VMS[@]}"; do
    echo "--- Leyendo desde $vm ---"
    ./bin/chord-client get $vm key_spain
    ./bin/chord-client get $vm key_us_central
    ./bin/chord-client get $vm key_us_east
    echo
done

echo "3. Probando localización de claves..."

# Test 3: LOCATE desde diferentes VMs
for key in key_spain key_us_central key_us_east; do
    echo "--- Localizando $key ---"
    for vm in "${VMS[@]}"; do
        echo "Desde $vm:"
        ./bin/chord-client locate $vm $key
    done
    echo
done

echo "4. Test de latencia..."

# Test 4: Medir latencia entre regiones
for i in {1..5}; do
    echo "--- Round $i ---"
    for vm in "${VMS[@]}"; do
        echo "GET desde $vm:"
        time ./bin/chord-client get $vm key_spain 2>/dev/null
    done
    echo
done

echo "=== Tests completados ==="
```

## start-simulators.sh - Iniciar simulaciones
```bash
#!/bin/bash

echo "=== Iniciando Simuladores en todas las VMs ==="

# Obtener IP de la VM actual
VM_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/external-ip -H "Metadata-Flavor: Google")
echo "IP de esta VM: $VM_IP"

# Determinar configuración según la VM
case $VM_IP in
    "34.38.96.126")
        VM_NAME="VM1_España"
        OUTPUT_DIR="results/metrics/vm1_sim_50nodes"
        LOG_FILE="results/logs/vm1_simulator.log"
        ;;
    "35.199.69.216")
        VM_NAME="VM2_US_Central" 
        OUTPUT_DIR="results/metrics/vm2_sim_50nodes"
        LOG_FILE="results/logs/vm2_simulator.log"
        ;;
    "34.58.253.117")
        VM_NAME="VM3_US_East"
        OUTPUT_DIR="results/metrics/vm3_sim_50nodes"
        LOG_FILE="results/logs/vm3_simulator.log"
        ;;
    *)
        echo "IP no reconocida: $VM_IP"
        exit 1
        ;;
esac

echo "Configuración: $VM_NAME"
echo "Output: $OUTPUT_DIR"

cd ~/chord

# Crear directorios
mkdir -p $(dirname $OUTPUT_DIR)
mkdir -p $(dirname $LOG_FILE)

# Iniciar simulador con 50 nodos
echo "Iniciando simulador: 50 nodos por 10 minutos..."
./bin/chord-simulator \
    -nodes 50 \
    -start-port 8001 \
    -bootstrap-addr 34.38.96.126 \
    -bootstrap-port 8000 \
    -duration 600s \
    -output $OUTPUT_DIR \
    > $LOG_FILE 2>&1 &

SIM_PID=$!
echo $SIM_PID > simulator.pid

echo "Simulador iniciado con PID: $SIM_PID"
echo "Logs: tail -f $LOG_FILE"
echo "Métricas: ls $OUTPUT_DIR/"

# Monitoreo
echo "Monitoreando simulador..."
sleep 10

if ps -p $SIM_PID > /dev/null; then
    echo "✓ Simulador corriendo correctamente"
    echo "✓ $VM_NAME: 50 nodos simulados activos"
    echo "✓ Duración: 10 minutos"
else
    echo "✗ Error: Simulador no está corriendo"
    cat $LOG_FILE | tail -20
fi
```

## collect-results.sh - Recolectar resultados
```bash
#!/bin/bash

echo "=== Recolectando Resultados de Experimento ==="

# Obtener información de la VM
VM_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/external-ip -H "Metadata-Flavor: Google")
HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

case $VM_IP in
    "34.38.96.126") VM_NAME="VM1_España" ;;
    "35.199.69.216") VM_NAME="VM2_US_Central" ;;
    "34.58.253.117") VM_NAME="VM3_US_East" ;;
    *) VM_NAME="VM_Unknown" ;;
esac

RESULTS_DIR="chord_results_${VM_NAME}_${TIMESTAMP}"

echo "VM: $VM_NAME ($VM_IP)"
echo "Directorio: $RESULTS_DIR"

cd ~/chord

# Crear directorio de resultados
mkdir -p $RESULTS_DIR

# Copiar métricas y logs
echo "Copiando métricas..."
if [ -d "results/metrics" ]; then
    cp -r results/metrics $RESULTS_DIR/
    echo "✓ Métricas copiadas"
else
    echo "⚠ No se encontraron métricas"
fi

echo "Copiando logs..."
if [ -d "results/logs" ]; then
    cp -r results/logs $RESULTS_DIR/
    echo "✓ Logs copiados"
else
    echo "⚠ No se encontraron logs"
fi

# Información del sistema
echo "Recolectando información del sistema..."
cat > $RESULTS_DIR/system_info.txt << EOF
=== Información del Sistema ===
VM: $VM_NAME
IP Externa: $VM_IP
Hostname: $HOSTNAME  
Fecha: $(date)
Uptime: $(uptime)
Zona: $(curl -s http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | cut -d'/' -f4)

=== Recursos ===
CPU: $(nproc) cores
Memoria: $(free -h | grep Mem | awk '{print $2}')
Disco: $(df -h / | tail -1 | awk '{print $2}')

=== Procesos Chord ===
$(ps aux | grep chord | grep -v grep)

=== Red ===
$(ss -tlnp | grep :800)
EOF

# Estadísticas de archivos
echo "Generando estadísticas..."
find $RESULTS_DIR -name "*.csv" -exec wc -l {} \; > $RESULTS_DIR/file_stats.txt

# Comprimir
echo "Comprimiendo resultados..."
tar -czf ${RESULTS_DIR}.tar.gz $RESULTS_DIR

# Limpiar directorio temporal
rm -rf $RESULTS_DIR

echo "✓ Resultados guardados en: ${RESULTS_DIR}.tar.gz"
echo "✓ Tamaño: $(du -h ${RESULTS_DIR}.tar.gz | cut -f1)"

# Mostrar resumen
echo ""
echo "=== Resumen ==="
echo "Archivo: ${RESULTS_DIR}.tar.gz"
echo "Para descargar desde local:"
echo "gcloud compute scp $HOSTNAME:~/chord/${RESULTS_DIR}.tar.gz ./ --zone=\$(gcloud compute instances list --filter=\"name=$HOSTNAME\" --format=\"value(zone)\")"
```

Guarda estos scripts en cada VM para automatizar el proceso de configuración y pruebas.