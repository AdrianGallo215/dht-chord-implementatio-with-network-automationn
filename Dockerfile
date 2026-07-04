# Dockerfile — Chord node image (Go binary + python3/netmiko runtime for the Run RPC).
#
# This builds the ./server binary (multi-stage, so the final image has no Go
# toolchain) on top of a python3 base so the node can exec netmiko-runner.py
# via os/exec for the Run RPC.
#
# IMPORTANT: this image does NOT bake in "network-automation/netmiko-runner.py".
# That script is owned by Adrian and is bind-mounted into the container at
# runtime (see docker-compose.yml) at the path the AutomationScript config
# option points to (default: /opt/automation/netmiko-runner.py). Likewise
# device credentials (NETMIKO_USER/NETMIKO_PASS/NETMIKO_SECRET/NETMIKO_PORT)
# are supplied at runtime via env_file, never baked into this image.
#
# Build context must be the repo root (not "network-automation/"), since the
# builder stage needs go.mod/go.sum and all .go packages.
#
# NOTE for whoever wires up docker-compose.yml: the "chord-node-*" services'
# `build.context: ./chord-node` placeholder should point here instead
# (context: .. relative to network-automation/, dockerfile: ../Dockerfile),
# and each chord-node-* service needs a volume mounting netmiko-runner.py to
# /opt/automation/netmiko-runner.py plus an env_file for NETMIKO_* credentials.

FROM golang:1.25 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/chord ./server

FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Matches network-automation/requirements.txt; kept inline so this image
# doesn't need network-automation/ as part of its build context.
RUN pip install --no-cache-dir --break-system-packages "netmiko>=4.0,<5.0"

WORKDIR /app
COPY --from=builder /out/chord ./chord

ENTRYPOINT ["./chord"]
