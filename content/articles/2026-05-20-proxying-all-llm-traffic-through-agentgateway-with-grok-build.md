---
title: "Proxying All Your LLM Traffic Through agentgateway with Grok Build"
date: 2026-05-20
description: "Centralize all your LLM traffic — OpenAI, xAI Grok, and local Qwen models — through a single Enterprise agentgateway instance, configured as the unified endpoint for Grok Build. One URL, full observability, secret management, and route-based access control."
---

## Introduction

If you're like me, your AI tooling has probably grown into a sprawling mess of API keys: Claude Code reads `.claude/.env`, Cursor uses OpenAI keys, Langflow points at its own Anthropic endpoint, and your local agents each have their own hardcoded tokens scattered across config files. Every new tool means another key to manage, another endpoint to remember, and another blind spot in your observability stack.

The alternative is elegant: **route every single LLM request through a single gateway** that handles authentication, observability, rate limiting, and routing — then point all your tools at that one endpoint.

In this guide, I'll walk you through exactly how I set up this architecture using **Solo.io Enterprise agentgateway** as the LLM traffic proxy and **Grok Build** as one of the clients. My production cluster routes traffic to three backends:

- **OpenAI** (`gpt-4o`) — cloud API via `api.openai.com`
- **xAI Grok** (`grok-4.3`) — cloud API via `api.x.ai`
- **DGX Spark** (`Qwen/Qwen3.6-35B-A3B-FP8`) — local on-prem inference server at `172.16.10.173:8000`

The key insight is that agentgateway speaks the OpenAI API contract. Every backend — regardless of whether it's OpenAI, xAI, Anthropic, or a local Qwen — is exposed as a standard `/v1/chat/completions` endpoint. Your tools don't need to know or care what's behind the proxy.

## Architecture Overview

Here's the high-level picture:

```
┌─────────────┐    ┌─────────────────────────────────────────────┐
│  Grok Build │    │                                             │
│  Claude Code│───→│  agentgateway Proxy (Kubernetes)            │
│  Cursor     │    │                                             │
│  Langflow   │    │  Gateway → HTTPRoute → AgentgatewayBackend  │
│  Your CLI   │    │                                             │
└─────────────┘    └────────┬──────────┬──────────────┬──────────┘
                           │          │              │
                    ┌──────▼───┐ ┌────▼─────┐ ┌─────▼──────┐
                    │ OpenAI   │ │ xAI Grok │ │ DGX Spark  │
                    │ gpt-4o   │ │ grok-4.3 │ │ Qwen 3.6   │
                    └──────────┘ └──────────┘ └────────────┘
```

All LLM requests flow through the same agentgateway instance — the same IP, same port, same observability pipeline — but different HTTP path prefixes route to different backends:

| Path Prefix | Backend | Model | Location |
|-------------|---------|-------|----------|
| `/openai` | OpenAI | `gpt-4o` | Cloud (api.openai.com) |
| `/grok` | xAI | `grok-4.3` | Cloud (api.x.ai) |
| `/spark` | DGX Spark | `Qwen3.6-35B-A3B-FP8` | On-prem (172.16.10.173) |

## The Problem with Scattered LLM Configuration

Before agentgateway, my setup looked like this:

- **Grok Build**: `base_url: http://172.16.10.173:8000/v1`, model `Qwen/Qwen3.6-35B-A3B-FP8`
- **Claude Code**: `ANTHROPIC_API_KEY` in `.env`, points at `api.anthropic.com`
- **Cursor**: OpenAI key hardcoded in settings, points at `api.openai.com`
- **Custom agents**: Various scripts with keys in environment variables, `.env` files, or inline

The pain points were obvious:

1. **API key sprawl** — every tool had its own key stored somewhere different
2. **No unified observability** — I couldn't see total LLM spend, compare model performance, or debug issues across providers
3. **Local model isolation** — my on-prem Qwen model on DGX Spark was only accessible to tools that could reach `172.16.10.173`, with no unified routing
4. **Secret management** — no centralized rotation, no audit trail

