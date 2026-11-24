---
title: "How To: Install kagent locally with one command"
date: 2026-11-24
draft: false
description: "The fastest way to get kagent running on your own machine: create a kind cluster, set a model API key and run one command. The kagent CLI installs the CRDs, Agent Substrate, a development PostgreSQL database and kagent for you. Covers every step, how to check that it worked, the two things that trip people up, and how to remove it when you're done."
categories:
  - AI
  - Agents
  - Kubernetes
tags:
  - kagent
  - Agent Substrate
  - Install
  - kind
  - kagent CLI
  - Getting started
author: "Sebastian Maniak"
---

**By Sebastian Maniak**

Getting kagent running on your laptop takes three things: a local Kubernetes cluster, a model API key and one command. This post walks through all three, start to finish, in about five minutes.

Here's the whole thing, if you just want to copy and paste:

```bash
kind create cluster --name kagent --image kindest/node:v1.37.0
export OPENAI_API_KEY="your-api-key-here"
curl -sL https://kagent.dev/install | bash && kagent install
kagent dashboard
```

The rest of this post explains each line.

![A terminal creating a kind cluster, running the kagent install command, and listing the running kagent pods](/images/articles/2026-11-24-kagent-agent-substrate-install-manage/kagent-install-cli-kind.gif)

*Installing kagent on a local kind cluster with the CLI, sped up.*

---

## What you need

