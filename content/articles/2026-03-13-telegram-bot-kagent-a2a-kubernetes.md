---
title: "Building a Telegram Bot for Your Kubernetes Cluster with kagent and A2A"
date: 2026-03-13T14:00:00-04:00
draft: false
categories:
  - Kubernetes
  - AI
  - Agents
tags:
  - kagent
  - Telegram
  - A2A
  - MCP
  - GitOps
  - ArgoCD
  - Vault
---

# Building a Telegram Bot for Your Kubernetes Cluster with kagent and A2A

**By Sebastian Maniak**

What if you could manage your Kubernetes cluster from Telegram? Not through a half-baked webhook that runs `kubectl` — but through a real AI agent that understands context, uses tools, and responds intelligently?

In this article, I'll walk you through how I built exactly that: a Telegram bot that connects to a [kagent](https://kagent.dev) AI agent running on my home lab Kubernetes cluster (Talos Linux on Proxmox), giving me full cluster operations from my phone. The entire thing is deployed via GitOps with ArgoCD, secrets come from HashiCorp Vault, and the bot uses the **A2A (Agent-to-Agent) protocol** to communicate with kagent.

No webhooks. No public endpoints. Just polling from inside the cluster.

---

## Architecture Overview

Here's what we're building:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Telegram Cloud                               │
│                    ┌──────────────────┐                              │
│                    │  Telegram Bot API │                             │
│                    └────────┬─────────┘                              │
│                             │ Long Polling                          │
└─────────────────────────────┼───────────────────────────────────────┘
                              │
┌─────────────────────────────┼───────────────────────────────────────┐
│  Kubernetes Cluster         │                                       │
│  (maniak-iceman)            ▼                                       │
│              ┌──────────────────────────┐                            │
│              │   telegram-bot (Pod)     │                            │
│              │   python-telegram-bot    │                            │
│              │   + httpx               │                            │
│              └────────────┬─────────────┘                            │
│                           │ HTTP POST (A2A JSON-RPC)                │
│                           │ message/send                            │
│                           ▼                                         │
│              ┌──────────────────────────┐                            │
│              │  kagent-controller       │                            │
│              │  :8083/api/a2a/kagent/   │                            │
│              │  telegram-k8s-agent/     │                            │
│              └────────────┬─────────────┘                            │
│                           │ Routes to Agent                         │
│                           ▼                                         │
│              ┌──────────────────────────┐      ┌──────────────────┐ │
│              │ telegram-k8s-agent (Pod) │─────▶│ kagent-tool-     │ │
│              │  LLM: gpt-5.4           │ MCP  │ server (Pod)     │ │
│              │  Agent CRD              │◀─────│ :8084/mcp        │ │
│              └──────────────────────────┘      └──────────────────┘ │
│                                                     │               │
│                                          ┌──────────┴──────────┐   │
│                                          │  Tools:             │   │
│                                          │  • k8s_get_resources│   │
│                                          │  • k8s_get_pod_logs │   │
│                                          │  • helm_list        │   │
│                                          │  • istio_*          │   │
│                                          │  • prometheus_*     │   │
│                                          └─────────────────────┘   │
│                                                                     │
│  ┌───────────────┐    ┌──────────────────┐                          │
│  │  Vault        │───▶│ ExternalSecret   │──▶ telegram-bot-token   │
│  │  secret/      │    │ Operator         │                          │
│  │  telegram     │    └──────────────────┘                          │
│  └───────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

The key insight: **the Telegram bot doesn't talk to the LLM directly**. It sends messages to the kagent controller's A2A endpoint, which routes them to the correct agent. The agent handles LLM orchestration, tool invocation, and response generation. The bot is just a thin transport layer.

---

## The A2A Protocol

