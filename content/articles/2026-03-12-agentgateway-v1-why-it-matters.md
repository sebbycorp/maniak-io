---
title: "agentgateway v1.0 (alpha): Why the 1.0 Line Matters (and What Changed)"
date: 2026-03-12T09:20:00-04:00
draft: false
categories:
  - AI
  - Infrastructure
  - Kubernetes
tags:
  - agentgateway
  - MCP
  - A2A
  - Observability
  - Security
  - Gateway
---

# agentgateway v1.0 (alpha): Why the 1.0 Line Matters (and What Changed)

If you’ve been tracking **agentgateway**, you probably noticed something big: it crossed into the **v1.0.0** release line.

As of today, the latest published release is **`v1.0.0-alpha.4`** — so this isn’t “GA 1.0” yet — but the **1.0 line itself is the story**.

This post breaks down why **v1.0** is significant, what it changes operationally, and how you should think about upgrading if you were previously consuming agentgateway via **kgateway**.

---

## Quick context: what is agentgateway?

**agentgateway** is an open-source **data plane** optimized for agentic AI connectivity — agent-to-tool and agent-to-agent — with a focus on:

- **Security and governance** around tool access (MCP) and agent interoperability (A2A)
- **Observability** (including OpenTelemetry)
- **High-performance** (Rust-based)
- **Run anywhere** (standalone or Kubernetes)

Upstream repo: https://github.com/agentgateway/agentgateway

---

## Why the v1.0 line is significant

### 1) Decoupling from kgateway (versioning + lifecycle)

The most important “why 1.0” detail is **not** a single feature — it’s **project independence**.

From the `v1.0.0-alpha.2` release notes:
- agentgateway is now **entirely decoupled from kgateway**
- Kubernetes deployment used to be delivered via kgateway and followed kgateway’s versioning scheme

**What that fixes in practice:**
- You no longer have to explain *two* versions for “agentgateway on k8s” (controller vs dataplane)
- Releases become **unified under one repo** with consistent artifacts

### 2) One release, one set of artifacts

The v1.0.0 alpha releases publish a consistent set of artifacts:
- Docker images (controller + gateway)
- Helm charts (agentgateway + agentgateway-crds)
- Binaries

Example (alpha.4):
- `cr.agentgateway.dev/agentgateway:v1.0.0-alpha.4`
- `cr.agentgateway.dev/controller:v1.0.0-alpha.4`
- `cr.agentgateway.dev/charts/agentgateway:v1.0.0-alpha.4`
- `cr.agentgateway.dev/charts/agentgateway-crds:v1.0.0-alpha.4`

This is a very “1.0-adjacent” sign: the project is taking packaging/distribution seriously.

### 3) The project is signaling stability goals

Even though it’s still alpha, moving to v1 is a public signal that the project is:
- drawing a line around scope
- solidifying APIs (CRDs, config models)
- standardizing install paths

In other words: it’s positioning itself to be something you can **operationalize**, not just demo.

---

## Notable changes in the v1.0.0-alpha series (high-level)

From the `v1.0.0-alpha.4` notes, a few changes that matter operationally:

- **OpenTelemetry support for access logs** (great for real-world production debugging and cost attribution)
- **Gateway API alignment updates** (example: TLSRoute v1 bump)
- Release artifact / versioning cleanup (consistent `v` prefixes)

Release notes:
- alpha.2: https://github.com/agentgateway/agentgateway/releases/tag/v1.0.0-alpha.2
- alpha.4: https://github.com/agentgateway/agentgateway/releases/tag/v1.0.0-alpha.4

---

## Upgrade / adoption guidance

### If you’re new
Start with v1.0.0-alpha.4 and pick one track:
- **Standalone** for local dev and labs
- **Kubernetes** if you want multi-tenant, policy, and integration with existing cluster operations

### If you came via kgateway
The key shift is that **agentgateway now has its own release line**, but it can still be used as a supported data plane within kgateway.

Practical recommendation:
- treat v1.0 alpha as **a migration window**
- stand up v1.0 alpha in parallel, validate config and policy behavior, then cut over

---

## What’s next

In the next posts I’ll publish two quick how-tos:
- “Install agentgateway on Kubernetes in 10 minutes”
- “Run agentgateway standalone locally (and what to look at in the UI)”

If you want one single “do it all” tutorial instead (one post, end-to-end), that also works — it’s just longer.
