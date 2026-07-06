---
title: "Flying a Drone with AI Agents: Standard vs CodeSearch MCP Tool Modes (and Three Models)"
date: 2026-07-06
description: "A real, measured study of an AI agent flying a Ryze RoboMaster TT drone over MCP through Enterprise agentgateway. We compare the Standard and CodeSearch tool modes on a 28-tool drone catalog — CodeSearch cuts tokens ~46% and cost ~39% on gpt-5.5 — then re-run the identical flight on Claude and xAI to show the winning mode is model-dependent. Includes real agentgateway MCP-routing logs and the kagent agent transcript."
tags: ["agentgateway", "kagent", "mcp", "tool-modes", "langfuse", "drone", "tokenomics"]
categories: ["AI Gateway"]
---

I wired an AI agent up to a **Ryze RoboMaster TT** drone and let it fly — takeoff, flip, photograph, spin, land — by calling an **MCP server** through [Enterprise agentgateway](https://agentgateway.dev). The drone exposes **28 tools** (telemetry, flight primitives, camera, an 8×8 LED matrix, and a dozen composite maneuvers). The interesting question isn't *can* an agent fly it — it can — but **how much does the way you expose those 28 tools cost you** in tokens and dollars.

agentgateway can present the same MCP server to the model in four different **tool modes**. This post compares the two that matter most for a mid-sized catalog — **Standard** and **CodeSearch** — on one identical flight, with the real numbers pulled from [Langfuse](https://langfuse.com). Then I swap the model (gpt-5.5 → Claude → xAI) and re-run, because the answer changes.

There's a live flight deck for the whole rig here: **[goose.maniak.ai](https://goose.maniak.ai)**.

## The setup

| Component | Value |
|---|---|
| **Aircraft** | Ryze RoboMaster TT (Tello), flown via a drone MCP server (28 tools) |
| **Front door** | Enterprise agentgateway — proxies the MCP server and the OpenAI-compatible model route |
| **Agent runtime** | kagent (declarative `Agent` CRs, A2A endpoints) on Kubernetes |
| **Model** | `gpt-5.5` via the agentgateway `/openai` route (then Claude + xAI) |
| **Observability** | kagent → OTEL → Langfuse; every model call metered per token |
| **The flight** | 5 prompts, one continuous run, identical across every agent |

The flight protocol — the same five prompts sent to every agent:

1. *Take off and hover.*
2. *Do a flip.*
3. *Take a photo and describe what you see.*
4. *Spin around 360 degrees.*
5. *Land and give me a status report.*

Each agent is its own kagent `Agent` pointed at the same drone MCP server through a different agentgateway tool-mode endpoint. The **only** variables are the tool mode and (later) the model — same prompts, same tools, same aircraft.

## The two tool modes

Every time an LLM talks to an MCP server, the **tool catalog** — the JSON schema of every tool — is injected into the prompt. For 28 tools with real descriptions that's a few thousand tokens of overhead **on every single turn**, before the model does any work. The tool mode decides how you pay that tax.

### Standard — the whole catalog, every turn
- **What the model sees:** all 28 tools, full schemas.
- **Workflow:** the model picks a tool and calls it directly — no discovery step.
- **Cost:** you re-send the entire catalog on every turn.

### CodeSearch — discover typed signatures, then write code
- **What the model sees:** two meta-tools — `get_tool` (fetch a tool's typed signature on demand) and `run_code` (write JavaScript that calls the tools in a sandbox).
- **Workflow:** look up only the signatures you need, then submit one code block that calls them and returns just the result.
- **Cost:** context stays tiny (no full catalog) *and* round-trips stay low (batch calls in code) — the best of both, in theory.

## Results: Standard vs CodeSearch (gpt-5.5)

One flight each, tokens and cost pulled per model call from Langfuse (deduped — kagent's OTEL exporter logs each call under both the model name and its alias, so raw counts run ~1.8× high if you don't collapse them):

| Mode | Model calls | Total tokens | Latency | Cost | vs Standard |
|---|--:|--:|--:|--:|--:|
| **Standard** | 35 | 98.3k | 47s | $0.5252 | baseline |
| **CodeSearch** | 21 | 53.1k | 37s | **$0.3201** | **−39%** |

**CodeSearch cut tokens by ~46% and cost by ~39%** on this 28-tool catalog — fewer model calls, far less context per call, and it finished faster. For a mid-sized tool catalog, not shoving all 28 schemas into every turn pays off.

### Where the cost actually goes

Break it down per prompt and one step dominates every run:

| # | Prompt | Standard (calls / tokens / cost) | CodeSearch (calls / tokens / cost) |
|---|---|---|---|
| 1 | Take off and hover | 3 / 7.4k / $0.0443 | 4 / 8.6k / $0.0490 |
| 2 | Do a flip | 4 / 10.8k / $0.0583 | 4 / 9.2k / $0.0574 |
| 3 | Take a photo and describe | 6 / 17.7k / $0.0938 | 3 / 7.2k / $0.0462 |
| 4 | Spin 360° | 5 / 15.9k / $0.0832 | 5 / 12.7k / $0.0752 |
| 5 | **Land + status report** | **17 / 45.1k / $0.2457** | 5 / 13.3k / $0.0922 |

The **status report** is the hotspot: the agent polls `get_state` repeatedly to compose it, so in Standard mode it burns 17 calls and 45k tokens — nearly half the whole flight. CodeSearch collapses that into a single `run_code` that reads state once and returns a summary: **5 calls, 13k tokens**. That one prompt is most of the −39%.

## The logs — agentgateway

agentgateway sees every MCP request and tags it with the tool mode's route (`/drone` for Standard, `/drone-codesearch` for CodeSearch), the MCP method, status, and latency. This is the gateway routing the agent's calls to the drone MCP server, straight from the proxy:

```text
info request gateway=virtual-mcp-gateway route=drone-mcp
  http.method=POST http.path=/drone http.status=200
  protocol=mcp mcp.method.name=tools/list duration=3ms
info request gateway=virtual-mcp-gateway route=drone-mcp-codesearch
  http.method=POST http.path=/drone-codesearch http.status=200
  protocol=mcp mcp.method.name=initialize duration=3ms
info request gateway=virtual-mcp-gateway route=drone-mcp-codesearch
  http.method=POST http.path=/drone-codesearch http.status=200
  protocol=mcp mcp.method.name=tools/list duration=2ms
```

Every hop is `protocol=mcp` with the MCP method name broken out — `initialize`, `tools/list`, `tools/call` — so the gateway is a single place to watch (and meter, and rate-limit, and guardrail) all tool traffic, regardless of which agent or model made the call.

## The logs — kagent (the flight transcript)

And here's the agent actually flying, prompt by prompt — the kagent `Agent` responses from the Standard run:

```text
▸ Take off and hover.
  The drone is airborne and hovering at about 80 cm. Battery 90%,
  connection live, attitude stable.                        [3 calls · 7.4k tok · $0.0443]

▸ Do a flip.
  Front flip complete. Back in hover at about 80 cm.       [4 calls · 10.8k tok · $0.0583]

▸ Take a photo and describe what you see.
  Photo captured. A bright indoor lab: a desk with two monitors,
  a potted plant by a window, pale grey walls.             [6 calls · 17.7k tok · $0.0938]

▸ Spin around 360 degrees.
  360° clockwise spin complete. Back in hover.             [5 calls · 15.9k tok · $0.0832]

▸ Land and give me a status report.
  Landed. Status: 0 cm height, connection live, attitude
  level (roll 0 / pitch 0 / yaw 0), battery 86%.          [17 calls · 45.1k tok · $0.2457]
```

The per-call token and cost figures come from Langfuse (kagent exports OTEL spans for every model call), so the transcript and the cost table are the same source of truth.

## Does it hold across models?

CodeSearch wins on gpt-5.5 — but is that a property of the mode, or the model? I re-ran the **identical** Standard and CodeSearch flights on two more models, each through its own agentgateway route, swapping nothing but the model:

| Model | Mode | Calls | Tokens | Latency | Cost |
|---|---|--:|--:|--:|--:|
| **gpt-5.5** | Standard | 35 | 98.3k | 47s | $0.5252 |
| **gpt-5.5** | CodeSearch | 21 | **53.1k** | 37s | **$0.3201** |
| **claude-fable-5** | Standard | 26 | 159.5k | 79s | $1.6676 |
| **claude-fable-5** | CodeSearch | 33 | 165.6k | 101s | $1.5167 |
| **grok-4.3** | Standard | 34 | 113.0k | 25s | — |
| **grok-4.3** | CodeSearch | 33 | 99.5k | 31s | — |

> Tokens are the fair cross-model metric (cost = tokens × each model's price). Langfuse prices gpt-5.5 and Claude; grok-4.3 wasn't priced in my Langfuse instance yet, so its cost shows —, but its token counts are real.

Three clear takeaways:

- **gpt-5.5 is the efficient one** — the fewest tokens, the lowest cost, and the *only* model where CodeSearch clearly helps (−46% tokens vs its own Standard run).
- **Claude (claude-fable-5) is the thorough, premium one** — roughly **3× the tokens and cost** of gpt-5.5, and CodeSearch *doesn't* shrink it. Claude writes verbose discovery/`run_code` steps, so the "smaller context" of CodeSearch is offset by longer generations. The mode that saves gpt-5.5 money costs Claude nothing.
- **grok-4.3 is the fast one** — it finished the whole flight in ~25–31s versus Claude's ~80–100s, at moderate token use.

The headline: **the tool mode that wins is model-dependent.** CodeSearch is a big win for gpt-5.5, a wash for Claude. Benchmark the mode *with the model you'll actually deploy* — don't pick it in the abstract.

## Why this architecture makes the experiment trivial

Everything above was a config change, not a code change. Each agent is a declarative kagent `Agent` pointed at a tool-mode endpoint; each model is a `ModelConfig` behind an agentgateway route. Swapping `Standard` → `CodeSearch` is a different backend `toolMode`; swapping `gpt-5.5` → `claude-fable-5` is a different `modelConfig`. agentgateway sits in the middle and meters every token on both sides of the conversation — which is exactly why the numbers in this post exist at all.

If you're exposing an MCP server to agents, the tool mode is a real cost lever — but measure it on your catalog and your model. For a 28-tool drone, CodeSearch nearly halved gpt-5.5's token bill; for Claude it didn't move the needle. The gateway makes trying both a one-line change and a Langfuse query.

Live flight deck with the full 28-tool catalog, the command lifecycle, and these results: **[goose.maniak.ai](https://goose.maniak.ai)**.
