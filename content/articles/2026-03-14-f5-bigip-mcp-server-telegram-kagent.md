---
title: "Managing F5 BIG-IP from Telegram with an AI Agent, MCP, and kagent"
date: 2026-03-14T10:00:00-04:00
draft: false
categories:
  - Networking
  - AI
  - Agents
tags:
  - F5
  - BIG-IP
  - MCP
  - kagent
  - Telegram
  - A2A
  - HITL
  - FastAPI
  - Kubernetes
  - GitOps
---

# Managing F5 BIG-IP from Telegram with an AI Agent, MCP, and kagent

**By Sebastian Maniak**

What if you could manage your F5 BIG-IP load balancer from Telegram? Not by SSH-ing into the box and running `tmsh` — but by telling an AI agent in plain English to "show me all pools" or "disable node 10.0.1.25" and having it figure out the right iControl REST calls, execute them safely, and ask for your approval before anything destructive happens?

That's exactly what I built. In this article, I'll walk through the full stack: a custom **MCP (Model Context Protocol) server** that wraps the F5 iControl REST API, a **kagent AI agent** on Kubernetes that uses those tools to manage the BIG-IP, and a **Telegram bot** that lets you talk to the agent from your phone — complete with **Human-in-the-Loop (HITL) approval buttons** for destructive operations.

Everything runs on my home lab Kubernetes cluster (Talos Linux on Proxmox), deployed via GitOps with ArgoCD, with secrets managed by HashiCorp Vault.

## Why Not Just Use the F5 API Directly?

The F5 iControl REST API is massive. It uses token-based auth with expiring sessions, returns deeply nested JSON, and has hundreds of endpoints. Talking to it directly from an AI agent would be fragile and wasteful.

I needed a wrapper that:

1. **Exposes only what the agent needs** — a curated set of pool, virtual server, node, monitor, iRule, certificate, and system operations instead of the full iControl surface area
2. **Handles auth in one place** — token acquisition, automatic refresh before the 1200s expiry, and clean logout on shutdown
3. **Speaks MCP natively** — so kagent discovers all tools automatically via a single endpoint, no manual tool registration needed
4. **Adds guardrails** — read-only mode, partition allow-lists, HITL approval for destructive operations, and clear error responses the agent can reason about

## Architecture

Here's how it all fits together:

```
┌──────────────┐
│   Telegram   │
│   (user)     │
└──────┬───────┘
       │ polling
       ▼
┌──────────────┐     A2A protocol      ┌──────────────────┐
│ Telegram Bot │ ──────────────────────▶│ kagent Controller │
│ (K8s pod)    │                        │                  │
└──────────────┘                        └────────┬─────────┘
                                                 │ routes to agent
                                                 ▼
                                        ┌──────────────────┐
                                        │ f5-bigip-agent   │
                                        │ (LLM decides     │
                                        │  which tool)     │
                                        └────────┬─────────┘
                                                 │ MCP streamable-HTTP
                                                 ▼
                                        ┌──────────────────┐
                                        │ F5 Wrapper       │
                                        │ (FastAPI + MCP)  │
                                        └────────┬─────────┘
                                                 │ iControl REST
                                                 ▼
                                        ┌──────────────────┐
                                        │ F5 BIG-IP        │
                                        └──────────────────┘
```

Four components, each running as a separate pod in the `kagent` namespace:

- **Telegram Bot** — polls for messages, sends them to kagent via A2A, renders HITL approval buttons
- **kagent Controller** — routes the request to the correct agent, manages conversation state
- **f5-bigip-agent** — the AI agent (LLM) that decides which MCP tools to call based on the user's natural language request
- **F5 Wrapper** — FastAPI service that translates MCP tool calls into iControl REST API calls against the BIG-IP

## Part 1: The F5 MCP Wrapper

The wrapper is a Python FastAPI application that serves two purposes: a REST API for direct HTTP access and an MCP server for kagent tool discovery.

### Project Structure

