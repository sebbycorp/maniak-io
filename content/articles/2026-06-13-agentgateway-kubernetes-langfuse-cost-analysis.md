---
title: "One-Script Deployment: agentgateway + Self-Hosted Langfuse on Kubernetes for LLM Cost Analysis"
date: 2026-06-13
description: "Deploy a complete agentgateway + Langfuse observability stack on kind with a single script. Get rich traces, token usage, and real USD cost tracking for local models with zero manual wiring."
---

Running production-grade LLM gateways with full observability usually involves many manual steps across Helm charts, CRDs, tracing configuration, and UI key management.

The **agentgateway-demos/09-k8s-langfuse** demo eliminates almost all of that friction by making **agentgateway the central cost-control and observability plane**.

**agentgateway** sits in front of your models, inspects every request/response, emits rich GenAI OpenTelemetry traces (model name, input/output tokens, full prompt + completion, latency, user/session attribution), and forwards them directly to Langfuse. Once you set per-model pricing in Langfuse, you get automatic USD cost tracking, spend dashboards, and usage analytics — all without any external SaaS or manual log shipping.

## What You Get

A single `./deploy.sh` that provisions:

- A dedicated kind cluster (`agw-k8s-langfuse`)
- Full self-hosted Langfuse (PostgreSQL + ClickHouse + Redis + web/worker) via the official Helm chart, tuned for kind
- agentgateway CRDs, controller, GatewayClass, and proxy (v1.1.0)
- Pre-configured `AgentgatewayBackend` + `HTTPRoute` routing `/v1/*` to your local OpenAI-compatible model (e.g. Qwen running on your host)
- Direct OTLP/HTTP tracing from agentgateway → Langfuse (no collector sidecar required)

After one follow-up script with your project keys, **agentgateway** automatically sends every LLM call to Langfuse with the data needed for real cost management.

## Quick Start (The Automated Path)

```bash
git clone https://github.com/sebbycorp/agentgateway-demos.git
cd agentgateway-demos/09-k8s-langfuse

./deploy.sh
```

The script handles:

- kind cluster creation
- Gateway API CRDs
- Langfuse Helm install + phased readiness waits (databases first)
- agentgateway controller + CRDs
- Base `AgentgatewayParameters`
- Gateway + `spark` backend + `spark-route` HTTPRoute

Langfuse bootstrap (ClickHouse especially) takes 5–15 minutes on first run. The script prints progress and continues.

## Wiring Observability (Minimal Manual Step)

Once `langfuse-web` is running:

```bash
kubectl port-forward -n langfuse svc/langfuse-web 3000:3000 &
# Open http://localhost:3000, create a project, copy Public + Secret keys
```

Then:

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
./configure-observability.sh
```

This single script:

- Computes the correct Basic Auth header Langfuse expects
- Applies the complete `AgentgatewayParameters` resource with:
  - OTLP/HTTP endpoint pointing at the in-cluster Langfuse service
  - Proper Authorization header
  - Full field mappings for `gen_ai.prompt`, `gen_ai.completion`, streaming flags, `user.id`, `session.id`, client IP, and environment tags
- The agentgateway controller immediately reconciles the change and pushes the new tracing config to all data-plane proxies

From this point forward, **agentgateway** is responsible for capturing cost-relevant telemetry on every request and streaming it to Langfuse in real time. No additional instrumentation, sidecars, or log shipping is required.

## How agentgateway Manages Costs & Sends Logs to Langfuse

**agentgateway** acts as your cost control plane:

1. Every OpenAI-compatible request hits the Gateway first
2. It extracts and enriches telemetry using the GenAI semantic conventions
3. It streams complete traces (including full prompt/completion bodies) over OTLP/HTTP directly to Langfuse’s `/api/public/otel/v1/traces` endpoint
4. Langfuse turns these traces into first-class “Generations” with token accounting

Key data **agentgateway** sends for cost management:
- `gen_ai.request.model`
- `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens`
- Full `gen_ai.prompt` and `gen_ai.completion`
- `user.id` and `session.id` (via request headers for attribution and filtering)
- Latency, streaming status, client IP, and environment tags

Once pricing is configured in Langfuse, you get accurate per-request and aggregated USD costs.

## Test & Observe Costs

```bash
kubectl port-forward -n agentgateway-system svc/agentgateway-proxy 8080:80 &

./test.sh --users          # realistic multi-user traffic with attribution headers
# or
./test.sh "Explain Kubernetes Gateway API in one paragraph."
```

**agentgateway** captures and forwards:

- Exact model name and provider
- Input and output token counts (`gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`)
- Full prompt and completion bodies
- Latency and streaming status
- User and session attribution (via `x-user-id` / `x-session-id` headers)

Open Langfuse → Traces / Generations. You’ll immediately see rich entries.

Then go to **Project → Settings → Models** and add pricing for your model (e.g. Qwen). Langfuse automatically calculates real USD costs per generation and aggregates them into spend dashboards. This is how you turn raw token logs into actionable cost management.

## Why This Approach Wins

- **Zero collector complexity** — agentgateway speaks Langfuse’s OTLP endpoint natively
- **Idempotent & reproducible** — re-run deploy.sh safely
- **Local-model friendly** — hostOverride pattern works cleanly inside kind
- **Production-ready patterns** — the same tracing config translates directly to real clusters

## Cleanup

```bash
./cleanup.sh
```

Removes the cluster and all resources.

## Next Steps

Clone the demo and run it:

```bash
https://github.com/sebbycorp/agentgateway-demos/tree/main/09-k8s-langfuse
```

This is currently the fastest way to stand up a complete, observable AI gateway stack on Kubernetes for cost tracking and debugging.

---

*Related reading:*
- [Self-Hosted Langfuse with Docker + kagent Integration](2026-06-10-self-hosted-langfuse-docker-kagent-integration.md)
- [LLM Observability with agentgateway + Langfuse](2026-02-14-llm-observability-agentgateway-langfuse.md)
- agentgateway Kubernetes docs: https://agentgateway.dev/docs/kubernetes/latest
