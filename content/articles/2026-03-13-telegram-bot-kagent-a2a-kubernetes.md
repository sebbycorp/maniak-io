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
  - HITL
---

# Building a Telegram Bot for Your Kubernetes Cluster with kagent and A2A

**By Sebastian Maniak**

What if you could manage your Kubernetes cluster from Telegram? Not through a half-baked webhook that runs `kubectl` — but through a real AI agent that understands context, uses tools, responds intelligently, and **asks for your approval before doing anything destructive**?

In this article, I'll walk you through how I built exactly that: a Telegram bot that connects to a [kagent](https://kagent.dev) AI agent running on my home lab Kubernetes cluster (Talos Linux on Proxmox), giving me full cluster operations from my phone. The entire thing is deployed via GitOps with ArgoCD, secrets come from HashiCorp Vault, and the bot uses the **A2A (Agent-to-Agent) protocol** to communicate with kagent.

The bot maintains **conversation continuity** across messages (so the agent remembers what you were talking about), and supports **Human-in-the-Loop (HITL) approval** — when the agent wants to run a destructive operation like deleting a resource or applying a manifest, it shows you Approve/Reject buttons in Telegram before proceeding.

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
│              │                          │                            │
│              │   Tracks contextId per   │                            │
│              │   Telegram user for      │                            │
│              │   session continuity     │                            │
│              └────────────┬─────────────┘                            │
│                           │ HTTP POST (A2A JSON-RPC)                │
│                           │ message/send + contextId                │
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
│              │  + long-term memory     │      └──────────────────┘ │
│              │  + context compaction   │           │               │
│              └──────────────────────────┘ ┌────────┴──────────┐   │
│                                           │  Tools:            │   │
│                      Response states:     │  • k8s_get_resources│  │
│                      • completed          │  • k8s_create_resource│ │
│                      • input-required     │  • k8s_apply_manifest│  │
│                        (HITL approval)    │  • k8s_delete_resource│ │
│                                           │  • k8s_get_pod_logs│   │
│                                           │  • k8s_scale       │   │
│                                           └────────────────────┘   │
│                                                                     │
│  ┌───────────────┐    ┌──────────────────┐                          │
│  │  Vault        │───▶│ ExternalSecret   │──▶ telegram-bot-token   │
│  │  secret/      │    │ Operator         │                          │
│  │  telegram     │    └──────────────────┘                          │
│  └───────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