```
f5-wrapper/
├── Dockerfile
├── requirements.txt
├── app/
│   ├── main.py              # Starlette root — mounts REST + MCP
│   ├── mcp_server.py         # 28 MCP tool definitions
│   ├── config.py             # Pydantic Settings (env vars)
│   ├── auth.py               # F5 token manager
│   ├── routers/              # REST API endpoints
│   │   ├── pools.py
│   │   ├── virtual_servers.py
│   │   ├── nodes.py
│   │   ├── monitors.py
│   │   ├── irules.py
│   │   ├── certificates.py
│   │   └── system.py
│   └── utils/
│       └── f5_client.py      # Reusable HTTP client for iControl REST
```

### Authentication: Token Lifecycle

The F5 iControl REST API uses token-based auth. Rather than handling this in every tool, the wrapper manages the entire token lifecycle transparently:

```python
class F5TokenManager:
    def __init__(self, host, username, password, verify_ssl=False):
        self.host = host
        self.token = None
        self.token_expiry = 0

    async def login(self):
        resp = await self.client.post(
            f"{self.host}/mgmt/shared/authn/login",
            json={"username": self.username, "password": self.password,
                  "loginProviderName": "tmos"},
        )
        self.token = resp.json()["token"]["token"]
        # Tokens last 1200s; refresh at 80% (960s)
        self.token_expiry = time.time() + 960

    async def get_token(self):
        if time.time() >= self.token_expiry:
            await self.login()
        return self.token

    async def logout(self):
        # Clean up token on shutdown
        await self.client.delete(
            f"{self.host}/mgmt/shared/authz/tokens/{self.token}",
            headers={"X-F5-Auth-Token": self.token},
        )
```

On startup, the app logs in and stores the token. Every request checks if the token is about to expire and refreshes automatically. On shutdown, the token is deleted.

### MCP Tool Definitions (28 Tools)

The MCP server uses the `FastMCP` library to expose tools that kagent discovers automatically. Here's the full tool inventory:

| Category | Tools | Description |
|----------|-------|-------------|
| **Pools** | 8 | List, create, delete pools; add/remove/enable/disable members |
| **Virtual Servers** | 4 | List, get details, create, delete virtual servers |
| **Nodes** | 5 | List, get, create, delete nodes; enable/disable/force-offline |
| **Monitors** | 4 | List all monitors, HTTP, HTTPS, and TCP monitors |
| **iRules** | 2 | List iRules, get full TCL definitions |
| **Certificates** | 2 | List SSL certs and expiration dates |
| **System** | 3 | BIG-IP version/hostname, HA failover status, config sync status |

Each tool is a simple async function decorated with `@mcp.tool()`. For example, here's the pool listing tool:

```python
@mcp.tool()
async def list_pools(partition: str = "Common") -> str:
    """List all LTM pools in the specified partition."""
    data = await _client().get(
        f"/mgmt/tm/ltm/pool?$filter=partition eq {partition}"
    )
    items = data.get("items", [])
    result = []
    for item in items:
        result.append({
            "name": item["name"],
            "partition": item.get("partition", "Common"),
            "monitor": item.get("monitor", "none"),
            "lb_method": item.get("loadBalancingMode", "round-robin"),
        })
    return json.dumps(result, indent=2)
```

And a write operation with read-only guard:

```python
@mcp.tool()
async def create_pool(name, partition="Common", monitor="/Common/http",
                      lb_method="round-robin", members=None) -> str:
    """Create a new LTM pool with optional members."""
    if settings.READ_ONLY:
        return "ERROR: Service is in read-only mode"
    payload = {
        "name": name, "partition": partition,
        "monitor": monitor, "loadBalancingMode": lb_method,
    }
    if members:
        payload["members"] = json.loads(members) if isinstance(members, str) else members
    data = await _client().post("/mgmt/tm/ltm/pool", payload)
    return json.dumps(data, indent=2)
```

### Mounting MCP + REST Together

The app uses Starlette as the root application to mount both the MCP server and the FastAPI REST API under different paths:

```python
# MCP streamable-HTTP app
mcp_app = mcp.streamable_http_app()

# Main Starlette app
app = Starlette(
    lifespan=lifespan,
    routes=[
        Route("/health", health),
        Mount("/mcp", app=mcp_app),    # MCP tools for kagent
        Mount("/", app=rest_app),       # REST API + Swagger docs
    ],
)
```