After agentgateway, it's all one URL with path-based routing. Every request goes through the same gateway that logs, traces, and authenticates — regardless of which LLM ultimately serves it.

## The Architecture: Three Layers

agentgateway uses three Kubernetes resource types to define each backend connection:

### 1. AgentgatewayBackend — "Where is the LLM?"

The backend resource tells agentgateway about an LLM provider. Here are all three of mine:

**OpenAI backend** — Cloud API with API key auth:

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: openai
  namespace: agentgateway-system
spec:
  ai:
    provider:
      openai:
        model: gpt-4o
  policies:
    auth:
      secretRef:
        name: openai-secret
```

**xAI Grok backend** — Cloud API with TLS and SNI:

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: xai-grok
  namespace: agentgateway-system
spec:
  ai:
    provider:
      openai:
        model: grok-4.3
      host: api.x.ai
      port: 443
      pathPrefix: /v1
  policies:
    auth:
      secretRef:
        name: xai-secret
    tls:
      sni: api.x.ai
```

**DGX Spark backend** — Local on-prem Qwen model, no auth needed:

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: dgx-spark-llm
  namespace: agentgateway-system
spec:
  ai:
    provider:
      openai:
        model: Qwen/Qwen3.6-35B-A3B-FP8
      host: 172.16.10.173
      port: 8000
      pathPrefix: /v1
```

Key observations:

- The **OpenAI provider** in agentgateway isn't just for OpenAI — it implements the OpenAI-compatible API contract. That's why it works for xAI (which exposes an OpenAI-compatible endpoint) and for the DGX Spark's vLLM server.
- The DGX Spark backend points directly at the on-prem inference server. No cloud egress, no internet required.
- Cloud backends (OpenAI, xAI) use `secretRef` for API key auth. The local DGX Spark has no auth — it's on the internal network.

### 2. Gateway — "Where does the traffic enter?"

A Gateway resource defines the proxy listener. I have one main gateway for cloud providers and dedicated gateways for local models (useful when you want separate NodePort allocations or network policies):

**Main gateway (cloud LLMs)**:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-proxy
  namespace: agentgateway-system
spec:
  gatewayClassName: enterprise-agentgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

**Dedicated DGX Spark gateway** (separate NodePort for the on-prem model):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: dgx-spark-gateway
  namespace: agentgateway-system
spec:
  gatewayClassName: enterprise-agentgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

Both use the `enterprise-agentgateway` GatewayClass, which is created automatically by the Enterprise agentgateway Helm chart. On my bare-metal Talos cluster, these are exposed via NodePort:

| Gateway | NodePort |
|---------|----------|
| `agentgateway-proxy` | 30160 |
| `dgx-spark-gateway` | 31944 |

### 3. HTTPRoute — "Which backend handles this path?"

HTTPRoute resources connect the Gateway to the Backend, defining which URL path prefix routes to which LLM:

**OpenAI route** (goes to main gateway, path `/openai`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: openai
  namespace: agentgateway-system
spec:
  parentRefs:
    - name: agentgateway-proxy
      namespace: agentgateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /openai
      backendRefs:
        - name: openai
          namespace: agentgateway-system
          group: agentgateway.dev
          kind: AgentgatewayBackend
```

