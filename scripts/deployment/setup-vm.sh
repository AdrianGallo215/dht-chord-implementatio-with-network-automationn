#!/bin/bash

# Script de configuración para VMs de Google Cloud
# Ejecutar este script en cada VM después de crear las instancias

set -e

echo "=== Configurando VM para Chord DHT ==="

# Actualizar sistema
sudo apt update
sudo apt upgrade -y

# Instalar Go
echo "Instalando Go..."
wget https://golang.org/dl/go1.19.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
source ~/.bashrc

# Verificar instalación de Go
/usr/local/go/bin/go version

# Crear directorio de trabajo
mkdir -p ~/chord-project
cd ~/chord-project

# Instalar git si no está instalado
sudo apt install -y git

# Nota: El usuario debe clonar su repositorio aquí
echo "Clona tu repositorio con:"
echo "git clone [TU_REPO_URL] ."

# Configurar firewall
echo "Configurando firewall..."
sudo ufw allow 8000:8100/tcp
sudo ufw --force enable

# Crear directorios para métricas y resultados
mkdir -p results metrics

# Crear script helper para compilar
cat > compile.sh << 'EOF'
#!/bin/bash
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export GOROOT=/usr/local/go

echo "Compilando proyecto Chord..."
go mod tidy
go build -o chord-server ./server
go build -o chord-client ./client  
go build -o chord-simulator ./cmd/simulator
echo "Compilación completada."
EOF

chmod +x compile.sh

# Crear script para ejecutar bootstrap
cat > run-bootstrap.sh << 'EOF'
#!/bin/bash
export PATH=$PATH:/usr/local/go/bin

# Obtener IP externa
EXTERNAL_IP=$(curl -s ifconfig.me)
echo "IP Externa: $EXTERNAL_IP"

# Ejecutar servidor bootstrap con métricas
./chord-server create --addr 0.0.0.0 --port 8000 --metrics --metrics-dir results/bootstrap
EOF

chmod +x run-bootstrap.sh

# Crear script para unirse al ring
cat > run-join.sh << 'EOF'
#!/bin/bash
export PATH=$PATH:/usr/local/go/bin

if [ $# -ne 1 ]; then
    echo "Uso: $0 <IP_BOOTSTRAP>"
    echo "Ejemplo: $0 34.123.45.67"
    exit 1
fi

BOOTSTRAP_IP=$1

# Obtener IP externa propia
EXTERNAL_IP=$(curl -s ifconfig.me)
echo "Mi IP Externa: $EXTERNAL_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"

# Ejecutar servidor join con métricas
./chord-server join $BOOTSTRAP_IP 8000 --addr 0.0.0.0 --port 8000 --metrics --metrics-dir results/node
EOF

chmod +x run-join.sh

# Crear script para simulador
cat > run-simulator.sh << 'EOF'
#!/bin/bash
export PATH=$PATH:/usr/local/go/bin

if [ $# -lt 2 ]; then
    echo "Uso: $0 <BOOTSTRAP_IP> <NUM_NODES> [DURATION] [OUTPUT_DIR]"
    echo "Ejemplo: $0 34.123.45.67 20 300s vm1_exp"
    exit 1
fi

BOOTSTRAP_IP=$1
NUM_NODES=$2
DURATION=${3:-300s}
OUTPUT_DIR=${4:-simulator_results}

echo "Ejecutando simulador con $NUM_NODES nodos por $DURATION"
echo "Bootstrap: $BOOTSTRAP_IP"
echo "Resultados en: results/$OUTPUT_DIR"

./chord-simulator \
    -nodes $NUM_NODES \
    -start-port 8001 \
    -bootstrap-addr $BOOTSTRAP_IP \
    -bootstrap-port 8000 \
    -duration $DURATION \
    -output results/$OUTPUT_DIR \
    -lookup-interval 1s \
    -keyspace 1000
EOF

chmod +x run-simulator.sh

# Crear script para recolectar resultados
cat > collect-results.sh << 'EOF'
#!/bin/bash

echo "Recolectando resultados..."

# Crear archivo tar con todos los resultados
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
RESULTS_FILE="chord_results_${HOSTNAME}_${TIMESTAMP}.tar.gz"

tar -czf $RESULTS_FILE results/ metrics/

echo "Resultados guardados en: $RESULTS_FILE"
echo "Descarga con: scp user@ip:~/$RESULTS_FILE ."
EOF

chmod +x collect-results.sh

echo "=== Configuración completada ==="
echo ""
echo "Pasos siguientes:"
echo "1. Clona tu repositorio: git clone [REPO_URL] ."
echo "2. Compila el proyecto: ./compile.sh"
echo "3. Para VM bootstrap: ./run-bootstrap.sh"
echo "4. Para otras VMs: ./run-join.sh <IP_BOOTSTRAP>"
echo "5. Para simulador: ./run-simulator.sh <IP_BOOTSTRAP> <NUM_NODES>"
echo "6. Recolectar resultados: ./collect-results.sh"
echo ""
echo "Archivos de configuración creados:"
echo "- compile.sh: Compila el proyecto"
echo "- run-bootstrap.sh: Ejecuta nodo bootstrap"
echo "- run-join.sh: Une nodo al ring"
echo "- run-simulator.sh: Ejecuta simulador"
echo "- collect-results.sh: Recolecta resultados"