| Tool | Why |
|---|---|
| Docker, or another container runtime that kind supports | kind runs your cluster as containers |
| [`kind`](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) v0.32.0 or later | To create the local cluster |
| [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl) | To talk to the cluster |
| [`helm`](https://helm.sh/docs/intro/install/) 3 | The kagent CLI runs `helm` to install each chart |
| A model API key | OpenAI, Anthropic, Gemini or Ollama |

## Step 1: Create a local cluster

kagent needs Kubernetes **1.37 or later**, so name the node image when you create the cluster:

```bash
kind create cluster --name kagent --image kindest/node:v1.37.0
```

The version matters. kagent 1.0 runs every agent on Agent Substrate, and Substrate uses two certificate APIs that became generally available in 1.37. On an older cluster the install won't work.

To check that your cluster is new enough, run:

```bash
kubectl api-resources --api-group=certificates.k8s.io
```

You should see `clustertrustbundles` and `podcertificaterequests` in the list, both at `certificates.k8s.io/v1`.

## Step 2: Set your model API key

kagent needs a model to think with. Pick your provider and export its key:

| Provider | Command |
|---|---|
| OpenAI | `export OPENAI_API_KEY="your-api-key-here"` |
| Anthropic | `export ANTHROPIC_API_KEY="your-api-key-here"` |
| Gemini | `export GOOGLE_API_KEY="your-api-key-here"` |
| Ollama (Ollama Cloud) | `export OLLAMA_API_KEY="your-api-key-here"` |

Set it in the same terminal that you'll run the install from. The installer reads it from the environment.

## Step 3: Install kagent

Now the one command. It does two things: it downloads the `kagent` CLI, and then it installs kagent into your cluster.

If you use **OpenAI**, that's the default:

```bash
curl -sL https://kagent.dev/install | bash && kagent install
```

For any other provider, add the `--provider` flag:

```bash
# Anthropic
curl -sL https://kagent.dev/install | bash && kagent install --provider Anthropic

# Gemini
curl -sL https://kagent.dev/install | bash && kagent install --provider Gemini

# Ollama
curl -sL https://kagent.dev/install | bash && kagent install --provider Ollama
```

It takes a few minutes. While you wait, here's what `kagent install` is putting in your cluster, in this order:

1. **The CRDs**, the resource types such as `Agent` and `Harness`.
2. **Agent Substrate**, the runtime that every kagent agent runs on. It sandboxes each agent and suspends it when it's idle.
3. **A development PostgreSQL database**, where kagent keeps conversations and schedules.
4. **kagent itself**: the controller, the UI and the built-in tools.

You don't install any of those separately. The CLI does it all.

### Two things that might trip you up

- **It asked for my password.** The install script puts the CLI in `/usr/local/bin`, and it needs your password to write there. To install into `$HOME/bin` without `sudo`, run:

  ```bash
  curl -sL https://kagent.dev/install | bash -s -- --no-sudo
  ```

- **I already had an older kagent installed.** Your shell might keep running the old one, and `kagent install` would then install the older release. Run `kagent version` and check that `kagent_version` matches the release the script just downloaded.

## Step 4: Check that it worked

Check that the pods are running:

```bash
kubectl get pods -n kagent
```

Every pod should say `Running`. Example output:

```console
NAME                                              READY   STATUS    RESTARTS   AGE
kagent-controller-56c67b6cd7-hqj5z                1/1     Running   3          2m
kagent-default-774d4496bd-sfx4b                   1/1     Running   0          2m
kagent-postgresql-856b475f59-n258n                2/2     Running   0          2m
kagent-tools-54959b659c-lfkrz                     1/1     Running   0          2m
kagent-ui-5fdb6fd85c-vzb2z                        1/1     Running   0          2m
```

Then check that the worker pool is ready. This is the pool of sandboxed Workers that your agents run on:

```bash
kubectl get workerpools -n kagent
```

Example output:

```console
NAME             DESIRED   REPLICAS   READY   SANDBOXCONFIG    RESOLVED   AGE
kagent-default   1         1          1       gvisor-default   True       2m
```

If `READY` shows `1`, you're good.

## Step 5: Open the dashboard

```bash
kagent dashboard
```

This forwards the UI to [http://localhost:8082](http://localhost:8082). On macOS it also opens it in your browser. On Linux or Windows, port-forward the UI service yourself and open that address:

```bash
kubectl port-forward -n kagent svc/kagent-ui 8082:8080
```

Leave the command running while you use the UI. The dashboard lists your agents, models, MCP servers and the tools that kagent discovered.

![The kagent dashboard after a fresh installation](/images/articles/2026-11-24-kagent-agent-substrate-install-manage/kagent-ui-dashboard.png)

*The dashboard after a fresh installation: no agents yet, one model configuration and two MCP servers.*

That's it. kagent is installed.

## Good to know

- **Want a specific release?** The script installs the newest one by default. To pin a version, pass `--version`:

  ```bash
  curl -sL https://kagent.dev/install | bash -s -- --version v1.0.1
  kagent version --client
  ```

- **Which platforms does the script support?** macOS and Linux on `amd64` and `arm64`, and Windows on `amd64` from Git Bash or MSYS.

- **Is this production-ready?** No. The CLI install is built for trying kagent out, because it deploys a development PostgreSQL database. For production, install with Helm against your own database. I cover what else to change in [Install kagent and manage Agent Substrate the right way](/articles/2026-11-24-kagent-agent-substrate-install-and-manage-the-right-way/).

- **Coming from kagent 0.x?** kagent 1.0 installs fresh. There's no in-place upgrade from the 0.10.x line, so use a new cluster for this.

## Remove it when you're done

If you used the kind cluster from step 1, one command removes everything:

```bash
kind delete cluster --name kagent
```

To keep the cluster and remove only kagent, use the CLI:

```bash
kagent uninstall
```

That deletes every kagent resource, the development database and all conversation state, and you can't get it back. Check that `kubectl config current-context` points at the right cluster before you run it.

## What to build next

You have a running kagent. Now give it something to do:

- [Build a Kubernetes SRE agent that asks before it changes anything](/articles/2026-11-24-kagent-k8s-sre-agent-human-approval-agent-substrate/): an agent that investigates on its own and waits for your approval before it scales or restarts anything.
- [Build a scheduled agent with kagent and Agent Substrate](/articles/2026-11-24-kagent-scheduled-agent-cluster-health-report-agent-substrate/): a cluster health report every day, without being asked.
- [Build a CVE agent with kagent and Agent Substrate in a secure sandbox](/articles/2026-11-24-kagent-cve-agent-substrate-secure-sandbox/): an agent that reads the internet safely, with default-deny egress.
- [Install kagent and manage Agent Substrate the right way](/articles/2026-11-24-kagent-agent-substrate-install-and-manage-the-right-way/): what the install created, how to check it and how to size it.
