# Chord DHT + Network Automation

Una tabla hash distribuida (DHT) con el protocolo Chord, implementada en Go con gRPC, extendida
para que cada nodo del anillo también pueda ejecutar comandos de automatización de red (Netmiko)
contra dispositivos Cisco.


## Estructura del repo

```
.
├── *.go                    # Núcleo del DHT: lookup, replicación, RPC, Run (paquete "chord")
├── chordpb/                # Definiciones y código generado de gRPC/protobuf
├── server/                 # CLI del servidor (crear/unir nodos al anillo)
├── client/                 # CLI del cliente (put/get/locate/run)
├── network-automation/      # Script Netmiko + Dockerfile/compose para el subsistema de automatización
├── scripts/                 # Build, despliegue en GCP, demos y análisis de resultados
└── Dockerfile               # Imagen del nodo Chord (Go + python3/netmiko)
```

## Requisitos

- Go 1.21 o superior.
- Para la función `run` (automatización de red): `python3` y el paquete `netmiko` instalados
  donde corra el nodo.
- Para regenerar los `.proto` (opcional, solo si los modificas): `protoc` + los plugins que indica
  `gen_pb.sh`.

## Compilar

```bash
make server      # genera server/chord
make client      # genera client/chord
```

## Configurar

### Servidor — `server/config.yaml`
```yaml
addr: 127.0.0.1
port: 8001
logging: false
```

### Cliente — `client/config.yaml`
```yaml
addr: 127.0.0.1:8001   # nodo del anillo al que se conecta el cliente
```

## Levantar el anillo

Crear el primer nodo (arranca un anillo nuevo):
```bash
./server/chord create
```

Unir un nodo nuevo a un anillo existente:
```bash
./server/chord join <ip> <puerto>
```

Levantar N nodos de una vez (útil para pruebas locales):
```bash
./server/chord join-n-nodes 4
```

Todos aceptan `--addr` / `--port` para sobreescribir la config.

## Usar el cliente

```bash
./client/chord put <clave> <valor>              # guarda un par clave-valor
./client/chord get <clave>                      # lee un valor
./client/chord locate <clave>                   # muestra qué nodo es dueño de la clave (debug)
./client/chord run <dispositivo> <comando>      # ejecuta <comando> en <dispositivo> vía la DHT
```

`run` enruta la petición al nodo dueño de `hash(dispositivo)`, que ejecuta el comando por SSH
(Netmiko) y cachea el resultado en el mismo almacén replicado que usan `put`/`get` — si luego
haces `get <dispositivo>`, obtienes la última salida cacheada.

## Automatización de red (`network-automation/`)

Ese directorio contiene `netmiko-runner.py` (el script que ejecuta los comandos SSH) y su propio
`Dockerfile`/`docker-compose.yml` para levantar el anillo en contenedores. Las credenciales viven
en `network-automation/.env` (variables `NETMIKO_*`) y nunca viajan por la red Chord — cada nodo
las lee de su propio entorno.

## Tests

```bash
make test          # go test -v (paquete raíz)
go test ./... -v   # todos los paquetes
```

## Scripts adicionales

`scripts/` contiene herramientas adicionales, cada una con su propio README: 
- `scripts/build/` : build
alternativo
- `scripts/deployment/` :despliegue para VMs de Cloud
- `scripts/automation/` :demos y
experimentos de escalabilidad 
- `scripts/analysis/` :post-procesa resultados de experimentos
