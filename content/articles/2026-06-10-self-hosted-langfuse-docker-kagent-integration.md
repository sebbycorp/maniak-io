---
title: "Self-Hosted Langfuse with Docker + kagent Integration"
date: 2026-06-10
description: "Run Langfuse locally or in production using Docker, then wire kagent to send traces, token usage, and costs automatically via OpenTelemetry."
---

Running Langfuse as a self-hosted Docker stack gives you full control over your LLM observability data. This guide shows how to deploy it and integrate it with **kagent** so every agent trace, prompt, completion, and token count flows into Langfuse automatically.

---

## Why Self-Hosted Langfuse?

- Keep all prompts and completions inside your infrastructure
- No usage limits or data leaving your cluster
- Full control over retention and cost tracking
- Works great with local models (vLLM, Ollama, etc.)

---

## 1. Run Langfuse with Docker

The fastest way to get Langfuse running is using their official Docker Compose stack.

```bash
git clone https://github.com/langfuse/langfuse.git
cd langfuse
docker compose up -d
```

After a minute, open http://localhost:3000 and create your first project.

**Important credentials you’ll need later:**
- `LANGFUSE_PUBLIC_KEY`
- `LANGFUSE_SECRET_KEY`
- Base URL (usually `http://langfuse:3000` inside the cluster or your external URL)

---

## 2. Configure kagent to Send Traces to Langfuse

kagent (v0.9.6+) has built-in OpenTelemetry support. The cleanest way to configure it is through Helm values.

### Helm Values (kagent)

```yaml
otel:
  tracing:
    enabled: true
    exporter:
      otlp:
        endpoint: "http://your-langfuse-host:3000/api/public/otel/v1/traces"
        protocol: "http/protobuf"
        insecure: true
        timeout: 15000

controller:
  env:
    - name: LANGFUSE_OTEL_AUTH
      valueFrom:
        secretKeyRef:
          name: langfuse-otel
          key: LANGFUSE_OTEL_AUTH
    - name: OTEL_EXPORTER_OTLP_TRACES_HEADERS
      value: "Authorization=Basic $(LANGFUSE_OTEL_AUTH)"
```

### Create the Auth Secret

Create a secret containing the Basic Auth header:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-otel
type: Opaque
stringData:
  LANGFUSE_OTEL_AUTH: "<public_key>:<secret_key>"   # base64 encoded later
```

Or let **External Secrets Operator + Vault** manage it (recommended for production).

---

## 3. Verify Traces Are Flowing

Once deployed:

1. Go to your kagent project in Langfuse
2. Trigger any agent (via UI, Telegram, Slack, etc.)
3. You should see traces appear within seconds showing:
   - Full prompt + completion
   - Token usage (`prompt_tokens`, `completion_tokens`)
   - Model name
   - Latency
   - Cost (if you configured pricing)

---

## 4. Cost Tracking for Local Models

Since you’re likely using local models (Qwen via vLLM), set the price to `$0` in Langfuse:

**Settings → Models → Add model**

- Model name: `Qwen/Qwen3.6-35B-A3B-FP8` (must match exactly)
- Input price: `0`
- Output price: `0`

This keeps the cost column clean while still capturing full usage data.

---

## Summary

You now have:

- Langfuse running self-hosted via Docker
- kagent automatically sending every LLM call via OTLP
- Token usage and (optional) cost tracking working

This setup is the foundation used in production clusters running kagent + agentgateway.

Next guide: How to extend this pattern to **agentgateway** using an OpenTelemetry Collector for cleaner auth handling.