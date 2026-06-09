---
title: "Running kagent on a kind Cluster with a Local vLLM + Qwen3 Backend"
date: 2026-06-09T16:00:00-04:00
draft: false
categories:
  - AI
  - Agents
  - Kubernetes
tags:
  - kagent
  - kind
  - vLLM
  - Qwen
  - Helm
  - Kubernetes
  - LLM
  - DGX Spark
  - Self-hosted
---

# Running kagent on a kind Cluster with a Local vLLM + Qwen3 Backend

**By Sebastian Maniak**

Most kagent walkthroughs assume you're pointing at OpenAI or Anthropic. But what if you want to run the **entire stack locally** — agents, controller, *and* the model — with zero tokens leaving your lab?

That's exactly what this demo does. We'll spin up a throwaway [kind](https://kind.sigs.k8s.io/) cluster, install [kagent](https://kagent.dev) with **all the built-in agents disabled**, and wire its default provider to a self-hosted [vLLM](https://github.com/vllm-project/vllm) endpoint serving `Qwen/Qwen3.6-35B-A3B-FP8`. From there you can build agents from a clean slate — no cloud LLM, no API bill, no data egress.

![Let's go](/images/articles/2026-06-09-kagent-kind-vllm-qwen/lets-go.gif)

## Why This Setup?

A few reasons this combo is worth your time:

- **Fully local inference** — the model runs on your own GPU (in my case a DGX Spark), so prompts and cluster data never leave the building.
- **Disposable environment** — kind means the whole cluster is one `docker` container. Break it, delete it, recreate it in 30 seconds.
- **Clean slate** — disabling the bundled agents means kagent comes up as a bare control plane. You decide which agents exist, instead of inheriting eight of them.
- **OpenAI-compatible** — vLLM exposes the standard `/v1` API, so kagent's `openAI` provider talks to it with nothing more than a `baseUrl` override.

## Architecture

```
┌─────────────────────────────────────┐
│  kind cluster (kagent-demo)          │
│                                      │
│   ┌────────────────────────────┐     │
│   │ kagent control plane        │     │
│   │ (controller + UI)           │     │
│   │  provider: openAI           │     │
│   └──────────────┬─────────────┘     │
│                  │ OpenAI /v1 API     │
└──────────────────┼────────────────────┘
                   │  (baseUrl override)
                   ▼
        ┌────────────────────────┐
        │  vLLM server            │
        │  Qwen3.6-35B-A3B-FP8    │
        │  DGX Spark · :8000/v1   │
        └────────────────────────┘
```

The cluster runs everything *except* the model. The model lives on a separate box (the DGX Spark) and is reached over the network at `http://172.16.10.173:8000/v1`. kagent doesn't care that it's not OpenAI — as far as it's concerned, it's just an OpenAI-compatible endpoint.

## Prerequisites

- [`kind`](https://kind.sigs.k8s.io/)
- `kubectl`
- `helm`
- A reachable vLLM endpoint serving the `Qwen/Qwen3.6-35B-A3B-FP8` model (see the [DGX Spark config](#bonus-the-vllm-server-on-dgx-spark) at the end)

## Step 1: Create the kind Cluster

One command and you've got a single-node Kubernetes cluster running inside Docker:

```bash
kind create cluster --name kagent-demo
```

## Step 2: Install the kagent CRDs

This installs the Custom Resource Definitions kagent depends on, and — thanks to `--create-namespace` — creates the `kagent` namespace that **every later step relies on**. Run it first.

```bash
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace
```

## Step 3: Create the vLLM API Key Secret

kagent's `openAI` provider expects an API key, even when the backend doesn't enforce one. vLLM typically ignores the key, so any non-empty value works:

```bash
kubectl create secret generic kagent-vllm \
  -n kagent \
  --from-literal=VLLM_API_KEY=dummykey
```

> The `kagent` namespace already exists from Step 2, so this secret lands in the right place. Order matters here.

## Step 4: Install kagent — Without the Default Agents

This is the interesting part. The kagent chart ships a set of built-in agents (k8s, helm, istio, cilium, kgateway, promql, observability, argo-rollouts). For this demo we **disable all of them** so we can build our own agents from scratch. We also point the default provider at our vLLM/Qwen endpoint — just adjust `config.baseUrl` to match your own server.

```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set k8s-agent.enabled=false \
  --set helm-agent.enabled=false \
  --set istio-agent.enabled=false \
  --set promql-agent.enabled=false \
  --set observability-agent.enabled=false \
  --set argo-rollouts-agent.enabled=false \
  --set cilium-debug-agent.enabled=false \
  --set cilium-manager-agent.enabled=false \
  --set cilium-policy-agent.enabled=false \
  --set kgateway-agent.enabled=false \
  --set grafana-mcp.enabled=false \
  --set querydoc.enabled=false \
  --set providers.default=openAI \
  --set providers.openAI.provider=OpenAI \
  --set-string providers.openAI.model="Qwen/Qwen3.6-35B-A3B-FP8" \
  --set providers.openAI.apiKeySecretRef=kagent-vllm \
  --set providers.openAI.apiKeySecretKey=VLLM_API_KEY \
  --set-string providers.openAI.config.baseUrl="http://172.16.10.173:8000/v1"
```

A few things worth calling out:

| Flag | What it does |
|------|--------------|
| `*-agent.enabled=false` | Disables each bundled agent so you start clean |
| `providers.default=openAI` | Makes the OpenAI-compatible provider the default |
| `providers.openAI.config.baseUrl` | **The key override** — points kagent at vLLM instead of api.openai.com |
| `providers.openAI.apiKeySecretRef` | References the dummy secret from Step 3 |
| `--set-string` on the model | Forces the model name to stay a string (it has slashes/digits) |

## Step 5: Verify the Control Plane

Check that the control-plane pods come up and that **no default agents were created**:

```bash
kubectl get pods -n kagent
kubectl get agents -n kagent   # should be empty
```

If `get agents` returns nothing, the disable flags did their job. 🎉

![It works](/images/articles/2026-06-09-kagent-kind-vllm-qwen/it-works.gif)

## The kagent UI

Once the control plane is healthy, open the kagent UI. The **Models** view confirms the provider wiring — you should see a `default-model-config` pointing at OpenAI as the provider, the Qwen model ID, the `kagent-vllm` API key secret, and your vLLM `baseUrl` under provider parameters:

![kagent Models view showing the default-model-config wired to the local vLLM endpoint](/images/articles/2026-06-09-kagent-kind-vllm-qwen/kagent-models.png)

The **Agents** view starts empty — exactly what we wanted. Here I've created a single `test` agent from scratch, running on the local `OpenAI (Qwen/Qwen3.6-35B-A3B-FP8)` model:

![kagent Agents view showing a custom test agent on the local Qwen model](/images/articles/2026-06-09-kagent-kind-vllm-qwen/kagent-agents.png)

From here the cluster is yours. Create agents, attach MCP tool servers, and every inference call routes to your local Qwen model instead of a cloud API.

## Cleanup

When you're done, tear the whole thing down with a single command:

```bash
kind delete cluster --name kagent-demo
```

No leftover namespaces, no orphaned resources — the entire cluster was a Docker container, and now it's gone.

## Bonus: The vLLM Server on DGX Spark

For completeness, here's the exact `docker run` I use to serve Qwen3.6 on my DGX Spark. This is the endpoint kagent's `baseUrl` points at:

```bash
docker run -d --name vllm-qwen36 \
  --restart always \
  --runtime nvidia --gpus all \
  --network host --ipc host --shm-size 96g \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  vllm/vllm-openai:cu130-nightly \
  --model Qwen/Qwen3.6-35B-A3B-FP8 \
  --host 0.0.0.0 --port 8000 \
  --gpu-memory-utilization 0.85 \
  --max-model-len 262144 \
  --max-num-seqs 16 \
  --max-cudagraph-capture-size 256 \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder
```

Highlights that make this work well for agentic workloads:

- **`--enable-auto-tool-choice` + `--tool-call-parser qwen3_coder`** — lets the model emit proper tool calls, which is essential for kagent agents that invoke MCP tools.
- **`--reasoning-parser qwen3`** — separates the model's reasoning trace from its final answer.
- **`--max-model-len 262144`** — a generous 256K context window, plenty of room for long agent conversations and tool outputs.
- **`--gpu-memory-utilization 0.85`** — leaves a little headroom on the GPU.

## Wrapping Up

In under ten minutes you've got a disposable Kubernetes cluster running kagent with a **fully local LLM backend** — no cloud provider, no API key that matters, no data leaving your network. Because the model speaks the OpenAI API, kagent didn't need any special integration: just a `baseUrl` swap.

This is my go-to scratchpad for prototyping agents before promoting them to a real cluster. The kind cluster is cheap to create and free to destroy, and the Qwen3.6 model on the DGX Spark is fast enough to make the loop feel interactive.

Next up: building a real agent on top of this and wiring it to MCP tool servers. Stay tuned.

---

*Want more on kagent? Check out [Human-in-the-Loop with kagent](/articles/2026-03-11-human-in-the-loop-kagent/) and [Managing FortiGate Firewalls from Telegram with AI, MCP, and kagent](/articles/2026-03-15-fortigate-firewall-telegram-kagent-mcp/).*
