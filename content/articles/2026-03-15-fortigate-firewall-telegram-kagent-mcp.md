---
title: "Managing FortiGate Firewalls from Telegram with AI, MCP, and kagent"
date: 2026-03-15T10:00:00-04:00
draft: false
categories:
  - Networking
  - AI
  - Agents
tags:
  - FortiGate
  - Fortinet
  - MCP
  - kagent
  - Telegram
  - A2A
  - HITL
  - Kubernetes
  - GitOps
  - Firewall
---

# Managing FortiGate Firewalls from Telegram with AI, MCP, and kagent

**By Sebastian Maniak**

What if you could query your FortiGate firewall from Telegram? Not by logging into the web UI or running CLI commands over SSH — but by asking an AI agent "show me all firewall policies" or "what VIPs are configured?" and getting a clean, summarized answer in seconds.

That's what I built. After wrapping my [F5 BIG-IP as an MCP server](/articles/2026-03-14-f5-bigip-mcp-server-telegram-kagent/) and managing it from Telegram, I wanted the same experience for my Fortinet firewall. In this article, I'll walk through how I deployed the [community FortiGate MCP server](https://github.com/alpadalar/fortigate-mcp-server) on Kubernetes, wired it up as a **kagent AI agent**, and connected it to a **Telegram bot** — giving me full conversational access to firewall policies, NAT rules, VIPs, address objects, routing tables, and system status from my phone.

Everything runs on my home lab Kubernetes cluster (Talos Linux on Proxmox), deployed via GitOps with ArgoCD, with secrets managed by HashiCorp Vault.

## Why Wrap a Firewall as an MCP Server?

FortiGate has a comprehensive REST API (`/api/v2/cmdb/...` and `/api/v2/monitor/...`), but it returns deeply nested JSON that's hard to parse at a glance. When you're on your phone and want a quick answer — "which policies allow traffic from the DMZ?" or "what's my NAT setup?" — you don't want to stare at raw JSON.

By wrapping FortiGate as an MCP server and letting an AI agent interpret the results, you get:

1. **Natural language queries** — ask questions in plain English, get summarized answers
2. **Automatic tool discovery** — kagent discovers all available FortiGate operations via MCP, no manual wiring
3. **HITL safety** — destructive operations (creating policies, modifying routes) require your explicit approval via Telegram buttons
4. **Conversational context** — follow-up questions work naturally ("show me policy 5" after listing all policies)

## Architecture

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
                                        │ fortigate-agent  │
                                        │ (LLM decides     │
                                        │  which tool)     │
                                        └────────┬─────────┘
                                                 │ MCP streamable-HTTP
                                                 ▼
                                        ┌──────────────────┐
                                        │ FortiGate MCP    │
                                        │ Server           │
                                        └────────┬─────────┘
                                                 │ FortiGate REST API
                                                 ▼
                                        ┌──────────────────┐
                                        │ FortiGate FW     │
                                        └──────────────────┘
```

Four components, each running as a separate pod in the `kagent` namespace:

- **Telegram Bot** — polls for messages, sends them to kagent via A2A, renders HITL approval buttons
- **kagent Controller** — routes the request to the correct agent, manages conversation state
- **fortigate-agent** — the AI agent (LLM) that decides which MCP tools to call based on your question
- **FortiGate MCP Server** — translates MCP tool calls into FortiGate REST API calls

## Part 1: The FortiGate MCP Server

Rather than writing a custom wrapper from scratch, I used the excellent [fortigate-mcp-server](https://github.com/alpadalar/fortigate-mcp-server) community project. It's a well-structured Python application built on FastMCP that exposes 28+ tools across six categories.

### Tool Inventory

| Category | Tools | What They Do |
|----------|-------|-------------|
| **Device** | 6 | List devices, test connectivity, get system status, discover VDOMs |
| **Firewall** | 5 | List, create, update, delete policies; get policy details |
| **Network** | 4 | List/create address objects and service objects |
| **Routing** | 7 | Static routes, routing table, interfaces, interface status |
| **Virtual IPs** | 5 | List, create, update, delete VIPs; get VIP details |
| **System** | 2+ | Health checks, connection tests, schema info |

### Multi-Device Support

One of the nice features of this MCP server is multi-device support. Each tool takes a `device_id` parameter, so you can manage multiple FortiGate appliances from a single server instance. The configuration file defines your device inventory:

```json
{
  "fortigate": {
    "devices": {
      "primary": {
        "host": "172.16.10.1",
        "port": 443,
        "api_token": "your-api-token",
        "vdom": "root",
        "verify_ssl": false,
        "timeout": 30
      }
    }
  }
}
```

### Authentication

FortiGate supports two auth methods — API tokens and username/password. I use API tokens because they don't expire (unless revoked) and avoid the session management complexity. You generate one in the FortiGate GUI under **System > Administrators > REST API Admin**.

### Containerization

I built a custom Docker image that generates the `config.json` from environment variables at startup. This lets Kubernetes secrets flow cleanly into the container without baking credentials into the image:

```bash
#!/bin/bash
cat > /app/config/config.json <<EOF
{
  "fortigate": {
    "devices": {
      "primary": {
        "host": "${FORTI_HOST}",
        "port": ${FORTI_PORT:-443},
        "api_token": "${FORTI_TOKEN}",
        "vdom": "${FORTI_VDOM:-root}",
        "verify_ssl": false,
        "timeout": 30
      }
    }
  }
}
EOF
exec python -m src.fortigate_mcp.server_http \
  --host 0.0.0.0 --port 8080 --path /mcp \
  --config /app/config/config.json
```

### MCP Transport: Streamable HTTP

A key detail — kagent uses the **Streamable HTTP** MCP transport, not the older SSE transport. The server needs to call `mcp.streamable_http_app()` (not `mcp.sse_app()`) and initialize the MCP task group via a Starlette lifespan handler:

```python
mcp_app = self.mcp.streamable_http_app()

@asynccontextmanager
async def lifespan(a):
    async with mcp_app.router.lifespan_context(mcp_app):
        yield

app = Starlette(
    lifespan=lifespan,
    routes=[
        Route("/health", health_endpoint),
        Mount("/mcp", app=mcp_app),
    ],
)
```

This exposes the MCP endpoint at `/mcp/mcp` — kagent POSTs JSON-RPC requests to this URL to discover and invoke tools.

## Part 2: The kagent Agent

The agent is defined as a Kubernetes CRD. It tells kagent what the agent can do, which MCP tools it has access to, and which operations need human approval.

### Agent CRD

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: fortigate-agent
  namespace: kagent
spec:
  description: "AI agent for managing FortiGate firewall"
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      You are fortigate-agent, an expert AI assistant
      for managing a FortiGate firewall.

      All tools require a device_id parameter.
      The configured device is called "primary".
      Always pass device_id="primary" when calling any tool.

      ## Behavioral Guidelines
      1. Confirm destructive operations before executing
      2. Present data clearly with tables
      3. Flag overly permissive policies (all/all/accept)
      4. Explain FortiGate API errors in plain language
    tools:
      - type: McpServer
        mcpServer:
          kind: RemoteMCPServer
          name: fortigate-mcp
          namespace: kagent
```

### HITL Approval for Destructive Operations

Read operations (listing policies, viewing routes) execute immediately. But anything that modifies the firewall requires your explicit approval:

```yaml
requireApproval:
  - create_firewall_policy
  - update_firewall_policy
  - delete_firewall_policy
  - create_address_object
  - create_service_object
  - create_static_route
  - update_static_route
  - delete_static_route
  - create_virtual_ip
  - update_virtual_ip
  - delete_virtual_ip
```

When the LLM decides to call one of these tools, kagent pauses execution and sends an approval request back through A2A. The Telegram bot renders this as inline Approve/Reject buttons — you tap to decide.

### MCP Tool Discovery

The `RemoteMCPServer` CRD points kagent at the FortiGate MCP server's endpoint:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: fortigate-mcp
  namespace: kagent
spec:
  url: "http://fortigate-mcp-server.kagent:8080/mcp/mcp"
  timeout: "30s"
  sseReadTimeout: "5m0s"
```

kagent automatically connects, discovers all available tools, and makes them available to the agent. No manual tool registration needed.

## Part 3: The Telegram Bot

The Telegram bot is the same Python bot I use for all my kagent agents. It reuses the `sebbycorp/telegram-kagent-bot:latest` image — the only thing that changes between agents is the `KAGENT_A2A_URL` environment variable:

```yaml
env:
  - name: TELEGRAM_BOT_TOKEN
    valueFrom:
      secretKeyRef:
        name: telegram-forti-bot-token
        key: TELEGRAM_BOT_TOKEN
  - name: KAGENT_A2A_URL
    value: "http://kagent-controller.kagent.svc.cluster.local:8083/api/a2a/kagent/fortigate-agent/"
```

Same image, different agent. The bot handles:

- **Message routing** — sends user messages to the FortiGate agent via A2A
- **Response rendering** — formats the agent's response (tables, summaries) for Telegram's 4000-char message limit
- **HITL approval** — renders Approve/Reject inline buttons when the agent needs permission for a destructive operation
- **Conversation context** — maintains per-user context IDs so follow-up questions work naturally

The deployment uses `strategy: Recreate` because Telegram only allows one poller per bot token.

## Part 4: Kubernetes Deployment

The entire stack is deployed via GitOps. The manifests live in the `k8s-iceman` repo:

```
manifests/kagent-examples/
├── fortigate-agent/
│   ├── 01-external-secret.yaml   # FortiGate creds from Vault
│   ├── 02-agent.yaml             # kagent Agent CRD
│   └── 03-deployment.yaml        # Deployment + Service + MCP + NetworkPolicy
└── telegram-forti-bot/
    ├── 01-external-secret.yaml   # Telegram token from Vault
    └── 02-deployment.yaml        # Telegram bot Deployment
```

ArgoCD watches this directory and auto-syncs any changes. Push to `main` and the stack deploys itself.

### Secrets from Vault

FortiGate credentials are stored in HashiCorp Vault and synced to Kubernetes via External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fortigate-credentials
  namespace: kagent
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: fortigate-credentials
  data:
    - secretKey: FORTI_TOKEN
      remoteRef:
        key: fortigate
        property: forti_token
    - secretKey: FORTI_HOST
      remoteRef:
        key: fortigate
        property: host
```

The Telegram bot token comes from a separate Vault path:

```yaml
data:
  - secretKey: TELEGRAM_BOT_TOKEN
    remoteRef:
      key: secret/telegram
      property: fortiaikagentbot_key
```

### Network Policy

The MCP server is locked down — only pods in the kagent namespace can reach it, and it can only talk to the FortiGate management IP and DNS:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fortigate-mcp-server-policy
spec:
  podSelector:
    matchLabels:
      app: fortigate-mcp-server
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
            cidr: 172.16.0.0/12
      ports:
        - protocol: TCP
          port: 443
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
```

## What It Looks Like in Practice

Here are some example conversations:

**You**: "Show me all firewall policies"

**Agent**: Returns a table with policy ID, name, source/destination interfaces, addresses, services, action, and NAT status.

**You**: "What VIPs are configured?"

**Agent**: Lists all Virtual IP mappings with external IP, mapped IP, port forwarding settings, and associated interfaces.

**You**: "Show me the routing table"

**Agent**: Displays the active routing table with destinations, gateways, interfaces, and metrics.

**You**: "Create an address object called test-server with IP 10.0.5.100/32"

**Agent**: "I'll create an address object 'test-server' with type 'ipmask' and address '10.0.5.100/32'."

**Telegram shows**: `[Approve] [Reject]` buttons

**You**: Tap `Approve`

**Agent**: "Address object 'test-server' created successfully."

## Safety Guardrails

This is network security infrastructure — the safety layers matter:

| Layer | Guardrail |
|-------|-----------|
| **Agent** | System prompt instructs the LLM to confirm destructive ops, flag overly permissive policies |
| **kagent** | `requireApproval` on 11 write operations — execution pauses until human approves |
| **Telegram** | HITL approval rendered as inline Approve/Reject buttons |
| **FortiGate** | API token scoped to specific admin profile with limited permissions |
| **Network** | NetworkPolicy restricts who can reach the MCP server and where it can connect |

## Lessons Learned

A few things I ran into while building this:

**MCP transport matters.** kagent uses Streamable HTTP, not SSE. If your MCP server only serves the older SSE transport, kagent will fail with "Method Not Allowed" on POST. Use `mcp.streamable_http_app()` and initialize the task group via a Starlette lifespan.

**Lifespan initialization is required.** The Streamable HTTP app needs `async with mcp_app.router.lifespan_context(mcp_app)` in your Starlette lifespan handler. Without it, you get "Task group is not initialized" errors.

**Device ID is a required parameter.** Every tool in the community MCP server requires a `device_id`. Make sure your agent's system prompt tells the LLM to always pass `device_id="primary"` (or whatever you named your device in the config).

**Vault key paths depend on the ClusterSecretStore.** If your ESO ClusterSecretStore has `path: "secret"` configured, the ExternalSecret key should be just `fortigate`, not `secret/fortigate` — the provider prepends the path automatically.

## Wrapping Up

This project reinforces the same patterns I've been exploring with [F5 BIG-IP](/articles/2026-03-14-f5-bigip-mcp-server-telegram-kagent/):

- **MCP as the universal integration layer** — wrap any API as an MCP server and let AI agents discover and use it
- **kagent for agent lifecycle on Kubernetes** — define agents as CRDs, deploy with GitOps, get HITL approval for free
- **A2A for agent communication** — the Telegram bot is agent-agnostic; it speaks A2A to kagent, which routes to the right agent
- **Reusable bot pattern** — same Telegram bot image, different `KAGENT_A2A_URL`, instant new agent interface

The FortiGate MCP server gives you 28+ tools covering device management, firewall policies, network objects, routing, VIPs, and system monitoring. And because it's MCP, adding more tools is just adding more functions — kagent discovers them automatically.

The full source code is available in the [k8s-iceman](https://github.com/ProfessorSeb/k8s-iceman) repository:
- FortiGate MCP server modifications: `apps/fortigate-wrapper-src/`
- Agent manifests: `manifests/kagent-examples/fortigate-agent/`
- Telegram bot manifests: `manifests/kagent-examples/telegram-forti-bot/`
