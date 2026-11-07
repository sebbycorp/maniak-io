# Localhost lab: mask one account email, rewrite User-Agent

Standalone [agentgateway](https://agentgateway.dev) 1.7.0 on your machine. Nothing here is a production TLS setup, and nothing here calls Anthropic unless you change `baseUrl` yourself.

Two hops:

1. **LLM.** `POST /v1/messages` on port 4000. A request regex guard masks the literal address `you@example.com` and forwards the rest. The lab upstream is a local mock that echoes the body it received.
2. **Egress.** HTTP CONNECT on port 3000. Tunnel mode and an internal HTTPS listener with `tls.mode: dynamicCa` so HTTP policy applies to the request inside TLS. `echo.lab.local` replaces `User-Agent` with `claude-code/egress`. `deny.lab.local` returns 403 when that header contains `@` or `you@example.com`.

Both hostnames are sent to a local HTTPS echo on `127.0.0.1:8443`. This file is not an open proxy to the internet.

## Run

Requirements: `python3`, `curl`, `openssl`, and agentgateway 1.7.x (`agentgateway` on `PATH`, or `AGENTGATEWAY_BIN`). If the binary is missing, `scripts/demo.sh` downloads the 1.7.0 release for Linux or macOS into `.cache/` (gitignored).

```sh
cp .env.example .env
make demo
```

`.env.example` has placeholders only. The mock ignores `ANTHROPIC_API_KEY`. Use a real key only after you edit `baseUrl` in `config.yaml` to `https://api.anthropic.com`, and keep that key in `.env`, not in git.

`make demo` generates `certs/`, starts the echo, the mock, and agentgateway, then checks four results:

- The mock sees `<masked>` where `you@example.com` was, and still sees `coworker@other.example`.
- `https://echo.lab.local/headers` through the proxy shows `"user-agent": "claude-code/egress"`.
- The same request to `https://deny.lab.local/headers` with the account address in `User-Agent` gets HTTP 403 `authorization failed` and does not show up at the echo.
- `deny.lab.local` with `User-Agent: claude-code/egress` is forwarded unchanged.

Generated files (`certs/`, `.env`, `.run/`, `.cache/`) stay out of git.

## Trust the inspect CA

`scripts/gen-ca.sh` writes a 30-day local CA (`certs/ca-cert.pem` and `certs/ca-key.pem`). The openssl command follows the [egress proxy](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/egress-proxy/) example and adds `basicConstraints=CA:TRUE` so the file can sign the per-host certificates agentgateway issues. Curl in the demo passes `--cacert certs/ca-cert.pem`.

That is the whole trust story for this lab. The script does not install the CA into the system trust store, and the certificate is not a stand-in for production TLS. Do not distribute `ca-key.pem`.

For a client other than the demo's curl:

- curl: `--cacert certs/ca-cert.pem` or `CURL_CA_BUNDLE`
- Python requests: `REQUESTS_CA_BUNDLE` or `SSL_CERT_FILE`
- Node: `NODE_EXTRA_CA_CERTS`

Point the process that runs curl at the CONNECT listener:

```sh
export HTTPS_PROXY=http://127.0.0.1:3000
export HTTP_PROXY=http://127.0.0.1:3000
export NO_PROXY=127.0.0.1,localhost
```

`NO_PROXY` keeps the call to the local Messages API on port 4000 from being sent back into the CONNECT proxy. Start agentgateway itself without `HTTP_PROXY` / `HTTPS_PROXY` set. The demo script clears those for the gateway process.

## Claude Code, when you want it

The demo does not start Claude Code. To send its API calls through the LLM hop:

```sh
export ANTHROPIC_BASE_URL=http://127.0.0.1:4000
export ANTHROPIC_API_KEY=sk-local-lab
```

Shell commands Claude runs only hit the egress hop when that process has `HTTPS_PROXY` / `HTTP_PROXY` set and trusts `certs/ca-cert.pem`. A curl that dials the destination directly never presents `User-Agent` to agentgateway.

## Config notes

The regex is one address, case-insensitive. It is not `builtin: email`. Masking every email is the wrong control for a coding agent that still has to handle other people's addresses. Custom-pattern matches are replaced with `<masked>`.

Request guards read the system prompt, message text, and tool results unless you set `scope`. See [regex prompt guards](https://agentgateway.dev/docs/standalone/latest/llm/prompt-guards/regex/). The guard runs on the buffered request, so it still applies when the client asks for a streamed response. A response `mask` cannot rewrite bytes that have already been streamed. This lab does not put a mask on the response, and it cannot edit a shell command that is already running.

`requestHeaderModifier.set` replaces `User-Agent`. The [header manipulation](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/traffic-management/manipulation/) docs define `set` as replace. Plain CONNECT does not see the inner HTTPS headers; the inspect listener is what makes the modifier apply. See [CONNECT egress](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/egress-proxy/).

`backendTLS.insecure: true` is only for the lab echo, which has its own self-signed certificate. The [inspect example](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/egress-proxy/) uses `backendTLS: {}` against a public host. Leave verification on for real destinations.

`config.session.key: disabled` stops agentgateway from writing a generated session key into `config.yaml`. This lab does not use session tokens.

The deny rule is fail-open when the CEL expression errors. A missing `User-Agent` does not match `request.headers["user-agent"].contains(...)`, so it is not denied. The rewrite route does not depend on that expression.
