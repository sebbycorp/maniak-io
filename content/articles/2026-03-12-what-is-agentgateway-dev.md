---
title: "What is agentgateway.dev? (And why it exists)"
date: 2026-03-12T07:10:00-04:00
draft: false
categories:
  - AI
  - Infrastructure
  - Security
tags:
  - agentgateway
  - MCP
  - A2A
  - LLM Gateway
  - Observability
  - RBAC
---

# What is agentgateway.dev? (And why it exists)

If you’re building **agentic AI** systems, you eventually hit the same wall:

- Your agents need **tools** (MCP servers, internal APIs, SaaS)
- They need to talk to **other agents** (A2A)
- They need to call **LLM providers** (often multiple)

…and suddenly “just use an API gateway” stops being a satisfying answer.

That’s what **agentgateway.dev** is about.

**agentgateway.dev** is the documentation hub for the open source **agentgateway** project — a connectivity data plane designed specifically for agent workloads.

Docs entry point (standalone):
https://agentgateway.dev/docs/standalone/latest/

Upstream repo:
https://github.com/agentgateway/agentgateway

---

## Why a new gateway for agents?

The docs put it bluntly: **traditional API gateways and reverse proxies aren’t built for MCP and A2A**.

Why?

Traditional gateways assume:
- stateless request/response
- one request → one backend
- client-initiated traffic only

But MCP/A2A introduces:
- **stateful JSON-RPC sessions** with long-lived connections
- **fan-out** across multiple tool servers
- **server-initiated events** (SSE) that must route back to the correct client session
- **per-session authorization** (different users/agents should see different tools)

In other words: the gateway needs to be protocol-aware and session-aware — not just path-aware.

---

## What agentgateway actually is (in one sentence)

Agentgateway is a unified **LLM + MCP + A2A gateway**, built for:
- enterprise-grade security
- observability
- resiliency
- multi-tenancy

And it’s implemented in **Rust** for performance and memory safety (important for long-lived, high-concurrency sessions).

---

## The three big product pillars

### 1) LLM Gateway

Agentgateway can route traffic to major LLM providers behind a **unified OpenAI-compatible API**, so you can switch providers without rewriting your application.

The docs also call out “native vs translation” support per provider/API, which is a real-world detail that matters when fields/models evolve quickly.

### 2) MCP Gateway

Agentgateway’s MCP features (from the docs):
- **Tool federation**: aggregate multiple MCP servers behind a single endpoint
- Multiple transports: stdio, HTTP/SSE, Streamable HTTP
- **OpenAPI integration**: expose existing REST APIs as MCP tools
- AuthN/AuthZ: MCP auth spec compliance + OAuth providers (Auth0, Keycloak)

This is where agentgateway becomes the “connective tissue” between LLMs and tools.

### 3) A2A Gateway

Agentgateway also supports the Agent-to-Agent (A2A) protocol so agents can:
- discover each other’s capabilities
- negotiate modalities (text/forms/media)
- collaborate on long-running tasks

---

## Security & observability (the part that turns demos into systems)

From the docs:
- Authentication: JWT, API keys, basic auth, MCP auth spec
- Authorization: fine-grained RBAC with the **Cedar policy engine**
- Traffic policies: rate limiting, CORS, TLS, external authz
- Observability: built-in OpenTelemetry metrics/logs/tracing

If you’re building agent systems you expect to run for months, this is the difference between:
- “we tested it once”
- and “we can operate it safely”

---

## Why now (the timing)

The timing is interesting because multiple milestones are converging:
- The repo is about **1 year old** (created March 2025)
- It’s **nearing ~2k GitHub stars**
- The project is crossing into the **v1.0 release line** (currently in alpha)

This is usually the moment when a project shifts from “early adopter playground” to “this is becoming a platform.”

---

## Next: what I’d build first

If you want a practical entry point, pick one:

1) **LLM routing + observability** (single endpoint, multiple providers)
2) **MCP tool federation** (one tool endpoint, many MCP servers)
3) **Policy + RBAC** (who can call which tools, under what conditions)

If you tell me which one you want to lead with, I’ll write a follow-up tutorial that’s copy/paste runnable.
