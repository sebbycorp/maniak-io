---
title: "How To: Install agentgateway on Kubernetes (Helm OCI)"
date: 2026-03-12T08:02:00-04:00
draft: false
categories:
  - Kubernetes
  - AI
  - Infrastructure
tags:
  - agentgateway
  - Helm
  - Gateway API
  - MCP
---

# How To: Install agentgateway on Kubernetes (Helm OCI)

This is a “get it running fast” install for **agentgateway v1.0.0-alpha.4** using the OCI Helm charts published by the project.

Upstream release notes (artifacts list):
https://github.com/agentgateway/agentgateway/releases/tag/v1.0.0-alpha.4

> Note: exact values and defaults can change between alphas; treat this as a baseline and validate in your cluster.

---

## Prereqs
- Kubernetes cluster
- `kubectl`
- Helm v3 with OCI support

---

## 1) Pick a namespace

```bash
export AGW_NS=agentgateway-system
kubectl create namespace $AGW_NS || true
```

---

## 2) Install CRDs

```bash
export AGW_VER=v1.0.0-alpha.4

helm install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --version $AGW_VER \
  --namespace $AGW_NS
```

---

## 3) Install agentgateway

```bash
helm install agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  --version $AGW_VER \
  --namespace $AGW_NS
```

---

## 4) Verify pods

```bash
kubectl get pods -n $AGW_NS
kubectl get svc -n $AGW_NS
```

---

## 5) Next: configure your first route/tool access

At this point agentgateway is installed; the next step is to define how traffic flows (MCP servers, policies, routes, etc.).

If you tell me your target (OpenAI proxying? MCP multiplexing? A2A?), I’ll write the exact minimal config example as a follow-up.
