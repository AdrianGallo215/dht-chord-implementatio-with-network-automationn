# Scripts de Despliegue

Este directorio contiene todos los scripts necesarios para desplegar el sistema Chord DHT en Google Cloud VMs.

## Estructura

### `setup-vm.sh`
Script principal para configurar una VM nueva:
- Instala Go 1.21
- Configura dependencias del sistema
- Prepara el entorno para Chord DHT

### `vm-scripts/`
Directorio con scripts específicos para cada VM y automatización:
- Scripts de inicio rápido por VM
- Scripts de pruebas de conectividad
- Scripts de recolección de resultados
- Ver `vm-scripts/README.md` para detalles completos

## Uso Rápido

### 1. Configurar VM Nueva
```bash
# En cada VM de Google Cloud
wget https://raw.githubusercontent.com/tu-repo/chord/master/scripts/deployment/setup-vm.sh
chmod +x setup-vm.sh
./setup-vm.sh
```

### 2. Usar Scripts Específicos
```bash
# Ver scripts disponibles para VMs
ls scripts/deployment/vm-scripts/

# Ejecutar script específico
./scripts/deployment/vm-scripts/quick-start-vm1.sh
```

## VMs Configuradas

- **VM1 (Bootstrap)**: `34.38.96.126` - España 🇪🇸
- **VM2**: `35.199.69.216` - US Central 🇺🇸  
- **VM3**: `34.58.253.117` - US East 🇺🇸

Ver `../../docs/DEPLOYMENT_GUIDE.md` para instrucciones completas.