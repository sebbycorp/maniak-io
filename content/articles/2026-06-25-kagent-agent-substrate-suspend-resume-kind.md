---
title: "Suspend & Resume Stateful Agents: kagent on Agent Substrate with kind"
date: 2026-06-25T10:00:00-04:00
draft: false
categories:
  - AI
  - Agents
  - Kubernetes
tags:
  - kagent
  - Agent Substrate
  - gVisor
  - kind
  - Helm
  - Kubernetes
  - Actors
  - Serverless
---

# Suspend & Resume Stateful Agents: kagent on Agent Substrate with kind

**By Sebastian Maniak**

Agent sessions are bursty. A user asks a question, the agent thinks for a few seconds, then the session sits idle for minutes — or hours — waiting on the next turn. Plain Kubernetes handles this badly: an idle pod still books its CPU and memory, and a cold pod takes seconds to come back. Multiply that across thousands of conversations and you're paying for a lot of nothing.

**Agent Substrate** flips the model. It decouples the *agent session* from the *pod*: idle sessions are checkpointed — full RAM and filesystem, via [gVisor](https://gvisor.dev/) — to object storage, the pod returns to a warm pool, and the session resumes **sub-second** on the next request, exactly where it left off. Think serverless scale-to-zero, but for *stateful* agents.

In this how-to we'll stand the whole thing up on a throwaway [kind](https://kind.sigs.k8s.io/) cluster: **Agent Substrate**, **kagent** wired to use it as its execution layer, and a tiny `SandboxAgent` running as a gVisor actor. Then we'll chat with it and watch it suspend and resume.

> This is a standalone, run-it-yourself adaptation of the [Agent Substrate with kagent Instruqt workshop](https://github.com/sebbycorp/Instruqt-demos/tree/main/01-kagent-agent-substrate-workshop). No Instruqt account required — just a Linux box.

## Why This Setup?

- **Serverless economics for stateful agents** — idle actors cost (almost) nothing; you pay for a small pool of warm workers, not one pod per session.
- **Sub-second resume** — gVisor checkpoint/restore brings a suspended session back where it left off, no cold-start penalty.
- **Disposable environment** — the whole thing is one `kind` cluster. Break it, delete it, recreate it.
- **kagent-native** — kagent `0.9.7` is the first release that can use substrate as its execution layer, so a declarative agent becomes a substrate actor with one field: `platform: substrate`.

## The Substrate Model in 30 Seconds

Agent Substrate decouples **actor** lifecycle from **pod** lifecycle:

- An **Actor** is one logical agent session — state `RUNNING` or `SUSPENDED`.
- A **Worker** is a pre-warmed pod hosting at most one actor — state `IDLE` or `BUSY`.
- Idle actors are **suspended**: gVisor checkpoints their full state to object storage and the worker returns to the pool.
- On the next request the actor is **resumed** sub-second into a free worker — exactly where it left off.

| Term | Meaning |
|------|---------|
| **Actor** | One logical agent session. |
| **Worker** | A pre-warmed pod hosting at most one actor. |
| **WorkerPool** | A set of warm standby worker pods (a CRD). |
| **ActorTemplate** | The immutable "class" an actor is created from (a CRD). Creating one builds a **golden snapshot** (version 0). |
| **Golden snapshot** | The initial frozen image every new actor is restored from. |
| **Suspend / Resume** | Checkpoint actor state to object storage / restore it sub-second. |

## Architecture

```
┌──────────────────────────── kind cluster (kagent-substrate) ────────────────────────────┐
│                                                                                          │
│   namespace: kagent                          namespace: ate-system                       │
│   ┌────────────────────┐                     ┌──────────────────────────────────────┐   │
│   │ kagent-controller  │  controller.substrate.* │ ate-api-server  (scheduling)      │   │
│   │ kagent-ui          │ ───────────────────────▶│ atenet-router   (L7 routing)      │   │
│   │ SandboxAgent       │                     │   │ atelet          (node supervisor) │   │
│   │   hello-substrate  │                     │   │ valkey-cluster  (state)           │   │
│   │ WorkerPool         │                     │   │ rustfs          (snapshots/S3)    │   │
│   │   kagent-default   │                     │   └──────────────────────────────────────┘ │
│   └────────────────────┘                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

| Layer | What it does |
|-------|--------------|
| **Agent Substrate** (`ate-system`) | Kubernetes-native runtime that maps many stateful **actors** onto a small pool of pre-warmed **worker** pods. Idle actors are checkpointed (RAM + filesystem, via gVisor) to object storage and resumed sub-second on demand. |
| **kagent** (`kagent`) | The agent control plane / runtime, wired to use substrate as its execution layer. |
| **`SandboxAgent`** | A per-session declarative agent that runs as a gVisor **actor** on the substrate. |

## Prerequisites

You need a **Linux** machine (or a Linux VM) with **at least ~8 vCPUs and 16 GB RAM** — the substrate control plane runs a 6-node valkey cluster plus several other components, so a tiny machine will struggle.

> **macOS / Windows note:** gVisor checkpoint/restore relies on Linux kernel features. Run this on Linux — a cloud VM such as a GCP `n1-standard-8`, an EC2 `m5.2xlarge`, or equivalent works well. Docker Desktop on Mac/Windows runs containers in a Linux VM and may not support the gVisor checkpointing path reliably.

Tools and the versions this guide is pinned to:

| Tool | Version | Why |
|------|---------|-----|
| Docker | any recent | `kind` runs the cluster in containers |
| `kind` | `v0.27.0` | Kubernetes-in-Docker |
| Node image | `kindest/node:v1.32.2` | **k8s 1.31+ required** — substrate CRDs use CEL `format` rules |
| `kubectl` | matches cluster | |
| `helm` | v3 | installs the charts |
| `grpcurl` | `v1.9.1` | drive the substrate `ate-api` directly |
| OpenAI API key | — | the agent makes real LLM calls |

Pinned component versions used throughout:

| Component | Version |
|-----------|---------|
| Agent Substrate | `0.0.6` |
| kagent (OSS) | `0.9.7` |
| gVisor actor image | `ghcr.io/kagent-dev/substrate/ateom-gvisor:v0.0.6` |

> ⚠️ **Why the node image matters:** the substrate `0.0.6` CRDs use CEL validation rules that call the `format` library (`format.dns1123Label` / `dns1123Subdomain`), added in Kubernetes **1.31**. An older `kind` default node image will reject the CRDs. Pin `kindest/node:v1.32.2` or newer.

## Step 0 — Install Tooling

Run these on a Linux host. Skip any tool you already have at a compatible version.

```bash
# kubectl
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# helm v3
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kind v0.27.0 (pin it — older kind ships an older default node image)
curl -fsSLo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# grpcurl v1.9.1
curl -fsSL "https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_x86_64.tar.gz" \
  | tar -xz -C /usr/local/bin grpcurl
chmod +x /usr/local/bin/grpcurl
```

Make sure Docker is running:

```bash
sudo systemctl start docker   # if applicable
docker info >/dev/null && echo "docker OK"
```

Export your OpenAI key (the agent makes real LLM calls):

```bash
export OPENAI_API_KEY="sk-...your-key..."
[[ -n "${OPENAI_API_KEY:-}" ]] && echo "key set (len=${#OPENAI_API_KEY})" || echo "OPENAI_API_KEY is empty!"
```

> ⚠️ **Footgun:** don't inline the assignment on the helm line like `OPENAI_API_KEY=... helm ... --set ...="${OPENAI_API_KEY}"` — the variable is expanded *before* the assignment runs and you'll silently pass an empty string. Export it first, as above.

Pin a few env vars for convenience:

```bash
export KIND_CLUSTER=kagent-substrate
export SUBSTRATE_VERSION=0.0.6
export KAGENT_VERSION=0.9.7
```

## Step 1 — Create the kind Cluster

```bash
kind create cluster --name "${KIND_CLUSTER}" --image kindest/node:v1.32.2 --wait 120s
```

Verify it's ready:

```bash
kubectl get nodes
kubectl cluster-info
```

You should see one node in `Ready` state. Confirm your tools resolve:

```bash
kind version
helm version --short
grpcurl --version
```

## Step 2 — Install Agent Substrate

Everything lands in the `ate-system` namespace. The substrate `0.0.6` chart defaults to **JWT auth** (ServiceAccount tokens), so a stock `kind` cluster works — no feature gates, no custom kind config.

Install the CRDs:

```bash
helm upgrade --install substrate-crds \
  oci://ghcr.io/kagent-dev/substrate/helm/substrate-crds \
  --version 0.0.6 \
  --namespace ate-system --create-namespace --wait
```

Install the control plane (this pulls several images and starts the valkey cluster — give it a few minutes):

```bash
helm upgrade --install substrate \
  oci://ghcr.io/kagent-dev/substrate/helm/substrate \
  --version 0.0.6 \
  --namespace ate-system --wait --timeout 10m
```

Watch it come up:

```bash
kubectl get pods -n ate-system
```

Wait until you see all of these `Running` (a couple of init Jobs will show `Completed`):

| Pod | Role |
|-----|------|
| `ate-api-server` | Control plane: actor lifecycle, scheduling, suspend/resume. Bypasses kube-scheduler. |
| `ate-controller` | Reconciles `WorkerPool` + `ActorTemplate` CRDs into Deployments. |
| `atelet` (DaemonSet) | Node supervisor: pulls images, manages sandbox lifecycle, talks to object storage. |
| `atenet-router` | Envoy L7 router; resolves which worker serves each request. |
| `valkey-cluster-0`..`-5` | State store: actor/worker records and locks. |
| `rustfs` | In-cluster S3-compatible object storage holding snapshot images. |

Inspect the CRDs:

```bash
kubectl get crd | grep ate.dev
kubectl get workerpools.ate.dev -A
```

There are no WorkerPools yet — kagent creates one in the next step.

## Step 3 — Install kagent, Wired to Substrate

kagent is the agent control plane; substrate is the execution layer *underneath* it. kagent `0.9.7` is the first release with substrate support.

> ⚠️ **Order matters:** the kagent controller **hard-fails (crash-loops)** if the substrate API isn't reachable at startup — which is why substrate had to be installed first.

Install the kagent CRDs:

```bash
helm upgrade --install kagent-crds \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --version 0.9.7 \
  --namespace kagent --create-namespace --wait
```

Install kagent with substrate enabled:

```bash
helm upgrade --install kagent \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --version 0.9.7 --namespace kagent --timeout 10m --wait \
  --set providers.default=openAI \
  --set providers.openAI.apiKey="${OPENAI_API_KEY}" \
  --set controller.substrate.enabled=true \
  --set controller.substrate.ateApiEndpoint="dns:///api.ate-system.svc:443" \
  --set controller.substrate.ateApiInsecure=true \
  --set controller.substrate.atenetRouterURL="http://atenet-router.ate-system.svc:80" \
  --set controller.substrate.ateApiTokenFile="/var/run/secrets/tokens/ate-api/token" \
  --set controller.substrate.defaultWorkerPool.namespace=kagent \
  --set controller.substrate.defaultWorkerPool.name=kagent-default \
  --set substrateWorkerPool.create=true \
  --set substrateWorkerPool.name=kagent-default \
  --set substrateWorkerPool.replicas=1 \
  --set substrateWorkerPool.ateomImage=ghcr.io/kagent-dev/substrate/ateom-gvisor:v0.0.6
```

What the substrate flags mean:

- `controller.substrate.enabled=true` — turn on the integration
- `controller.substrate.ateApiEndpoint` — where the substrate control plane lives
- `controller.substrate.atenetRouterURL` — the substrate request router
- `controller.substrate.defaultWorkerPool.*` — the pool agents land on by default
- `substrateWorkerPool.create=true` + `.replicas=1` — create one warm worker

> If helm times out while the controller waits on its database (it restarts a couple of times during cold start), wait for it manually and continue:
>
> ```bash
> kubectl wait deploy/kagent-controller -n kagent --for=condition=Available --timeout=10m
> ```

Verify the WorkerPool and the integration:

```bash
kubectl get workerpools.ate.dev -A
```

You should see `kagent/kagent-default`.

```bash
kubectl run substrate-status-check -n kagent --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 -- \
  http://kagent-controller:8083/api/substrate/status
```

The response should include `"enabled": true`.

## Step 4 — Deploy a SandboxAgent

A kagent `SandboxAgent` with `platform: substrate` is a per-session declarative agent that runs as a substrate **actor**. Creating one generates an `ActorTemplate`, which triggers the **golden snapshot** — the version-0 frozen image every session is restored from. The first snapshot takes ~60–90s.

> The runtime must be **Go** — Python ADK isn't compatible with gVisor checkpointing.

Write the manifest:

```bash
cat > hello-substrate.yaml <<'YAML'
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: hello-substrate
  namespace: kagent
spec:
  type: Declarative
  description: Tiny declarative agent running inside a substrate actor
  declarative:
    runtime: go
    modelConfig: default-model-config
    systemMessage: |
      You are a friendly assistant living inside an Agent Substrate sandbox.
      When asked who you are, say "I am hello-substrate, a Go ADK declarative
      agent running inside a gVisor actor."
  platform: substrate
  substrate:
    workerPoolRef:
      name: kagent-default
YAML
```

Apply it:

```bash
kubectl apply -f hello-substrate.yaml
```

Wait for it to be Ready (first golden snapshot takes ~60–90s):

```bash
kubectl wait sandboxagent/hello-substrate -n kagent --for=condition=Ready --timeout=5m
```

Inspect the generated substrate resources:

```bash
kubectl get sandboxagent -n kagent
kubectl get actortemplates.ate.dev -A
```

kagent generated an `ActorTemplate` for your agent (owned by the SandboxAgent).

## Step 5 — Chat, Then Watch Suspend / Resume

When you chat with `hello-substrate`, a per-session gVisor **actor** is restored from the golden snapshot, runs the LLM call, and snapshots itself back to object storage — returning the worker to the pool. Between requests the actor sits **SUSPENDED**; on the next request it's **RESUMED** sub-second.

### 5a. Open the kagent UI

Port-forward the UI and open it in your browser:

```bash
kubectl -n kagent port-forward svc/kagent-ui 8080:8080 --address 0.0.0.0
```

Open <http://localhost:8080> (or `http://<vm-ip>:8080`). Pick `kagent/hello-substrate` from the Agents list and send:

> *What are you, and where are you running? Answer in one sentence.*

You should get back something like:

> *I am hello-substrate, a Go ADK declarative agent running inside a gVisor actor.*

Then open the **Substrate** page (`/substrate`) in the UI to see the worker pool and actors.

### 5b. Drive the actor lifecycle from the CLI

In another terminal, port-forward the substrate API in the background:

```bash
kubectl port-forward -n ate-system svc/api 18443:443 >/tmp/pf-api.log 2>&1 &
sleep 3
```

Mint a short-lived token the kagent controller's identity can use:

```bash
TOKEN=$(kubectl create token kagent-controller -n kagent --audience=api.ate-system.svc --duration=15m)
```

List the actors — note your actor's id and its status (it will be `SUSPENDED` between requests):

```bash
grpcurl -insecure -H "authorization: Bearer $TOKEN" -d '{}' \
  localhost:18443 ateapi.Control/ListActors
```

Resume the actor explicitly — watch it flip to `RUNNING`:

```bash
grpcurl -insecure -H "authorization: Bearer $TOKEN" \
  -d '{"actor_id":"<ACTOR_ID>"}' \
  localhost:18443 ateapi.Control/ResumeActor
```

Re-run `ListActors` to confirm the state change. That round trip — `SUSPENDED` in object storage, `RESUMED` into a worker on demand — is the whole point of substrate.

## Recap

You now have, on a single `kind` cluster:

- **Agent Substrate** (`ate-system`) — control plane (`ate-api-server`), router (`atenet-router`), node supervisor (`atelet`), state (`valkey`), snapshots (`rustfs`).
- **kagent** (`kagent`) — wired to substrate with a default `WorkerPool`.
- A **`SandboxAgent`** running as a per-session gVisor actor, suspended to object storage between requests and resumed sub-second on demand.

### Scaling the WorkerPool

One worker serves many declarative sessions sequentially because each session releases its slot the moment it snapshots back. To run overlapping sessions or long-lived agents, scale the pool:

```bash
kubectl scale workerpool kagent-default -n kagent --replicas=3
```

### What's Next (Beyond This Guide)

- **`AgentHarness` (`runtime: substrate`)** — long-lived runtimes run as substrate actors reached through a kagent gateway. These need an object-storage bucket (e.g. `gs://...`) and don't auto-suspend, so each pins a worker slot.
- **Identity** — substrate can mint per-actor JWTs and certs for mTLS.
- **Observability** — substrate exposes metrics for activation latency and worker pool use.

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| Substrate CRDs rejected on install | Node image too old — recreate the cluster with `kindest/node:v1.32.2` or newer. |
| `kagent-controller` crash-loops | Substrate API not reachable at startup — confirm `ate-system` pods are all `Running` before installing kagent. |
| kagent install silently "works" but the agent fails on chat | `OPENAI_API_KEY` was empty — re-export it (don't inline the assignment on the helm line) and re-run the kagent `helm upgrade`. |
| Helm install times out on kagent | The controller restarts during cold start; run `kubectl wait deploy/kagent-controller -n kagent --for=condition=Available --timeout=10m` and continue. |
| `ListActors` returns auth errors | Token expired (15m TTL) — re-mint with the `kubectl create token` command. |
| Everything was fine yesterday, broken today | Substrate's in-cluster TLS certs expire after ~24h on idle clusters — best run in a single sitting. Recreate the cluster if needed. |

> **Note:** Agent Substrate is **very early / pre-1.0** — APIs will change and it's not production-ready. gVisor checkpoint/restore requires a live Linux host to test.

## Cleanup

```bash
kind delete cluster --name kagent-substrate
```

## Try It Yourself

The full standalone how-to (with the exact manifests used here) lives in the [kagent-demos repo](https://github.com/sebbycorp/kagent-demos/tree/main/01-kagent-agent-substrate). Prefer a guided, browser-based lab with no setup? Run the [Agent Substrate with kagent Instruqt workshop](https://github.com/sebbycorp/Instruqt-demos/tree/main/01-kagent-agent-substrate-workshop) instead — same path, six bite-sized challenges.

Suspend-and-resume is the feature that finally makes per-session stateful agents affordable at scale. Spin it up, chat with `hello-substrate`, and watch a worker serve far more sessions than it has slots for.