The key insight: **the Telegram bot doesn't talk to the LLM directly**. It sends messages to the kagent controller's A2A endpoint, which routes them to the correct agent. The agent handles LLM orchestration, tool invocation, and response generation. The bot is a transport layer that also handles **session tracking** (via `contextId`) and **HITL approval** (via Telegram inline keyboards).

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
     │  │       "kind": "message",│       │                                  │
     │  │       "contextId":      │       │                                  │
     │  │         "abc-123...",   │       │                                  │
     │  │       "parts": [{      │       │                                  │
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
     │  │     "contextId":        │       │                                  │
     │  │       "abc-123...",     │       │                                  │
     │  │     "status": {         │       │                                  │
     │  │       "state":          │       │                                  │
     │  │         "completed"     │       │                                  │
     │  │     },                  │       │                                  │
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

### Key things about kagent's A2A implementation

- The method is **`message/send`** (not `tasks/send` as in the older A2A draft spec)
- Parts use `"kind": "text"` (not `"type": "text"`)
- The URL pattern is `/api/a2a/{namespace}/{agent-name}/` — **trailing slash required**
- **Session continuity uses `contextId` inside the `message` object** — not `sessionId` in `params`
- Responses include a `status.state` field: `"completed"` for normal responses, `"input-required"` for HITL approval
- Completed responses have text in `result.artifacts[].parts[]`
- Input-required responses have data in `result.status.message.parts[]` and text in `result.history[]`

### Session Continuity with `contextId`

This is the most important (and least documented) part of kagent's A2A protocol. To maintain a conversation across multiple messages, you must include a `contextId` in the **message object** itself:

```json
{
  "jsonrpc": "2.0",
  "id": "unique-message-id",
  "method": "message/send",
  "params": {
    "message": {
      "role": "user",
      "kind": "message",
      "contextId": "previously-returned-context-id",
      "parts": [{"kind": "text", "text": "now scale it to 3 replicas"}]
    }
  }
}
```

On the first message, omit `contextId` — kagent will generate one and return it in `result.contextId`. Store that value and send it back on every subsequent message to continue the conversation.

If you don't send `contextId`, every message starts a fresh session and the agent won't remember what you were talking about.

### Response States

kagent A2A responses come in two states:

**`completed`** — The agent finished processing. The response text is in `artifacts`:

```json
{
  "result": {
    "contextId": "abc-123",
    "status": {"state": "completed"},
    "artifacts": [{"parts": [{"kind": "text", "text": "Here are your pods..."}]}]
  }
}
```

**`input-required`** — The agent needs human input before proceeding. This happens when a tool in the `requireApproval` list is about to be called. The response contains an `adk_request_confirmation` data part describing which tool and what arguments:

```json
{
  "result": {
    "contextId": "abc-123",
    "status": {
      "state": "input-required",
      "message": {
        "parts": [{
          "kind": "data",
          "data": {
            "name": "adk_request_confirmation",
            "args": {
              "originalFunctionCall": {
                "name": "k8s_create_resource",
                "args": {"namespace": "staging", "kind": "Namespace"}
              }
            }
          }
        }]
      }
    }
  }
}
```

To approve or reject, send a follow-up message with `"approved"` or `"rejected"` using the same `contextId`.

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

The `telegram-k8s-agent` is a kagent `Declarative` agent focused on K8s resource management. It has **long-term memory** (vector-backed via SQLite), **context compaction** for long conversations, and a **prompt template** with kagent's built-in safety guardrails:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: telegram-k8s-agent
  namespace: kagent
spec:
  description: "Kubernetes resource management agent accessible via Telegram bot"
  type: Declarative
  declarative:
    modelConfig: default-model-config
    a2aConfig:
      skills:
        - id: k8s-operations
          name: Kubernetes Operations
          description: "Create, apply, inspect, and manage Kubernetes resources"
          examples:
            - "Create a new staging namespace"
            - "Apply a deployment for nginx"
            - "What pods are running in the default namespace?"
            - "Show me the events in namespace kagent"
            - "Scale the nginx deployment to 3 replicas"
          tags:
            - kubernetes
            - operations
    # Long-term memory — remembers user preferences, namespaces, and
    # past operations across conversations (vector-backed via SQLite).
    memory:
      modelConfig: openai-embed
    # Context compaction — automatically summarizes older messages in long
    # conversations so the agent doesn't lose track during extended sessions.
    context:
      compaction:
        tokenThreshold: 120000
        eventRetentionSize: 80
        overlapSize: 8
    promptTemplate:
      dataSources:
        - kind: ConfigMap
          name: kagent-builtin-prompts
          alias: builtin
    systemMessage: |
      You are {{.AgentName}}, a Kubernetes resource management agent accessible via Telegram.

      {{include "builtin/safety-guardrails"}}
      {{include "builtin/tool-usage-best-practices"}}
      {{include "builtin/kubernetes-context"}}

      Your primary role is helping users create, apply, inspect, and manage Kubernetes resources.
      You can:
      - Create namespaces, deployments, services, configmaps, and other K8s resources
      - Apply YAML manifests to the cluster
      - Inspect running resources (pods, deployments, services, events, logs)
      - Scale deployments and manage rollouts
      - Describe resources and troubleshoot issues

      Guidelines:
      - Keep responses concise and well-formatted for Telegram chat
      - Use short code blocks for YAML and logs
      - Summarize large outputs — don't dump full resource lists
      - When creating resources, confirm the namespace and resource details before applying
      - Mutating operations (create, apply, delete, scale) require user approval — explain what you plan to do first

      Available tools: {{.ToolNames}}
    tools:
      - type: McpServer
        mcpServer:
          apiGroup: kagent.dev
          kind: RemoteMCPServer
          name: kagent-tool-server
          toolNames:
            # --- Read / Inspect ---
            - k8s_get_resources
            - k8s_describe_resource
            - k8s_get_pod_logs
            - k8s_get_events
            - k8s_get_resource_yaml
            - k8s_get_available_api_resources
            # --- Create / Apply / Mutate ---
            - k8s_create_resource
            - k8s_apply_manifest
            - k8s_delete_resource
            - k8s_scale
            - k8s_rollout
            - k8s_label_resource
            - k8s_annotate_resource
          requireApproval:
            - k8s_create_resource
            - k8s_apply_manifest
            - k8s_delete_resource
            - k8s_scale
```

Notable features:

- **`memory` with `openai-embed`**: The agent remembers context from past conversations using vector search. If you told it "I always work in the staging namespace" last week, it'll remember.
- **`context.compaction`**: Long Telegram conversations won't blow out the LLM context window. kagent automatically summarizes older messages when the token count exceeds 120k.
- **`promptTemplate` with `dataSources`**: Pulls in kagent's built-in safety guardrails and Kubernetes-aware prompts from a ConfigMap, so the system message stays DRY.
- **`requireApproval`**: The four mutating tools (`create`, `apply`, `delete`, `scale`) trigger HITL — the bot shows Approve/Reject buttons in Telegram before they execute.

### 3. The Bot Code

The bot is ~460 lines of Python using `python-telegram-bot` (polling mode) and `httpx` for A2A calls. It handles three main concerns: **A2A communication with session continuity**, **HITL approval flow via Telegram inline keyboards**, and **robust response parsing**.

Let's walk through it section by section.

#### A2A Communication

The core of the bot — sending messages to kagent and tracking `contextId` for session continuity:

```python
"""Telegram bot that forwards messages to a kagent A2A agent."""

import asyncio
import json
import logging
import os
import uuid
from pathlib import Path

import httpx
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    MessageHandler,
    filters,
)

TELEGRAM_BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
KAGENT_A2A_URL = os.environ["KAGENT_A2A_URL"]

# Per-user contextId for conversation continuity (maps Telegram user_id -> kagent contextId)
user_contexts: dict[int, str] = {}

# Pending approval tasks: callback_id -> {context_id, user_id}
pending_approvals: dict[str, dict] = {}


async def _send_a2a_request(
    message_text: str,
    context_id: str | None = None,
) -> dict:
    """Send a message to the kagent A2A endpoint and return the raw result."""
    message = {
        "role": "user",
        "kind": "message",
        "messageId": str(uuid.uuid4()),
        "parts": [{"kind": "text", "text": message_text}],
    }
    if context_id:
        message["contextId"] = context_id

    payload = {
        "jsonrpc": "2.0",
        "id": message["messageId"],
        "method": "message/send",
        "params": {"message": message},
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(
            KAGENT_A2A_URL,
            json=payload,
            headers={"Content-Type": "application/json"},
        )
        resp.raise_for_status()
        data = resp.json()

    result = data.get("result", {})
    return result
```

The critical detail: `contextId` goes **inside the `message` object**, not in `params`. On the first message, we omit it — kagent returns a `contextId` in the result. We store that per Telegram user and send it on every subsequent message. This is what makes "tell me about nginx" followed by "now scale it to 3" work as a coherent conversation.

#### Response Parsing

kagent returns text in different locations depending on the response state. The bot tries three sources in order:

```python
def _extract_text(result: dict) -> str | None:
    """Extract text from an A2A task result (artifacts, history, or status message)."""
    # Check artifacts first (completed responses)
    artifacts = result.get("artifacts", [])
    if artifacts:
        parts = artifacts[-1].get("parts", [])
        texts = [p.get("text", "") for p in parts if p.get("kind") == "text" and p.get("text")]
        if texts:
            return "\n".join(texts)

    # Check history — last agent message with text parts
    for msg in reversed(result.get("history", [])):
        if msg.get("role") != "agent":
            continue
        texts = [p.get("text", "") for p in msg.get("parts", []) if p.get("kind") == "text" and p.get("text")]
        if texts:
            return "\n".join(texts)

    # Check status message
    for p in result.get("status", {}).get("message", {}).get("parts", []):
        if p.get("kind") == "text" and p.get("text"):
            return p["text"]

    return None
```

Why three sources? `completed` responses put text in `artifacts`. But `input-required` responses (HITL) don't have artifacts — the agent's explanatory text is in the `history` array. And some edge cases put short status messages in `status.message.parts`. Without this fallback chain, you'd get "Agent returned no text response" for perfectly valid HITL interactions.

#### HITL Approval Flow

When kagent returns `input-required`, the bot parses the `adk_request_confirmation` data to figure out what tool the agent wants to run, then shows Telegram inline keyboard buttons:

```python
def _parse_adk_confirmation(data: dict) -> dict | None:
    """Parse an adk_request_confirmation DataPart into a structured dict."""
    if data.get("name") == "adk_request_confirmation":
        args = data.get("args", {})
        func_call = args.get("originalFunctionCall", {})
        tool_name = func_call.get("name", "")
        tool_args = func_call.get("args", {})
        hint = args.get("toolConfirmation", {}).get("hint", "")

        if tool_name == "ask_user":
            questions = tool_args.get("questions", [])
            if isinstance(questions, str):
                questions = [{"question": questions}]
            return {"type": "ask_user", "tool_name": tool_name, "questions": questions, "hint": hint}

        return {"type": "approval", "tool_name": tool_name, "tool_args": tool_args, "hint": hint}

    return None
```

The bot classifies `input-required` responses into three categories:

1. **Approval** — A tool from the `requireApproval` list (e.g., `k8s_create_resource`). Shows Approve/Reject buttons.
2. **Ask user** — The agent is using `ask_user` to ask a clarifying question, sometimes with predefined choices.
3. **Question** — Generic fallback, prompts the user for free-text input.

When the user presses Approve, the bot sends `"approved"` back to kagent with the same `contextId`, and the agent proceeds to execute the tool:

```python
async def handle_callback(update: Update, _) -> None:
    """Handle inline keyboard button presses (approval and choice selection)."""
    query = update.callback_query
    await query.answer()

    data = query.data
    parts = data.split(":", 2)
    action = parts[0]
    callback_id = parts[1]

    approval = pending_approvals.pop(callback_id, None)
    if not approval:
        await query.edit_message_text("This action has expired or was already handled.")
        return

    context_id = approval.get("context_id", "")

    if action == "approve":
        await query.edit_message_text("Approved. Processing...")
        reply_text = "approved"
    elif action == "reject":
        await query.edit_message_text("Rejected.")
        reply_text = "rejected"
    elif action == "choice":
        choice_value = parts[2] if len(parts) > 2 else ""
        await query.edit_message_text(f"Selected: {choice_value}")
        reply_text = choice_value

    # Send the response back to kagent with the same contextId
    result = await send_a2a_message(reply_text, context_id)
    # ... handle the follow-up result
```

#### Message Handler

The main handler ties it all together — sends the user's text to kagent, stores the returned `contextId`, and dispatches to the right renderer:

```python
async def handle_message(update: Update, _) -> None:
    """Forward user message to kagent A2A and reply with the response."""
    user_id = update.effective_user.id
    user_text = update.message.text
    context_id = user_contexts.get(user_id)

    thinking_msg = await update.message.reply_text("Thinking...")

    try:
        result = await send_a2a_message(user_text, context_id)
        ctx = result.get("contextId")
        if ctx:
            user_contexts[user_id] = ctx
        await _handle_a2a_result(result, user_id, thinking_msg)
    except Exception as e:
        await thinking_msg.edit_text(f"Error contacting agent: {e}")
```

The `_handle_a2a_result` function checks `status.state` — if it's `input-required`, it renders the approval UI; otherwise, it sends the text response.

Key design decisions:

- **Polling, not webhooks**: No ingress, no public endpoint, no TLS termination. The bot makes outbound connections to Telegram's API from inside the cluster.
- **`contextId` per user**: Each Telegram user's conversation maps to a kagent `contextId`. The `/new` command clears it, starting a fresh session.
- **Inline keyboards for approvals**: Instead of making the user type "yes" or "no", the bot shows tappable buttons for HITL approval. Each button carries a callback ID that maps to the pending approval's `context_id`.
- **Chunked responses**: Telegram has a 4096-character message limit. Long agent responses are split into 4000-char chunks automatically.
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
          imagePullPolicy: Always
          env:
            - name: TELEGRAM_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: telegram-bot-token
                  key: TELEGRAM_BOT_TOKEN
            - name: KAGENT_A2A_URL
              value: "http://kagent-controller.kagent.svc.cluster.local:8083/api/a2a/kagent/telegram-k8s-agent/"
            - name: LOG_LEVEL
              value: "INFO"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            exec:
              command:
                - python
                - -c
                - "import os; assert os.path.exists('/tmp/bot-healthy')"
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            exec:
              command:
                - python
                - -c
                - "import os; assert os.path.exists('/tmp/bot-healthy')"
            initialDelaySeconds: 10
            periodSeconds: 15
```

The `Recreate` strategy is important — Telegram's polling API doesn't support multiple consumers. If you use `RollingUpdate`, you'd briefly have two pods pulling the same messages.

---

## The HITL Approval Flow

This is the most interesting part of the bot. Here's what happens when you ask the agent to do something destructive:

```
┌──────────────┐                ┌──────────────┐               ┌──────────────┐
│   Telegram   │                │  Bot (Pod)   │               │ kagent A2A   │
│   User       │                │              │               │              │
└──────┬───────┘                └──────┬───────┘               └──────┬───────┘
       │                               │                              │
       │  "Create a staging namespace" │                              │
       │──────────────────────────────▶│                              │
       │                               │  message/send               │
       │                               │  (no contextId — first msg) │
       │                               │─────────────────────────────▶│
       │                               │                              │
       │                               │  status: input-required     │
       │                               │  contextId: abc-123         │
       │                               │  data: adk_request_         │
       │                               │    confirmation {           │
       │                               │      k8s_create_resource    │
       │                               │      namespace: staging     │
       │                               │    }                        │
       │                               │◀─────────────────────────────│
       │                               │                              │
       │  "The agent wants to run:     │                              │
       │   k8s_create_resource         │                              │
       │   namespace: staging"         │                              │
       │                               │                              │
       │  [ Approve ] [ Reject ]       │                              │
       │◀──────────────────────────────│                              │
       │                               │                              │
       │  *taps Approve*               │                              │
       │──────────────────────────────▶│                              │
       │                               │  message/send               │
       │                               │  contextId: abc-123         │
       │                               │  text: "approved"           │
       │                               │─────────────────────────────▶│
       │                               │                              │
       │                               │  status: completed          │
       │                               │  "Namespace staging created" │
       │                               │◀─────────────────────────────│
       │                               │                              │
       │  "Namespace staging created   │                              │
       │   successfully."              │                              │
       │◀──────────────────────────────│                              │
```

The same `contextId` is used throughout the entire flow — from the initial request, through the approval, to the final result. This means the agent maintains context even across HITL interactions. You can ask "now deploy nginx to that namespace" and it'll know you mean `staging`.

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

### 1. `contextId`, not `sessionId`

This was the biggest surprise. kagent's A2A protocol uses `contextId` for session continuity, and it must go **inside the `message` object** — not in `params`, not as a top-level field. The A2A spec and other implementations sometimes mention `sessionId` — kagent ignores it completely. I spent hours debugging why every message started a fresh conversation before diving into the [kagent source code](https://github.com/kagent-dev/kagent) and finding that `contextId` maps directly to kagent's internal session system.

```python
# WRONG — kagent ignores sessionId
payload = {
    "params": {
        "sessionId": "...",  # This does nothing
        "message": {...}
    }
}

# RIGHT — contextId goes inside the message object
payload = {
    "params": {
        "message": {
            "contextId": "...",  # This maintains the session
            "role": "user",
            "parts": [...]
        }
    }
}
```

### 2. `input-required` responses have no artifacts

When the agent needs approval (HITL), the response has `status.state: "input-required"` but **no `artifacts` array**. If you only parse `artifacts`, you'll get "Agent returned no text response" for every approval request. The agent's explanation text is in the `history` array (last agent message), and the approval data is in `status.message.parts` as a `data` kind part.

### 3. The trailing slash matters

The kagent A2A endpoint at `/api/a2a/kagent/telegram-k8s-agent` returns a **307 redirect** to `/api/a2a/kagent/telegram-k8s-agent/`. The `httpx` library (and most HTTP clients) won't follow redirects on POST requests by default — for good security reasons. Always include the trailing slash.

### 4. kagent uses `message/send`, not `tasks/send`

If you're reading the A2A spec or looking at other A2A implementations, be aware that kagent uses `message/send` as the method name. The older `tasks/send` method returns a `Method not found` error.

### 5. Parts use `kind`, not `type`

The A2A spec uses `"kind": "text"` for message parts. Some implementations and docs use `"type": "text"`. kagent expects `kind`.

### 6. Telegram message limits

Telegram enforces a 4096-character limit per message. If your agent returns a large response (like a full pod listing or verbose logs), you need to chunk it. The bot handles this automatically by splitting at 4000-character boundaries.

### 7. `Recreate` strategy, not `RollingUpdate`

Telegram's long-polling API delivers each update to exactly one consumer. With two pods running during a rolling update, you'd get duplicate responses or missed messages. `Recreate` ensures a clean handoff.

---

## Testing It

Once deployed, open Telegram and find your bot (the one you created with @BotFather):

1. **`/start`** — Shows available commands
2. **`/status`** — Checks connectivity to the kagent controller
3. **`/new`** — Resets your conversation session (clears `contextId`)
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

> **You:** Create a staging namespace
>
> **Bot:** The agent wants to run: k8s_create_resource
>   namespace: staging
>   kind: Namespace
>
> **[ Approve ]** **[ Reject ]**
>
> *You tap Approve*
>
> **Bot:** Namespace `staging` created successfully.

> **You:** Now deploy nginx to that namespace
>
> **Bot:** The agent wants to run: k8s_create_resource
>   namespace: staging
>   kind: Deployment
>   name: nginx
>   ...
>
> **[ Approve ]** **[ Reject ]**

Notice how the agent knows "that namespace" means `staging` — because the `contextId` maintained the conversation context across the approval interaction.

---

## What's Next

This is a foundation. From here you could:

- **Add more agents**: Create a `telegram-security-agent` with Kubescape tools, or a `telegram-istio-agent` with mesh-specific tools
- **Route by command**: Use different Telegram commands (`/k8s`, `/istio`, `/security`) to route to different kagent agents
- **Add image support**: kagent supports multi-modal parts — you could send screenshots of dashboards and ask "what's wrong here?"
- **Connect via AgentGateway**: Route the A2A traffic through [AgentGateway](https://agentgateway.dev) for rate limiting, authentication, and observability
- **Build other chat integrations**: The A2A protocol is platform-agnostic. Swap `python-telegram-bot` for `discord.py`, `slack-bolt`, or even a WhatsApp integration and the A2A layer stays exactly the same

The pattern works for any chat platform. The A2A protocol is the universal adapter.

---

*The full source code and Kubernetes manifests are in the [k8s-iceman](https://github.com/ProfessorSeb/k8s-iceman) repo under `apps/telegram-bot-src/` and `manifests/kagent-examples/telegram-bot/`.*
