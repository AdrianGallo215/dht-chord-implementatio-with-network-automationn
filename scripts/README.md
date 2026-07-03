# Scripts

Este directorio contiene todos los scripts de automatización, construcción y despliegue del proyecto Chord DHT.

## Estructura

```
scripts/
├── automation/          # Scripts de demostración y experimentos
│   ├── demo.sh         # Demostración del sistema
│   ├── run-experiments.sh  # Experimentos de escalabilidad
│   └── README.md       # Documentación de automatización
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

### Demostración Local
```bash
./scripts/automation/demo.sh
```

### Configurar VM de Google Cloud
```bash
./scripts/deployment/setup-vm.sh
```

### Experimentos de Escalabilidad
```bash
./scripts/automation/run-experiments.sh
```

Cada subdirectorio contiene su propio README.md con instrucciones detalladas.