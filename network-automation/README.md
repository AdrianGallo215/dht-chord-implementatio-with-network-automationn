# network-automation

Esta carpeta contiene la capa de automatización de red del proyecto: el puente entre
la DHT (Chord, código de Ivett en la raíz del repo) y los dispositivos de red reales,
vía [Netmiko](https://github.com/ktbyers/netmiko). También es donde vive el
`docker-compose.yml` que levanta el anillo completo (los 3 nodos Chord + esta capa
de automatización fusionada en cada uno).

## ¿Qué hace?

Cuando alguien pide `chord run <dispositivo> <comando>`, la DHT enruta la petición
al nodo responsable de ese dispositivo, y ese nodo ejecuta `netmiko-runner.py` para
conectarse por SSH de verdad y correr el comando. El resultado queda cacheado y
replicado en la DHT igual que cualquier otro dato.

## Contenido

| Archivo | Para qué sirve |
| --- | --- |
| `netmiko-runner.py` | Ejecuta un comando contra un dispositivo vía Netmiko y devuelve JSON. Invocado por el nodo Go (`automation.go`) vía `subprocess`. Incluye preflight checks (RAM, hilos, red) y un mapa de errores conocidos en su propia cabecera — si algo falla, léelo primero ahí. |
| `Dockerfile` | Imagen fusionada Go (binario del nodo Chord) + Python (Netmiko). Vive en este repo pero el binario Go se compila desde la raíz — ver nota de build más abajo. |
| `requirements.txt` | Dependencias Python (`netmiko`). |
| `.env.example` | Plantilla de credenciales. Copia a `.env` y rellena con datos reales — **nunca subas `.env` a git**. |
| `docker-compose.yml` | Levanta los 3 nodos del anillo (`chord-node-1/2/3`), cada uno con Go + Python fusionados. |
| `config-node1.yaml`, `config-node2.yaml`, `config-node3.yaml` | Uno por nodo. Cada uno le dice a su contenedor cómo anunciarse a sí mismo ante los demás (`addr: chord-node-N`). Necesarios porque, sin esto, cada nodo se identifica como `0.0.0.0`, que no es una dirección alcanzable entre contenedores separados (ver sección de gotchas). |

## Configuración inicial

```bash
cp .env.example .env
# edita .env con las credenciales reales del dispositivo:
#   NETMIKO_HOST, NETMIKO_PORT, NETMIKO_USER, NETMIKO_PASS, NETMIKO_SECRET
```

## Uso — levantar el anillo completo

Desde esta carpeta:

```bash
docker-compose up -d --build
```

El nodo `chord-node-1` expone su puerto (`8000`) al host, así que el cliente ya
compilado (`../client/chord`) puede hablarle directo desde la VM sin necesidad de
meterlo también en un contenedor:

```bash
ADDR=localhost:8000 ../client/chord locate <dispositivo>
ADDR=localhost:8000 ../client/chord run <dispositivo> "<comando>"
ADDR=localhost:8000 ../client/chord get <dispositivo>
```

Para probar tolerancia a fallos, tumba cualquier nodo **que no sea `chord-node-1`**
(porque es el único con el puerto expuesto hacia afuera):

```bash
docker stop chord-node-2
sleep 3   # dale un momento al anillo para detectar la caída y re-enrutar
ADDR=localhost:8000 ../client/chord get <dispositivo>
docker-compose up -d chord-node-2   # reintegrarlo después
```

## Uso — probar solo el script, sin Docker ni el anillo

Útil para descartar problemas de Netmiko/red antes de meter Docker en la ecuación:

```bash
python3 netmiko-runner.py --selftest --host <IP>          # solo preflight, no ejecuta nada
python3 netmiko-runner.py --dry-run --command "show version"   # valida el contrato JSON sin conectar
python3 netmiko-runner.py --host <IP> --username <user> --password '<pass>' --command "show ip interface brief"
```

## Notas importantes / cosas que ya nos mordieron

- **El datastore de la DHT vive en memoria.** Si reinicias un nodo (especialmente
  `chord-node-1`), pierde todo su estado y vuelve a formar un anillo desde cero. Si
  necesitas reiniciar algo durante una demo, vuelve a correr `run` antes de `get`.
- **`security_opt: seccomp:unconfined`** está en el compose porque el Docker Engine
  de la VM (`19.03.8`) tiene un choque conocido entre su filtro seccomp por defecto
  y la syscall `clone3()` que usan libc/Python recientes para crear hilos — sin esto,
  cualquier cosa que abra un hilo (Netmiko incluido) falla con
  `RuntimeError: can't start new thread`. Si actualizan Docker a `20.10.9+`, esta
  línea deja de ser necesaria pero no hace daño dejarla.
- **Los `config-node*.yaml` no son opcionales.** El proyecto base de Chord anuncia
  cada nodo con la dirección que traiga en su config, y por defecto es `0.0.0.0`
  (válido para escuchar, inútil para que otro contenedor te marque de vuelta). Sin
  estos archivos montados, los 3 nodos terminan creyendo que están solos en su
  propio anillo, cada uno con el mismo Id.
- **Si el build de Docker falla resolviendo `proxy.golang.org` o `pypi.org`**, es
  DNS del daemon de Docker, no de la VM. Revisa/crea `/etc/docker/daemon.json` con
  `{"dns": ["8.8.8.8", "1.1.1.1"]}` y reinicia el daemon.
- **Credenciales:** si alguna vez ves un `.env` con password real en `git log`,
  rota esa credencial en el dispositivo real — el historial de git no se limpia
  solo con borrar el archivo del working tree.

## Contrato del script (para quien toque `automation.go` del lado Go)

`netmiko-runner.py` siempre imprime **una sola línea JSON en stdout**, nunca texto
extra ahí (los diagnósticos van a stderr):

```jsonc
// éxito
{"ok": true,  "output": "<texto del comando>", "error": null,    "error_type": null}
// fallo
{"ok": false, "output": null,                  "error": "<msg>", "error_type": "<categoria>"}
```

`error_type` puede ser: `timeout`, `auth`, `ssh_protocol`, `connection_refused`, `dns`,
`thread_limit`, `memory`, `config`, `preflight`, `unknown`.