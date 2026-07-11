---
title: "AgentGateway Standalone — Cost & Tokenomics Dashboard Demo"
date: 2026-06-24
description: "Want to see AgentGateway's cost and analytics dashboard fully populated in under two minutes — without burning a single real API call? This standalone demo runs AgentGateway in a single Docker container, seeds a SQLite database with 5,000 mock fleet requests across 7 days, and prices every one of them against a real model-cost catalog. One command, one dashboard, zero waiting for traffic to accumulate. Here's how to run it."
---

Every time I show someone [AgentGateway](https://agentgateway.dev)'s **Costs** and **Analytics** dashboards, the same problem comes up: a fresh install has *no data*. The dashboard is empty until you've sent real traffic through it, which means you either wait days for usage to accumulate or you script a load generator and pay for thousands of throwaway API calls just to make some charts light up.

The [`00-standalone-latest`](https://github.com/sebbycorp/agentgateway-demos/tree/main/00-standalone-latest) demo solves that. It spins up AgentGateway standalone in a single Docker container with a **pre-populated** cost database — 5,000 simulated requests spanning 7 days, each priced against a real per-model cost catalog — so the dashboard is fully alive the moment it boots. No waiting, no burned tokens.

👉 **[sebbycorp/agentgateway-demos / 00-standalone-latest](https://github.com/sebbycorp/agentgateway-demos/tree/main/00-standalone-latest)**

**TL;DR:** `export OPENAI_API_KEY=… && ./setup.sh`, then open `http://localhost:15000/ui/`. You get a working AgentGateway with a costs dashboard that already has a week of fleet traffic in it — and the LLM endpoint is live on `:4000` so you can add your own real requests on top.

## What you actually get

The demo is deliberately small — five files do all the work:

| File | Role |
|---|---|
| `setup.sh` | One-shot installer: preflight checks, generates mock data, writes config, launches the container |
| `config.yaml` | AgentGateway config — admin UI, SQLite database, model catalog, OpenAI routes |
| `base-costs.json` | Per-model pricing rates (OpenAI, Anthropic, Bedrock, Gemini, Mistral, DeepSeek…) so every request gets a real dollar cost |
| `gen-mock-logs.py` | Generates realistic fleet traffic and writes it into AGW's `request_logs` schema |
| `destroy.sh` | Tears the whole thing down |

The trick that makes it work: the **mock generator writes to the exact same `request_logs` table that AgentGateway's dashboard reads from**, and the model catalog (`base-costs.json`) prices every row. So from the dashboard's point of view, the seeded data is indistinguishable from real traffic.

## Prerequisites

You need very little:

- **Docker** installed and running
- **`curl`** (the script downloads the mock-data generator)
- **Python ≥ 3.11** or [`uv`](https://github.com/astral-sh/uv) to run the generator
- An **`OPENAI_API_KEY`** — required because the live LLM route on `:4000` proxies to OpenAI. (The *dashboard* data is mock; the *live endpoint* is real.)

## Run it

```bash
git clone https://github.com/sebbycorp/agentgateway-demos.git
cd agentgateway-demos/00-standalone-latest

export OPENAI_API_KEY='sk-...'
./setup.sh
```

That's the whole thing. `setup.sh` walks through:

1. **Preflight** — checks for Docker + a running daemon, `curl`, a Python runner, and `OPENAI_API_KEY`.
2. **Fetch the generator** — downloads `gen-mock-logs.py` if it isn't already local.
3. **Generate mock data** — creates a SQLite DB with **5,000 requests across 7 days** (both configurable, see below) using AGW's `request_logs` schema.
4. **Write config** — emits the `config.yaml` pointing the admin UI at that database and loading the cost catalog.
5. **Launch** — pulls the image, creates a named volume, seeds the DB, and starts the container.

When it finishes, open:

```
http://localhost:15000/ui/
```

and head to the **Costs** and **Analytics** sections. They're already full.

### Tuning the seed

Three environment variables let you change the shape of the seeded data before you run `setup.sh`:

```bash
VERSION=v1.3.1 \   # AgentGateway image tag
REQUESTS=20000 \   # number of mock requests (default 5000)
DAYS=30 \          # days to spread them across (default 7)
./setup.sh
```

Bump `REQUESTS` and `DAYS` if you want to demo what a busier fleet or a longer reporting window looks like.

## What's under the hood: config.yaml

The generated config is worth a look because it shows how cost tracking is wired:

```yaml
config:
  adminAddr: "0.0.0.0:15000"        # admin UI + dashboards (reachable from host)
  database:
    url: "sqlite:///data/data.db"   # /data is the mounted ./data dir in the container
  modelCatalog:
    - file: /base-costs.json        # per-model rates so every request is priced

llm:
  port: 4000
  policies:
    cors:
      allowOrigins: ["*"]
      allowHeaders: ["*"]
      allowMethods: ["GET", "POST", "OPTIONS"]
  models:
    - name: "openai/gpt-4.1"
      provider: openAI
      params:
        model: gpt-4.1
        apiKey: "$OPENAI_API_KEY"
    - name: "openai/*"              # fallback: cheaper nano model
      provider: openAI
      params:
        model: gpt-4.1-nano
        apiKey: "$OPENAI_API_KEY"
```

Two things to call out:

- **`modelCatalog`** is what turns raw token counts into dollars. `base-costs.json` carries input/output/cache rates for dozens of models across OpenAI, Anthropic, Bedrock, Gemini, Mistral, DeepSeek and more — including tiered pricing for large-context models. Every request in the dashboard is costed against it.
- **The `openai/*` fallback route** quietly downshifts anything that doesn't match a named model to the cheaper `gpt-4.1-nano` — a nice pattern for keeping unbudgeted traffic from hitting your most expensive model.

The container is launched roughly like this (the script handles it for you):

```bash
docker run -d --name agw-cost-demo \
  --user 0:0 \
  -p 4000:4000 -p 15000:15000 \
  -e OPENAI_API_KEY \
  -v config.yaml:/config.yaml \
  -v base-costs.json:/base-costs.json \
  -v agw-cost-demo-data:/data \
  cr.agentgateway.dev/agentgateway:v1.3.1 -f /config.yaml
```

| Port | What it serves |
|---|---|
| **15000** | Admin UI — the Costs & Analytics dashboards |
| **4000** | Live LLM endpoint (OpenAI-compatible `/v1/chat/completions`) |

## Add real traffic on top

Because `:4000` is a live OpenAI-compatible endpoint, you can fire real requests at it and watch them land in the same dashboard alongside the mock data:

```bash
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4.1",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

Refresh the dashboard and your call shows up — priced against the same catalog as the seeded rows. This is the best way to convince a skeptical teammate that the cost numbers are real: send a couple of calls and watch the spend tick up.

## Tear it down

When you're done, the demo cleans up after itself:

```bash
./destroy.sh
```

or do it by hand:

```bash
docker rm -f agw-cost-demo && docker volume rm agw-cost-demo-data
```

No leftover containers, no stray volumes.

## Why this demo is useful

Standalone AgentGateway is the fastest way to understand what the gateway *sees* about your LLM spend — which models cost what, where the tokens go, how a fallback route changes the bill. But "fastest" still normally means "after you've generated enough traffic to have something to look at." This demo collapses that to a single command by **separating the dashboard data from the live path**: mock data makes the charts immediately meaningful, and the real `:4000` route lets you prove the pricing is genuine whenever you want.

If you've read my earlier posts on [tool-mode token economics](2026-06-20-github-mcp-token-economics-agentgateway-tool-modes.md) or [stacking Headroom on top of AGW](2026-06-22-headroom-agentgateway-mcp-token-stacking.md), this is the dashboard those experiments report into — now you can stand it up in two minutes and explore it yourself.

👉 Grab it here: **[sebbycorp/agentgateway-demos / 00-standalone-latest](https://github.com/sebbycorp/agentgateway-demos/tree/main/00-standalone-latest)**