[A2A (Agent-to-Agent)](https://google.github.io/A2A/) is a Google-backed open protocol for agent interoperability. kagent implements A2A on its controller, meaning any A2A-compatible client can talk to any kagent agent.

The protocol uses JSON-RPC 2.0 over HTTP. Here's what a message exchange looks like:

```
┌──────────┐                    ┌───────────────────┐                ┌─────────────┐
│ Telegram │                    │ kagent-controller  │                │ Agent Pod   │
│ Bot Pod  │                    │ (A2A endpoint)     │                │ + LLM + MCP │
└────┬─────┘                    └─────────┬──────────┘                └──────┬──────┘
     │                                    │                                  │
     │  POST /api/a2a/kagent/             │                                  │
     │       telegram-k8s-agent/          │                                  │
     │  ┌─────────────────────────┐       │                                  │
     │  │ {                       │       │                                  │
     │  │   "jsonrpc": "2.0",     │       │                                  │
     │  │   "method":             │       │                                  │
     │  │     "message/send",     │       │                                  │
     │  │   "params": {           │       │                                  │
     │  │     "message": {        │       │                                  │
     │  │       "role": "user",   │       │                                  │
     │  │       "parts": [{       │       │                                  │
     │  │         "kind": "text", │       │                                  │
     │  │         "text": "list   │       │                                  │
     │  │           my pods"      │       │                                  │
     │  │       }]                │       │                                  │
     │  │     }                   │       │                                  │
     │  │   }                     │       │                                  │
     │  │ }                       │       │                                  │
     │  └─────────────────────────┘       │                                  │
     │ ──────────────────────────────────▶│                                  │
     │                                    │  Forward to agent                │
     │                                    │─────────────────────────────────▶│
     │                                    │                                  │
     │                                    │              LLM + Tool calls    │
     │                                    │              (k8s_get_resources) │
     │                                    │                                  │
     │                                    │◀─────────────────────────────────│
     │ ◀──────────────────────────────────│  Response with artifacts         │
     │  ┌─────────────────────────┐       │                                  │
     │  │ {                       │       │                                  │
     │  │   "result": {           │       │                                  │
     │  │     "artifacts": [{     │       │                                  │
     │  │       "parts": [{       │       │                                  │
     │  │         "kind": "text", │       │                                  │
     │  │         "text": "Here   │       │                                  │
     │  │           are your      │       │                                  │
     │  │           pods: ..."    │       │                                  │
     │  │       }]                │       │                                  │
     │  │     }]                  │       │                                  │
     │  │   }                     │       │                                  │
     │  │ }                       │       │                                  │
     │  └─────────────────────────┘       │                                  │
     │                                    │                                  │
```

A few things to note about kagent's A2A implementation:

- The method is **`message/send`** (not `tasks/send` as in the older A2A draft spec)
- Parts use `"kind": "text"` (not `"type": "text"`)
- The URL pattern is `/api/a2a/{namespace}/{agent-name}/` — **trailing slash required**
- Responses come back in `result.artifacts[].parts[]`

---

## The Components

### 1. ExternalSecret — Pulling the Bot Token from Vault

The Telegram bot token lives in HashiCorp Vault at `secret/telegram` with key `api_key`. The External Secrets Operator syncs it into a Kubernetes secret:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: telegram-bot-token
  namespace: kagent
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: telegram-bot-token
    creationPolicy: Owner
  data:
    - secretKey: TELEGRAM_BOT_TOKEN
      remoteRef:
        key: telegram
        property: api_key
```

This follows the same pattern as the existing `kagent-openai` and `kagent-anthropic` secrets in the cluster. No hardcoded tokens in Git.

### 2. The Agent CRD

The `telegram-k8s-agent` is a standard kagent `Declarative` agent. It references the `kagent-tool-server` RemoteMCPServer for Kubernetes, Helm, Istio, and Prometheus tools:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: telegram-k8s-agent
  namespace: kagent
spec:
  description: "Kubernetes operations agent accessible via Telegram bot"
  type: Declarative
  declarative:
    modelConfig: default-model-config
    a2aConfig:
      skills:
        - id: k8s-operations
          name: Kubernetes Operations
          description: "Query, manage, and troubleshoot Kubernetes resources"
          examples:
            - "What pods are running in the default namespace?"
            - "Show me the logs for pod X"
            - "What Helm releases are installed?"
          tags: [kubernetes, operations]
        - id: cluster-monitoring
          name: Cluster Monitoring
          description: "Query Prometheus metrics and monitor cluster health"
          examples:
            - "What is the CPU usage across nodes?"
          tags: [monitoring, prometheus]
    systemMessage: |
      You are a Kubernetes operations agent accessible via Telegram.
      Keep responses concise and well-formatted for chat readability.
    tools:
      - type: McpServer
        mcpServer:
          apiGroup: kagent.dev
          kind: RemoteMCPServer
          name: kagent-tool-server
          toolNames:
            - k8s_get_resources
            - k8s_describe_resource
            - k8s_get_pod_logs
            - k8s_get_events
            - helm_list_releases
            - helm_get_release
            - istio_proxy_status
            - istio_version
            - prometheus_query_tool
            - datetime_get_current_time
          requireApproval:
            - k8s_delete_resource
            - k8s_apply_manifest
            - helm_upgrade
            - helm_uninstall
```

The `a2aConfig.skills` section tells other A2A clients what this agent can do. The `requireApproval` list ensures destructive operations go through Human-in-the-Loop approval in the kagent UI before executing.

### 3. The Bot Code

The bot is ~120 lines of Python using `python-telegram-bot` (polling mode) and `httpx` for A2A calls:

```python
"""Telegram bot that forwards messages to a kagent A2A agent."""

import logging, os, uuid
from pathlib import Path
import httpx
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters

TELEGRAM_BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
KAGENT_A2A_URL = os.environ["KAGENT_A2A_URL"]

async def send_a2a_task(message_text: str, session_id: str) -> str:
    """Send a message to the kagent A2A endpoint and return the response."""
    task_id = str(uuid.uuid4())
    payload = {
        "jsonrpc": "2.0",
        "id": task_id,
        "method": "message/send",
        "params": {
            "id": task_id,
            "message": {
                "role": "user",
                "parts": [{"kind": "text", "text": message_text}],
            },
        },
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(KAGENT_A2A_URL, json=payload,
                                 headers={"Content-Type": "application/json"})
        resp.raise_for_status()
        data = resp.json()

    result = data.get("result", {})
    artifacts = result.get("artifacts", [])
    if artifacts:
        parts = artifacts[-1].get("parts", [])
        texts = [p.get("text", "") for p in parts if p.get("kind") == "text"]
        if texts:
            return "\n".join(texts)

    return "Agent returned no text response."

# Per-user session tracking
user_sessions: dict[int, str] = {}

def get_session(user_id: int) -> str:
    if user_id not in user_sessions:
        user_sessions[user_id] = str(uuid.uuid4())
    return user_sessions[user_id]

async def handle_message(update: Update, _) -> None:
    user_id = update.effective_user.id
    session_id = get_session(user_id)
    thinking_msg = await update.message.reply_text("Thinking...")

    try:
        response = await send_a2a_task(update.message.text, session_id)
        for i in range(0, len(response), 4000):  # Telegram 4096 char limit
            chunk = response[i : i + 4000]
            if i == 0:
                await thinking_msg.edit_text(chunk)
            else:
                await update.message.reply_text(chunk)
    except Exception as e:
        await thinking_msg.edit_text(f"Error contacting agent: {e}")

def main() -> None:
    app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("new", new_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    Path("/tmp/bot-healthy").touch()  # For k8s probes
    app.run_polling(drop_pending_updates=True)
```

Key design decisions:

- **Polling, not webhooks**: No ingress, no public endpoint, no TLS termination. The bot makes outbound connections to Telegram's API from inside the cluster.
- **Session per user**: Each Telegram user gets their own A2A session ID, so conversations have context continuity.
- **Chunked responses**: Telegram has a 4096-character message limit. Long agent responses are split automatically.
- **Health file**: A simple `/tmp/bot-healthy` file is created on startup for Kubernetes liveness/readiness probes.

### 4. The Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telegram-bot
  namespace: kagent
spec:
  replicas: 1
  strategy:
    type: Recreate    # Only one poller at a time
  template:
    spec:
      containers:
        - name: bot
          image: docker.io/sebbycorp/telegram-kagent-bot:latest
          env:
            - name: TELEGRAM_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: telegram-bot-token
                  key: TELEGRAM_BOT_TOKEN
            - name: KAGENT_A2A_URL
              value: "http://kagent-controller.kagent.svc.cluster.local:8083/api/a2a/kagent/telegram-k8s-agent/"
```

The `Recreate` strategy is important — Telegram's polling API doesn't support multiple consumers. If you use `RollingUpdate`, you'd briefly have two pods pulling the same messages.

---

## GitOps Flow

The entire deployment is managed through ArgoCD. Here's how changes flow:

```
┌─────────────┐     git push      ┌──────────────────┐
│ Developer   │ ─────────────────▶│ GitHub            │
│ (You)       │                   │ ProfessorSeb/     │
└─────────────┘                   │ k8s-iceman        │
                                  └────────┬──────────┘
                                           │
                              ArgoCD polls │ (3 min)
                                           ▼
                                  ┌──────────────────┐
                                  │ ArgoCD            │
                                  │ kagent-examples   │
                                  │ Application       │
                                  └────────┬──────────┘
                                           │
                              kubectl apply│
                                           ▼
                                  ┌──────────────────┐
                                  │ Kubernetes        │
                                  │ ├─ ExternalSecret │
                                  │ ├─ Agent CRD      │
                                  │ └─ Deployment     │
                                  └──────────────────┘
```

The repo structure:

```
k8s-iceman/
├── apps/
│   ├── kagent-examples.yaml          # ArgoCD Application (recurse: true)
│   └── telegram-bot-src/             # Bot source code
│       ├── Dockerfile
│       ├── main.py
│       └── requirements.txt
├── manifests/
│   └── kagent-examples/
│       └── telegram-bot/             # Picked up by ArgoCD automatically
│           ├── 01-external-secret.yaml
│           ├── 02-agent.yaml
│           └── 03-deployment.yaml
└── helm-values/
    └── kagent/
        └── values.yaml               # Model config (gpt-5.4)
```

Because the `kagent-examples` ArgoCD Application has `directory.recurse: true`, any new directory under `manifests/kagent-examples/` is automatically synced. No new ArgoCD Application needed.

---

## Gotchas and Lessons Learned

### 1. The trailing slash matters

The kagent A2A endpoint at `/api/a2a/kagent/telegram-k8s-agent` returns a **307 redirect** to `/api/a2a/kagent/telegram-k8s-agent/`. The `httpx` library (and most HTTP clients) won't follow redirects on POST requests by default — for good security reasons. Always include the trailing slash.

### 2. kagent uses `message/send`, not `tasks/send`

If you're reading the A2A spec or looking at other A2A implementations, be aware that kagent uses `message/send` as the method name. The older `tasks/send` method returns a `Method not found` error.

### 3. Parts use `kind`, not `type`

The A2A spec uses `"kind": "text"` for message parts. Some implementations and docs use `"type": "text"`. kagent expects `kind`.

### 4. Telegram message limits

Telegram enforces a 4096-character limit per message. If your agent returns a large response (like a full pod listing or verbose logs), you need to chunk it. The bot handles this automatically.

### 5. `Recreate` strategy, not `RollingUpdate`

Telegram's long-polling API delivers each update to exactly one consumer. With two pods running during a rolling update, you'd get duplicate responses or missed messages. `Recreate` ensures a clean handoff.

---

## Testing It

Once deployed, open Telegram and find your bot (the one you created with @BotFather):

1. **`/start`** — Shows available commands
2. **`/status`** — Checks connectivity to the kagent controller
3. **`/new`** — Resets your conversation session
4. **Send any message** — It goes to the agent and comes back with a real answer

Example interactions:

> **You:** What pods are running in kagent namespace?
>
> **Bot:** Here are the running pods in the kagent namespace:
> - kagent-controller-57864fdf69-xfgmr (1/1 Running)
> - telegram-bot-5469669bf-v8h7p (1/1 Running)
> - telegram-k8s-agent-5f696bf4b9-pl7cl (1/1 Running)
> - k8s-agent-6dccd8ddd8-gxt6x (1/1 Running)
> - ... (28 more pods)

> **You:** What helm releases are installed?
>
> **Bot:** Here are the Helm releases across all namespaces:
> - kagent (kagent) v0.8.0-beta6
> - vault (vault) v0.29.1
> - istio-base (istio-system) v1.25.2
> - ...

---

## What's Next

This is a foundation. From here you could:

- **Add more agents**: Create a `telegram-security-agent` with Kubescape tools, or a `telegram-istio-agent` with mesh-specific tools
- **Route by command**: Use different Telegram commands (`/k8s`, `/istio`, `/security`) to route to different kagent agents
- **Add image support**: kagent supports multi-modal parts — you could send screenshots of dashboards and ask "what's wrong here?"
- **Connect via AgentGateway**: Route the A2A traffic through [AgentGateway](https://agentgateway.dev) for rate limiting, authentication, and observability

The pattern works for any chat platform. Swap `python-telegram-bot` for `discord.py` or `slack-bolt` and the rest stays the same — the A2A protocol is the universal adapter.

---

*The full source code and Kubernetes manifests are in the [k8s-iceman](https://github.com/ProfessorSeb/k8s-iceman) repo under `apps/telegram-bot-src/` and `manifests/kagent-examples/telegram-bot/`.*
