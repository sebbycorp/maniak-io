---
title: "Production Langfuse Integration with agentgateway (OTel Collector Pattern)"
date: 2026-06-10
description: "Connect agentgateway to Langfuse using an in-cluster OpenTelemetry Collector. This pattern avoids auth headaches and gives you clean, gateway-level tracing for every LLM and tool call."
---

**agentgateway** emits rich OpenTelemetry traces for every LLM request, tool call, and policy decision. This guide shows the production-grade way to forward those traces to Langfuse using an OpenTelemetry Collector.

---

## Why Go Through an OTel Collector?

Directly sending from agentgateway to Langfuse has issues:

- agentgateway expects OTLP headers as CEL expressions
- A raw `Authorization: Basic xxx` header breaks the proxy on startup
- You lose the ability to fan-out traces to multiple backends

**Solution**: Send from agentgateway → OTel Collector (no auth) → Langfuse (with auth).

This is the exact pattern used in the k8s-iceman production cluster.

---

## Architecture

```
agentgateway (proxy)
      │
      │ OTLP gRPC (no auth)
      ▼
OpenTelemetry Collector (otel-collector.kagent)
      │
      │ OTLP HTTP + Basic Auth
      ▼
Langfuse (/api/public/otel)
```

---

## 1. Deploy the OpenTelemetry Collector

Use the community Helm chart with this configuration:

```yaml
# otel-collector/values.yaml
mode: deployment
fullnameOverride: otel-collector

image:
  repository: otel/opentelemetry-collector-contrib

extraEnvsFrom:
  - secretRef:
      name: langfuse-otel

ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317

config:
  extensions:
    basicauth/langfuse:
      client_auth:
        username: ${env:LANGFUSE_PUBLIC_KEY}
        password: ${env:LANGFUSE_SECRET_KEY}

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: ${env:MY_POD_IP}:4317

  exporters:
    otlphttp/langfuse:
      endpoint: ${env:LANGFUSE_BASE_URL}/api/public/otel
      auth:
        authenticator: basicauth/langfuse

  service:
    extensions: [health_check, basicauth/langfuse]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlphttp/langfuse]
```

---

## 2. Configure agentgateway Tracing

Create an `AgentgatewayParameters` resource (referenced from your GatewayClass):

```yaml
# manifests/agentgateway-config/langfuse-tracing.yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayParameters
metadata:
  name: langfuse-tracing
  namespace: agentgateway-system
spec:
  env:
    - name: OTLP_ENDPOINT
      value: "http://otel-collector.kagent.svc.cluster.local:4317"
    - name: OTLP_PROTOCOL
      value: "grpc"
    - name: OTLP_HEADERS
      value: "{}"          # critical: empty so it doesn't crash
  rawConfig:
    config:
      tracing:
        randomSampling: true
        fields:
          add:
            span.name: '"agentgateway.request"'
            gen_ai.system: 'llm.provider'
            gen_ai.prompt: 'flattenRecursive(llm.prompt)'
            gen_ai.completion: 'flattenRecursive(llm.completion.map(c, {"role":"assistant", "content": c}))'
            gen_ai.usage.completion_tokens: 'llm.outputTokens'
            gen_ai.usage.prompt_tokens: 'llm.inputTokens'
```

Then reference it in your agentgateway Helm values:

```yaml
gatewayClassParametersRefs:
  agentgateway:
    name: langfuse-tracing
    namespace: agentgateway-system
```

---

## 3. Secrets via Vault + External Secrets

Never hardcode Langfuse keys. Use this pattern:

```yaml
# ExternalSecret that creates langfuse-otel secret
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: langfuse-otel
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: langfuse-otel
  data:
    - secretKey: LANGFUSE_PUBLIC_KEY
      remoteRef:
        key: iceman_langfuse
        property: LANGFUSE_PUBLIC_KEY
    - secretKey: LANGFUSE_SECRET_KEY
      remoteRef:
        key: iceman_langfuse
        property: LANGFUSE_SECRET_KEY
    - secretKey: LANGFUSE_BASE_URL
      remoteRef:
        key: iceman_langfuse
        property: LANGFUSE_BASE_URL
```

The collector and kagent both reference this same secret.

---

## 4. What You Get in Langfuse

Every request through agentgateway now appears with:

- Full prompt and completion
- Token counts
- Model name
- Which gateway policy ran (if any)
- MCP tool calls
- Latency breakdown

---

## Summary

This pattern gives you:

- Clean separation of concerns
- No auth headaches in agentgateway
- Production-ready secret management
- Easy to extend to metrics + logs later

This is the exact setup running in the k8s-iceman cluster today.

Would you like a combined “Langfuse + kagent + agentgateway” mega-guide next?