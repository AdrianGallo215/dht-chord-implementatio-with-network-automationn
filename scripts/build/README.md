# Scripts de Construcción

Este directorio contiene scripts para compilar y construir el proyecto.

## Archivos

### `build.sh`
Script principal de construcción que compila todos los binarios del proyecto:
- `chord-server` - Servidor/nodo del ring Chord
- `chord-client` - Cliente para operaciones GET/PUT/LOCATE  
- `chord-simulator` - Simulador multi-nodo para experimentos

### Uso
```bash
cd scripts/build
./build.sh
```

Los binarios compilados se guardan en `../../bin/`