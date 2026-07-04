# Experimentos — Chord DHT + Automatización de red

Suite de experimentos que demuestran, sobre el CLI real del proyecto, que el sistema
funciona correctamente: forma el anillo, guarda y recupera datos de forma distribuida,
sobrevive a la caída de un nodo, y ejecuta automatización de red enrutada por la DHT.

Cada experimento levanta su propio anillo limpio de nodos locales, hace unas cuantas
aserciones e imprime `PASS`/`FAIL`. Al terminar, limpia todos los procesos que arrancó.

## Cómo correr

```bash
# Todo, de una vez (el exp. de automatización usa el dispositivo real por defecto):
./scripts/experiments/run-all.sh

# Todo sin hardware ni credenciales (el exp. de automatización usa un runner simulado):
MODE=mock ./scripts/experiments/run-all.sh

# Un solo experimento:
./scripts/experiments/03-fault-tolerance.sh
```

Los binarios `server/chord` y `client/chord` se compilan solos si faltan.

## Los experimentos

| Script | Qué demuestra |
| --- | --- |
| `01-ring-formation.sh` | El anillo se forma y es **consistente**: cada clave se enruta siempre al mismo nodo dueño, sin importar a qué nodo le preguntes (consistent hashing / lookup correcto). |
| `02-put-get.sh` | **Almacenamiento distribuido**: un valor guardado a través de un nodo se lee a través de otro nodo distinto (reenvío de RPC entre nodos del anillo). |
| `03-fault-tolerance.sh` | **Replicación y tolerancia a fallos**: se mata el proceso del nodo dueño de una clave y, tras el failover, el valor se sigue leyendo desde un superviviente (la réplica en la successor list toma el relevo). |
| `04-automation.sh` | **Automatización de red sobre la DHT**: `run <dispositivo> <comando>` se enruta al nodo dueño de `hash(dispositivo)`, que ejecuta el comando (SSH/Netmiko) y **cachea** el resultado; un `get <dispositivo>` posterior devuelve esa salida. |

## Requisitos

- **Go** (para compilar los binarios).
- Para `04-automation.sh` en **modo real**: `python3` + `netmiko` instalados, y el archivo
  `network-automation/.env` con las credenciales `NETMIKO_*` del dispositivo. En **modo mock**
  no hace falta nada de eso (usa `mock-runner.py`, que simula la salida sin tocar la red).

## Perillas (variables de entorno)

Todas se heredan por el entorno; sirven para `run-all.sh` y para cada experimento suelto.

| Variable | Default | Descripción |
| --- | --- | --- |
| `N` | `4` | Número de nodos del anillo. |
| `BASE_PORT` | `9100` | Puerto del nodo bootstrap; los demás usan `BASE_PORT+1..` |
| `WAIT_MAX` | `30` | Segundos máximos a esperar la convergencia del anillo. |
| `MODE` | `real` | `04-automation.sh`: `real` (dispositivo de `.env`) o `mock` (sin hardware). |
| `DEVICE` | según modo | Clave/host del dispositivo para el exp. de automatización. |
| `COMMAND` | `show ip interface brief` | Comando a ejecutar en el exp. de automatización. |
| `REPLICATION_SETTLE` | `12` | (exp. 3) segundos de espera para que la réplica se asiente antes de matar al dueño. |
| `FAILOVER_WAIT` | `25` | (exp. 3) ventana de reintento de la lectura tras el fallo. |

Ejemplos:

```bash
N=8 BASE_PORT=9200 ./scripts/experiments/01-ring-formation.sh
MODE=mock COMMAND="show version" ./scripts/experiments/04-automation.sh
```

## Notas y límites

- La **replicación es eventual**: se propaga a la successor list en las rondas periódicas de
  estabilización, no de forma síncrona con el `put`. Por eso el exp. 3 espera `REPLICATION_SETTLE`
  segundos antes de provocar el fallo y reintenta la lectura después.
- El exp. 3 mata **un** nodo, dentro de `SuccessorListSize=2`. Matar ≥2 nodos consecutivos del
  anillo podría perder datos (límite teórico de la configuración actual, no un bug del experimento).
- `run-all.sh` levanta y tumba un anillo limpio por experimento (aislamiento), así que tarda
  algunas decenas de segundos en total.

## Añadir un experimento nuevo

`lib.sh` da las primitivas; un experimento nuevo es sourcearlo y usarlas:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

require_binaries
start_ring                       # levanta N nodos y espera convergencia

client "$BASE_PORT" put foo bar >/dev/null
got="$(get_value foo)"           # lee y parsea el valor
assert_eq "$got" "bar" "put/get de una clave"

# más helpers utiles:
#   owner_port KEY               -> puerto del nodo dueño de KEY
#   kill_node PORT               -> mata ese nodo
#   a_survivor_other_than PORT   -> un nodo vivo distinto de PORT
#   get_expect KEY WANT PORT SEG -> reintenta get hasta leer WANT
#   pass/fail/assert_nonempty/assert_contains

info "Mi experimento OK"          # stop_ring corre solo al salir (trap EXIT)
```

Añádelo a la lista `experiments=(...)` de `run-all.sh` para que entre en la corrida completa.
