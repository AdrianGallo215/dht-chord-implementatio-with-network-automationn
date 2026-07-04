# Scripts

Este directorio contiene todos los scripts de automatización, construcción y despliegue del proyecto Chord DHT.

## Estructura

```
scripts/
├── experiments/         # Suite de experimentos de correctitud del anillo
│   ├── lib.sh          # Primitivas compartidas (levantar/tumbar anillo, aserciones)
│   ├── 01..04-*.sh     # Un experimento por archivo
│   ├── run-all.sh      # Corre todos y muestra resumen PASS/FAIL
│   ├── mock-runner.py  # Runner de automatización simulado (sin hardware)
│   └── README.md       # Qué demuestra cada experimento y cómo correrlos
├── build/              # Scripts de construcción
│   ├── build.sh        # Compilación de todos los binarios
│   └── README.md       # Documentación de construcción
└── deployment/         # Scripts de despliegue en Google Cloud
    ├── setup-vm.sh     # Configuración inicial de VMs
    ├── vm-scripts/     # Scripts específicos por VM
    └── README.md       # Documentación de despliegue
```

## Uso Rápido

### Compilar Proyecto
```bash
./scripts/build/build.sh
```

### Correr los experimentos (demostración)
```bash
./scripts/experiments/run-all.sh            # todo (automatización contra el dispositivo real)
MODE=mock ./scripts/experiments/run-all.sh  # todo sin hardware
```

### Configurar VM de Google Cloud
```bash
./scripts/deployment/setup-vm.sh
```

Cada subdirectorio contiene su propio README.md con instrucciones detalladas.