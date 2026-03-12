---
title: "How To: Run agentgateway standalone locally (UI + basic smoke test)"
date: 2026-03-12T09:30:00-04:00
draft: false
categories:
  - AI
  - Infrastructure
tags:
  - agentgateway
  - MCP
  - A2A
  - Observability
---

# How To: Run agentgateway standalone locally (UI + basic smoke test)

This is a quick-start for **agentgateway v1.0.0-alpha.4** in standalone mode.

Upstream repo: https://github.com/agentgateway/agentgateway
Latest alpha release notes: https://github.com/agentgateway/agentgateway/releases/tag/v1.0.0-alpha.4

---

## Option A — Docker (fastest)

The project publishes a container image:
- `cr.agentgateway.dev/agentgateway:v1.0.0-alpha.4`

Example:
```bash
docker run --rm -p 15000:15000 \
  cr.agentgateway.dev/agentgateway:v1.0.0-alpha.4
```

Then open:
- UI: http://localhost:15000/ui

---

## Option B — Binary

The release also publishes binaries (see the GitHub release assets). Download the one for your OS/arch, then run it:

```bash
./agentgateway
```

Then open:
- UI: http://localhost:15000/ui

---

## What to check first

- Does the UI load at `/ui`?
- Are there obvious errors in logs on startup?
- Can you see config/state updating when you apply changes?

---

## Next step: one real use case

Tell me which “first win” you want and I’ll build the smallest working example:
- Proxy OpenAI through agentgateway
- Route + observe MCP tool traffic
- A2A connectivity demo