The lifespan handler initializes the F5 token manager on startup and triggers the MCP sub-app's lifespan to set up its async task group:

```python
@asynccontextmanager
async def lifespan(app):
    tm = F5TokenManager(host=settings.F5_HOST, ...)
    await tm.login()
    set_token_manager(tm)
    async with mcp_app.router.lifespan_context(mcp_app):
        yield
    await tm.logout()
```

### Configuration

All configuration is via environment variables, loaded by Pydantic Settings:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `F5_HOST` | Yes | — | BIG-IP management URL |
| `F5_USERNAME` | No | `admin` | iControl REST username |
| `F5_PASSWORD` | Yes | — | iControl REST password |
| `F5_VERIFY_SSL` | No | `false` | Verify F5 SSL certificate |
| `F5_PARTITION` | No | `Common` | Default BIG-IP partition |
| `ALLOWED_PARTITIONS` | No | `Common` | Partition allow-list |
| `READ_ONLY` | No | `false` | Block all write operations |

## Part 2: The kagent Agent

The AI agent is defined as a Kubernetes CRD — a declarative `Agent` resource that tells kagent what the agent can do, which tools it has, and which operations need human approval.

### Agent CRD

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: f5-bigip-agent
  namespace: kagent
spec:
  description: "AI agent for managing F5 BIG-IP load balancer"
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      You are f5-bigip-agent, an expert AI assistant for managing
      the F5 BIG-IP load balancer.

      ## Behavioral Guidelines
      1. Always confirm destructive operations before executing
      2. Check dependencies before deleting (e.g., is a VS using this pool?)
      3. Check HA failover status before write operations
      4. Use tables for listing multiple resources
      ...
    tools:
      - type: McpServer
        mcpServer:
          kind: RemoteMCPServer
          name: f5-bigip-mcp
          namespace: kagent
```

### HITL Approval

The critical piece is `requireApproval` — this tells kagent that 10 destructive operations must get human approval before execution:

```yaml
requireApproval:
  - create_pool
  - delete_pool
  - add_pool_member
  - remove_pool_member
  - set_pool_member_state
  - create_virtual_server
  - delete_virtual_server
  - create_node
  - delete_node
  - set_node_state
```

When the LLM decides to call one of these tools, kagent pauses execution and sends an approval request back through the A2A protocol. The Telegram bot renders this as Approve/Reject buttons.

### A2A Skills

The agent also advertises its capabilities via A2A skills, so other agents or clients can discover what it does:

```yaml
a2aConfig:
  skills:
    - id: f5-bigip-operations
      name: F5 BIG-IP Operations
      description: "Manage pools, virtual servers, nodes, monitors,
                    and system status on F5 BIG-IP"
      examples:
        - "Show me all pools on the F5"
        - "Disable member 10.0.1.25:80 in pool prod-web"
        - "What is the failover status of the BIG-IP?"
```

## Part 3: The Telegram Bot

The Telegram bot is the same Python bot I built for [general kagent operations](/articles/2026-03-13-telegram-bot-kagent-a2a-kubernetes/), redeployed with a different environment variable pointing it at the F5 agent:

```yaml
env:
  - name: TELEGRAM_BOT_TOKEN
    valueFrom:
      secretKeyRef:
        name: telegram-f5-bot-token
        key: TELEGRAM_BOT_TOKEN
  - name: KAGENT_A2A_URL
    value: "http://kagent-controller.kagent.svc.cluster.local:8083/api/a2a/kagent/f5-bigip-agent/"
```

That's it — same bot image (`sebbycorp/telegram-kagent-bot:latest`), different agent URL. The bot polls Telegram for messages, sends them to the F5 agent via A2A, and streams the response back to the chat. When a HITL approval is needed, it shows inline Approve/Reject buttons.

The deployment uses `strategy: Recreate` because Telegram only allows one poller per bot token.

## Part 4: Kubernetes Deployment

The entire stack is deployed via GitOps. The manifests live in the `k8s-iceman` repo under `manifests/kagent-examples/`:

```
manifests/kagent-examples/
├── f5-agent/
│   └── bigip/
│       ├── 01-external-secret.yaml   # F5 creds from Vault
│       ├── 02-agent.yaml             # kagent Agent CRD
│       └── 03-deployment.yaml        # Deployment + Service + MCP + NetworkPolicy
└── telegram-f5-bot/
    ├── 01-external-secret.yaml       # Telegram token from Vault
    └── 02-deployment.yaml            # Telegram bot Deployment
