#!/bin/bash

# Makefile alternativo para compilar proyecto Chord
# Uso: ./build.sh [clean|all|server|client|simulator|test]

set -e

export PATH=$PATH:/usr/local/go/bin
export GOROOT=/usr/local/go
export GOPATH=$HOME/go

PROJECT_ROOT=$(pwd)
BIN_DIR="bin"

# Crear directorio de binarios
mkdir -p $BIN_DIR

build_server() {
    echo "Compilando chord-server..."
    go build -o $BIN_DIR/chord-server ./server
    echo "✓ chord-server compilado"
}

build_client() {
    echo "Compilando chord-client..."
    go build -o $BIN_DIR/chord-client ./client
    echo "✓ chord-client compilado"
}

build_simulator() {
    echo "Compilando chord-simulator..."
    go build -o $BIN_DIR/chord-simulator ./cmd/simulator
    echo "✓ chord-simulator compilado"
}

build_all() {
    echo "=== Compilando Proyecto Chord ==="
    
    # Verificar Go
    if ! command -v go &> /dev/null; then
        echo "Error: Go no está instalado o no está en PATH"
        exit 1
    fi
    
    echo "Go version: $(go version)"
    
    # Limpiar y obtener dependencias
    echo "Obteniendo dependencias..."
    go mod tidy
    
    # Compilar todos los componentes
    build_server
    build_client
    build_simulator
    
    echo ""
    echo "=== Compilación Completada ==="
    echo "Binarios disponibles en: $BIN_DIR/"
    ls -la $BIN_DIR/
}

clean() {
    echo "Limpiando archivos de compilación..."
    rm -rf $BIN_DIR
    go clean
    echo "✓ Limpieza completada"
}

run_tests() {
    echo "Ejecutando tests..."
    go test -v ./...
    echo "✓ Tests completados"
}

case "${1:-all}" in
    "clean")
        clean
        ;;
    "server")
        build_server
        ;;
    "client")
        build_client
        ;;
    "simulator")
        build_simulator
        ;;
    "test")
        run_tests
        ;;
    "all"|"")
        build_all
        ;;
    *)
        echo "Uso: $0 [clean|all|server|client|simulator|test]"
        exit 1
        ;;
esac