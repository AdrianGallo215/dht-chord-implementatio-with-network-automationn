# Dockerfile — contenedor de automatización de red (netmiko_runner.py)
#
# Construido para correr DENTRO de la DEVASC VM (Linux), donde Docker nativo
# sí puede alcanzar la red host-only del CR1000v sin trucos adicionales.
#
# -----------------------------------------------------------------------
# PROBLEMAS DE BUILD MÁS PROBABLES Y CÓMO RESOLVERLOS
# -----------------------------------------------------------------------
#
# 1) "pip install" falla / se cuelga / timeout
#    Causa: la DEVASC VM se quedó sin salida a internet. Esto pasa si por
#    error deshabilitaron el Adaptador 1 (NAT) al agregar el Adaptador 2
#    (host-only) para el CR1000v -- deben coexistir ambos, NO reemplazar uno
#    por el otro.
#    Solución: dentro de la VM, antes de construir la imagen:
#         ping -c 3 8.8.8.8
#         ping -c 3 pypi.org
#    Si el primero funciona pero el segundo no, es un problema de DNS del
#    adaptador NAT, no de conectividad. Revisa /etc/resolv.conf en la VM.
#
# 2) "no space left on device" durante el build
#    Causa: la VM tiene poco disco asignado y las capas de Docker se van
#    acumulando entre pruebas.
#    Solución: `docker system prune -a` para limpiar imágenes/capas viejas
#    antes de reconstruir.
#
# 3) El build es muy lento la primera vez
#    Causa normal: está descargando la imagen base python:slim (~50MB) más
#    las dependencias. Constrúyela una sola vez y reutilízala; no la
#    reconstruyas en cada iteración si solo cambiaste netmiko_runner.py
#    (Docker cachea la capa de "pip install" si el requirements.txt no cambió).
#
# 4) Falla al resolver la imagen base (registry timeout)
#    Causa: mismo problema de internet del punto 1, o Docker Hub con rate
#    limit temporal.
#    Solución: reintenta en unos minutos, o usa una imagen ya cacheada
#    localmente si la construiste antes con éxito.
# -----------------------------------------------------------------------

FROM python:3.11-slim

# Evita prompts interactivos y bytecode innecesario
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copiamos requirements primero para aprovechar el cache de capas de Docker:
# si solo cambias netmiko_runner.py después, esta capa de pip install NO
# se vuelve a ejecutar en el siguiente build.
COPY requirements.txt .

# --break-system-packages porque la imagen base marca el Python del sistema
# como "externally managed" (PEP 668); no afecta nada fuera del contenedor.
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY netmiko_runner.py .

# El script se invoca con argumentos desde afuera (docker run / docker exec /
# subprocess de Ivett desde el nodo Go), así que no fijamos un CMD con
# argumentos de conexión fijos -- dejamos el contenedor listo para recibir
# la llamada con los parámetros reales.
ENTRYPOINT ["python3", "netmiko_runner.py"]

# Ejemplo de uso manual para probar el contenedor de forma aislada:
#   docker build -t network-automation .
#   docker run --rm --network chord_net \
#       -e NETMIKO_HOST=192.168.56.101 \
#       -e NETMIKO_USER=admin \
#       -e NETMIKO_PASS=cisco \
#       network-automation --command "show ip interface brief"
