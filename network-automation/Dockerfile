FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --break-system-packages --progress-bar off "netmiko>=4.0,<5.0"
COPY netmiko_runner.py .

ENTRYPOINT ["python3", "netmiko_runner.py"]

# Ejemplo de uso manual para probar el contenedor de forma aislada:
#   docker build -t network-automation .
#   docker run --rm --network chord_net \
#       -e NETMIKO_HOST=192.168.56.101 \
#       -e NETMIKO_USER=admin \
#       -e NETMIKO_PASS=cisco \
#       network-automation --command "show ip interface brief"