```

ArgoCD watches this directory and auto-syncs any changes.

### Secrets from Vault

F5 credentials are stored in HashiCorp Vault and injected via External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: f5-bigip-credentials
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: f5-bigip-credentials
  data:
    - secretKey: F5_HOST
      remoteRef:
        key: secret/f5
        property: host
    - secretKey: F5_USERNAME
      remoteRef:
        key: secret/f5
        property: username
    - secretKey: F5_PASSWORD
      remoteRef:
        key: secret/f5
        property: password
```

### Network Policy

The wrapper is locked down with a NetworkPolicy that only allows ingress from the kagent namespace and egress to the F5 management IP + DNS:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: f5-wrapper-bigip-policy
spec:
  podSelector:
    matchLabels:
      app: f5-wrapper-bigip
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kagent
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
      ports:
        - protocol: TCP
          port: 443
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
```

## Safety Guardrails

This is network infrastructure — you don't want an AI agent accidentally deleting a production pool. Here are the layers of safety built in:

| Layer | Guardrail |
|-------|-----------|
| **Agent** | System prompt instructs the LLM to confirm before destructive ops, check dependencies, verify HA status |
| **kagent** | `requireApproval` on 10 destructive tools — execution pauses until human approves |
| **Telegram** | HITL approval rendered as inline Approve/Reject buttons |
| **Wrapper** | `READ_ONLY=true` mode blocks all write operations at the API level |
| **Wrapper** | `ALLOWED_PARTITIONS` restricts which F5 partitions can be accessed |
| **Network** | NetworkPolicy limits which pods can reach the wrapper and where the wrapper can connect |

## What It Looks Like in Practice

Here's a typical conversation flow:

**You** (in Telegram): "Show me all pools on the F5"

**Agent**: Lists pools in a clean table with member counts, monitors, and load balancing methods.

**You**: "Disable member 10.0.1.50:80 in pool k8s-argocd"

**Agent**: "I'll disable member 10.0.1.50:80 in pool k8s-argocd. This will stop it from receiving new connections but allow existing connections to drain."

**Telegram shows**: `[Approve] [Reject]` buttons

**You**: Tap `Approve`

**Agent**: "Done. Member 10.0.1.50:80 in pool k8s-argocd is now disabled (session: user-disabled, state: user-up)."

## CI/CD

A GitHub Actions workflow automatically builds and pushes the `f5-wrapper` Docker image to Docker Hub whenever files in `apps/f5-wrapper/` change on `main`. PRs build the image for validation but don't push.

## Wrapping Up

This project brings together several patterns that I think are the future of infrastructure management:

- **MCP as the integration layer** — instead of writing bespoke integrations, wrap existing APIs as MCP servers and let any AI agent discover and use them
- **kagent for agent lifecycle** — define agents as Kubernetes CRDs, manage them with GitOps, get HITL approval for free
- **A2A for agent communication** — the Telegram bot doesn't know anything about F5; it just speaks A2A to kagent, which routes to the right agent
- **Defense in depth** — read-only mode, partition allow-lists, HITL approval, network policies, and agent-level behavioral guidelines

The F5 wrapper has 28 tools covering pools, virtual servers, nodes, monitors, iRules, certificates, and system operations. You could extend it with more tools (data groups, policies, WAF rules) by adding more `@mcp.tool()` functions — kagent discovers them automatically.

The full source code is available in the [k8s-iceman](https://github.com/ProfessorSeb/k8s-iceman) repository:
- F5 wrapper: `apps/f5-wrapper/`
- Agent manifests: `manifests/kagent-examples/f5-agent/`
- Telegram bot manifests: `manifests/kagent-examples/telegram-f5-bot/`