**xAI Grok route** (goes to dedicated gateway, path `/grok`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: xai-grok
  namespace: agentgateway-system
spec:
  parentRefs:
    - name: xai-grok-gateway
      namespace: agentgateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /grok
      backendRefs:
        - name: xai-grok
          namespace: agentgateway-system
          group: agentgateway.dev
          kind: AgentgatewayBackend
```

**DGX Spark route** (goes to dedicated gateway, path `/spark`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: dgx-spark-llm
  namespace: agentgateway-system
spec:
  parentRefs:
    - name: dgx-spark-gateway
      namespace: agentgateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /spark
      backendRefs:
        - name: dgx-spark-llm
          namespace: agentgateway-system
          group: agentgateway.dev
          kind: AgentgatewayBackend
```

The complete flow for a request:

```
Client → http://172.16.10.149:30160/openai/v1/chat/completions
       → Gateway "agentgateway-proxy" (port 80, NodePort 30160)
       → HTTPRoute matches path "/openai"
       → AgentgatewayBackend "openai"
       → api.openai.com/v1/chat/completions
```

## Secret Management with Vault

Cloud LLM providers require API keys. I use **HashiCorp Vault** with the **External Secrets Operator** to keep all keys out of Git:

```
Vault (KV v2)              ESO                          K8s Secret              Backend
agentgateway/llm-keys/openai  →  ExternalSecret  →  openai-secret  →  AgentgatewayBackend
agentgateway/llm-keys/xai     →  ExternalSecret  →  xai-secret     →  AgentgatewayBackend
```

The Vault stores the actual API keys. ESO syncs them into Kubernetes Secrets. The `AgentgatewayBackend` resources reference those Secrets by name — never the key itself. ArgoCD manages all of this declaratively, and no secret ever touches Git.

```yaml
# ClusterSecretStore — connects ESO to Vault
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault
  namespace: agentgateway-system
spec:
  provider:
    vault:
      server: "http://vault-vault.vault.svc:8200"
      path: "agentgateway/llm-keys"
      kind: SecretList
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
```

## Distributed Tracing

Every request through agentgateway emits OpenTelemetry traces to the Solo UI's telemetry collector. This gives you a unified view of all LLM traffic — OpenAI, xAI, local Qwen — in the same dashboard:

```yaml
apiVersion: enterpriseagentgateway.solo.io/v1alpha1
kind: EnterpriseAgentgatewayPolicy
metadata:
  name: tracing
  namespace: agentgateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: agentgateway-proxy
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: dgx-spark-gateway
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: xai-grok-gateway
  frontend:
    tracing:
      backendRef:
        name: solo-enterprise-telemetry-collector
        namespace: agentgateway-system
        kind: Service
        port: 4317
      randomSampling: "true"
```

## Connecting Grok Build

Now for the exciting part — pointing Grok Build at the gateway. The Grok Build config file lives at `~/.grok/config.toml`. Here's mine:

```toml
[cli]
installer = "internal"

[model.qwen]
model = "Qwen/Qwen3.6-35B-A3B-FP8"
base_url = "http://172.16.10.173:8000/v1"

[model.agw]
model = "agw"
base_url = "http://172.16.10.149:31944/spark"

[ui]
max_thoughts_width = 120
fork_secondary_model = "grok-build"
yolo = true
compact_mode = true
permission_mode = "always-approve"
theme = "groknight"

[models]
default = "agw"
```

The `[model.agw]` section defines a model called `agw` that points at the DGX Spark gateway URL — `http://172.16.10.149:31944/spark`. This is the agentgateway endpoint for my local Qwen model.

The `[models]` section sets `agw` as the **default model**, so every Grok Build conversation goes through agentgateway by default.

The `[model.qwen]` entry is a fallback direct-to-backend configuration. If I need to bypass the gateway for debugging, I can switch to the `qwen` model and it points directly at the vLLM server.

Here's what happens when I type a prompt in Grok Build:

```
Grok Build → base_url: http://172.16.10.149:31944/spark
           → Gateway "dgx-spark-gateway" (NodePort 31944)
           → HTTPRoute matches "/spark"
           → AgentgatewayBackend "dgx-spark-llm"
           → http://172.16.10.173:8000/v1/chat/completions
           → Qwen3.6-35B-A3B-FP8 (local DGX)
```

The request never leaves my network. The gateway still logs it, traces it, and enforces policies — but the payload never traverses the public internet.

## Connecting Other Tools

The same pattern works for any tool that supports custom API endpoints:

**Claude Code** — set the API base to the agentgateway URL for Anthropic:
```
ANTHROPIC_BASE_URL=http://172.16.10.149:30160/anthropic
```

**Cursor** — in settings, set the API endpoint to:
```
http://172.16.10.149:30160/openai
```
And set the model to `gpt-4o` — agentgateway strips the path prefix and forwards to the OpenAI backend.

**Langflow / LlamaIndex / custom scripts** — same thing:
```python
import openai
client = openai.OpenAI(
    api_key="not-needed-proxy",
    base_url="http://172.16.10.149:30160/openai/v1"
)
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

The `api_key` doesn't need to be a real OpenAI key — it's just passed through by the proxy. The real auth happens server-side via the Vault-synced Secret.

## Testing the Endpoints

You can verify each backend works through the gateway:

**OpenAI** (main gateway, path `/openai`):
```bash
curl http://172.16.10.149:30160/openai/v1/chat/completions \
  -H "content-type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

**xAI Grok** (dedicated gateway, path `/grok`):
```bash
curl http://172.16.10.149:31500/grok/v1/chat/completions \
  -H "content-type: application/json" \
  -d '{"model":"grok-4.3","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

**DGX Spark** (dedicated gateway, path `/spark`):
```bash
curl http://172.16.10.149:31944/spark/v1/chat/completions \
  -H "content-type: application/json" \
  -d '{"model":"Qwen/Qwen3.6-35B-A3B-FP8","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

## Deploying with GitOps

All of these manifests live in a Git repository and are deployed via ArgoCD using sync waves:

1. **Wave 1** — Gateway API CRDs
2. **Wave 2** — agentgateway CRDs (AgentgatewayBackend, EnterpriseAgentgatewayPolicy types)
3. **Wave 3** — Control plane (controller + proxy)
4. **Wave 4** — HashiCorp Vault (secrets store)
5. **Wave 5** — External Secrets Operator (Vault → K8s Secret sync)
6. **Wave 6** — Solo UI (dashboard + telemetry collector)
7. **Wave 7** — Config (gateways, backends, routes, policies)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway-config
  namespace: argocd
spec:
  syncWave: 7
  # ... (points to config/ directory in Git)
```

When I add a new LLM backend, I create three YAML files (backend, gateway if needed, route), commit them, and ArgoCD deploys everything automatically. No imperative commands, no manual kubectl apply.

## The Benefits

After months of running this setup, the benefits are clear:

1. **One URL, all LLMs** — Every tool connects to the same gateway. No scattered keys, no config files spread across machines.

2. **Local-first by default** — My Grok Build conversations go to the local Qwen model by default (free, fast, private). I switch to GPT-4o or Grok when I need the heavier models. The gateway makes the switch seamless.

3. **Unified observability** — The Solo UI shows traces from all three backends in one place. I can see latency, error rates, and token usage across providers without logging into three different dashboards.

4. **Local models get cloud treatment** — The DGX Spark runs behind the same Gateway API routing, tracing, and policy system as the cloud providers. It's a first-class citizen, not an afterthought.

5. **Secrets never touch Git** — Vault + ESO keeps API keys out of the repository. Adding a new provider means storing a key in Vault and applying three YAML files.

6. **Network isolation** — The on-prem DGX Spark is on an internal network (`172.16.10.173`). agentgateway exposes it to the outside world through the Gateway API — no firewall rules needed on the DGX itself.

## Conclusion

agentgateway transforms the LLM landscape from a fragmented mess of per-tool configurations into a unified, observable, centrally-managed infrastructure. Grok Build is just one client — any tool that speaks the OpenAI API contract can connect to the gateway and get access to all your LLMs.

The three-resource pattern (Backend → Gateway → Route) is simple enough to understand in minutes but powerful enough to handle complex multi-provider, multi-model, multi-cluster setups. And because it's all Kubernetes-native — using Gateway API CRDs managed by ArgoCD — it fits into any GitOps workflow you already have.

The full configuration for this setup is open source in the [k8s-goose repository](https://github.com/sebastianmaniak/k8s-goose), which includes the ArgoCD GitOps pipeline, all YAML manifests, and scripts for deploying on any Kubernetes cluster.

For a step-by-step walkthrough of the agentgateway setup itself, see [Setting Up Enterprise agentgateway on Kind Clusters](/articles/01-setting-up-enterprise-agentgateway-on-kind-clusters).
