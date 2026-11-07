#!/usr/bin/env bash
# Local inspect CA for agentgateway tls.mode: dynamicCa, plus a separate
# certificate for the lab echo server. The echo cert is not signed by the
# inspect CA. Clients trust the inspect CA; the gateway skips verification
# of the echo cert (backendTLS.insecure) because that cert exists only so
# the echo can speak HTTPS on loopback.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${root}/certs"

if [[ -f "${root}/certs/ca-cert.pem" && -f "${root}/certs/ca-key.pem" && -f "${root}/certs/echo-cert.pem" && -f "${root}/certs/echo-key.pem" ]]; then
  echo "certs already present in ${root}/certs"
  exit 0
fi

# The docs generate this CA with openssl req -x509. basicConstraints=CA:TRUE
# is added so the file is a CA that can sign the per-host leaf certificates
# agentgateway issues in dynamicCa mode. Local testing only.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${root}/certs/ca-key.pem" \
  -out "${root}/certs/ca-cert.pem" \
  -days 30 \
  -subj "/CN=agentgateway egress CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${root}/certs/echo-key.pem" \
  -out "${root}/certs/echo-cert.pem" \
  -days 30 \
  -subj "/CN=echo.lab.local" \
  -addext "subjectAltName=DNS:echo.lab.local,DNS:deny.lab.local,IP:127.0.0.1"

chmod 600 "${root}/certs/ca-key.pem" "${root}/certs/echo-key.pem"
echo "wrote ${root}/certs/ca-cert.pem and the echo server certificate"
