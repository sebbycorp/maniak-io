#!/usr/bin/env bash
# Start the local echo, the Anthropic mock, and agentgateway, then run both hops.
# Does not call Anthropic. Does not need a Claude Code session.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
run="${root}/.run"
mkdir -p "${run}"

account_email="${ACCOUNT_EMAIL:-you@example.com}"
if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
  account_email="${ACCOUNT_EMAIL:-${account_email}}"
fi
# The mock ignores this. A real key is only required if you edit baseUrl.
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-sk-local-lab}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

agentgateway_bin="${AGENTGATEWAY_BIN:-}"
if [[ -z "${agentgateway_bin}" ]]; then
  if command -v agentgateway >/dev/null 2>&1; then
    agentgateway_bin="$(command -v agentgateway)"
  else
    agentgateway_bin="${root}/.cache/agentgateway"
  fi
fi

cleanup() {
  local pid
  for pid in $(jobs -p); do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  wait || true
}
trap cleanup EXIT

"${root}/scripts/gen-ca.sh"

if [[ ! -x "${agentgateway_bin}" ]]; then
  mkdir -p "${root}/.cache"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac
  case "${os}" in
    linux|darwin) ;;
    *)
      echo "set AGENTGATEWAY_BIN to an agentgateway 1.7.x binary" >&2
      exit 1
      ;;
  esac
  url="https://github.com/agentgateway/agentgateway/releases/download/v1.7.0/agentgateway-${os}-${arch}"
  echo "downloading ${url}"
  curl -fsSL -o "${agentgateway_bin}" "${url}"
  chmod +x "${agentgateway_bin}"
fi

python3 "${root}/scripts/echo-server.py" \
  "${root}/certs/echo-cert.pem" "${root}/certs/echo-key.pem" 8443 \
  >"${run}/echo.log" 2>&1 &
python3 "${root}/scripts/llm-mock.py" 4010 >"${run}/llm-mock.log" 2>&1 &

# The gateway dials upstream itself. A proxy in this shell must not wrap that dial.
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  "${agentgateway_bin}" -f "${root}/config.yaml" >"${run}/agentgateway.log" 2>&1 &

port_open() {
  python3 -c 'import socket,sys; s=socket.create_connection(("127.0.0.1", int(sys.argv[1])), 0.2); s.close()' "$1" >/dev/null 2>&1
}

ready=0
for _ in $(seq 1 50); do
  if port_open 4010 && port_open 8443 && port_open 4000 && port_open 3000; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "${ready}" != "1" ]]; then
  echo "timed out waiting for the lab ports" >&2
  echo "--- agentgateway log ---" >&2
  cat "${run}/agentgateway.log" >&2 || true
  exit 1
fi

echo
echo "== LLM hop: mask ${account_email} in the prompt, leave a different address =="
llm_out="${run}/llm-response.json"
curl -sS -D "${run}/llm-headers.txt" -o "${llm_out}" \
  http://127.0.0.1:4000/v1/messages \
  -H 'content-type: application/json' \
  -H 'x-api-key: sk-local-lab' \
  -H 'anthropic-version: 2023-06-01' \
  -d "{\"model\":\"claude-sonnet-4-5\",\"max_tokens\":64,\"system\":\"Signed-in account: ${account_email}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a curl contact of ${account_email}. A teammate address coworker@other.example must stay.\"}]}"

python3 - "${llm_out}" "${account_email}" <<'PY'
import json, sys
path, email = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8").read()
print(raw)
body = json.loads(raw)
text = body["content"][0]["text"]
if email in text:
    raise SystemExit(f"upstream prompt still contains {email}")
if "<masked>" not in text:
    raise SystemExit("upstream prompt was not masked")
if "coworker@other.example" not in text:
    raise SystemExit("a different address was removed; the guard is too broad")
print("LLM hop ok: account address masked, other address kept")
PY

echo
echo "== Egress hop: rewrite User-Agent on echo.lab.local =="
rewrite_out="${run}/rewrite.json"
curl -sS --proxy http://127.0.0.1:3000 \
  --cacert "${root}/certs/ca-cert.pem" \
  --resolve echo.lab.local:443:127.0.0.1 \
  -A "claude-code/1.0 (${account_email})" \
  -o "${rewrite_out}" \
  https://echo.lab.local/headers
python3 - "${rewrite_out}" "${account_email}" <<'PY'
import json, sys
path, email = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8").read()
print(raw)
body = json.loads(raw)
ua = body["headers"].get("User-Agent") or body["headers"].get("user-agent")
if ua != "claude-code/egress":
    raise SystemExit(f"upstream User-Agent is {ua!r}, expected claude-code/egress")
if email in raw:
    raise SystemExit("account address reached the echo")
print("egress rewrite ok")
PY

echo
echo "== Egress hop: deny User-Agent that contains @ =="
deny_file="${run}/deny.txt"
set +e
deny_code="$(curl -sS -o "${deny_file}" -w '%{http_code}' \
  --proxy http://127.0.0.1:3000 \
  --cacert "${root}/certs/ca-cert.pem" \
  --resolve deny.lab.local:443:127.0.0.1 \
  -A "claude-code/1.0 (${account_email})" \
  https://deny.lab.local/headers)"
deny_rc=$?
set -e
echo "curl exit ${deny_rc} http ${deny_code}"
cat "${deny_file}" || true
echo
if grep -q "${account_email}" "${run}/echo.log"; then
  echo "echo log saw the account address; deny did not stop the request" >&2
  exit 1
fi
if [[ "${deny_code}" == "200" ]]; then
  echo "deny route returned 200 for a User-Agent containing the account address" >&2
  exit 1
fi
echo "egress deny ok (request did not reach the echo with the account address)"

echo
echo "== Egress hop: a User-Agent without @ is forwarded on the deny route =="
allow_out="${run}/allow.json"
curl -sS --proxy http://127.0.0.1:3000 \
  --cacert "${root}/certs/ca-cert.pem" \
  --resolve deny.lab.local:443:127.0.0.1 \
  -A "claude-code/egress" \
  -o "${allow_out}" \
  https://deny.lab.local/headers
python3 - "${allow_out}" <<'PY'
import json, sys
body = json.load(open(sys.argv[1], encoding="utf-8"))
ua = body["headers"].get("User-Agent") or body["headers"].get("user-agent")
if ua != "claude-code/egress":
    raise SystemExit(f"clean User-Agent was changed to {ua!r}")
print("deny route forwarded a User-Agent with no @")
PY

echo
echo "lab ok"
