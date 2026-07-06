---
title: "GPT-5.5 vs Claude vs Grok: Which Model Saves Money? (I Made Them Fly a Drone)"
date: 2026-07-06
description: "I flew the identical mission on a real Ryze RoboMaster TT drone with three models — gpt-5.5, claude-fable-5, and grok-4.3 — each swapped in with a one-line agentgateway ModelConfig, every token metered in Langfuse. The cost gap was 5×. Here's who saves money, why, and how the MCP tool mode changes the answer. Real graphs, real agentgateway logs, real kagent traces."
tags: ["agentgateway", "kagent", "mcp", "llm-cost", "gpt-5.5", "claude", "grok", "langfuse", "tokenomics"]
categories: ["AI Gateway"]
---

Same job, three brains. I gave an AI agent a real **Ryze RoboMaster TT** drone and one fixed mission — *take off, flip, photograph the room, spin 360°, land and report* — then flew it **identically on three models**: `gpt-5.5`, `claude-fable-5`, and `grok-4.3`. Same agent, same drone, same 28-tool MCP server, same prompts. The only thing that changed was the model, swapped in with a **one-line [agentgateway](https://agentgateway.dev) ModelConfig**.

The bill for that identical flight ranged **5× from cheapest to dearest.** This post is about who saves money, why, and the one extra knob that moves the answer. Every number is measured — pulled from kagent's tracing and Langfuse, not estimated.

Live flight deck: **[goose.maniak.ai](https://goose.maniak.ai)**.

Here's the agent flying the mission on the real drone:

<video controls playsinline muted preload="metadata" style="width:100%;height:auto;border-radius:8px" aria-label="The AI agent flying the identical mission on a real Ryze RoboMaster TT drone">
<source src="/videos/2026-07-06-drone-flight.mp4" type="video/mp4">
Your browser does not support the video tag.
</video>

## The verdict: cost per flight

<svg viewBox="0 0 720 320" role="img" aria-label="Cost per flight — Standard vs CodeSearch, three models" style="width:100%;height:auto">
<text x="54" y="26" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="13" font-weight="700">Cost per flight — Standard vs CodeSearch, three models</text>
<rect x="470" y="16" width="11" height="11" rx="2" fill="#9d7bff"/><text x="486" y="26" fill="#7788a1" font-family="ui-monospace,monospace" font-size="11">Standard</text>
<rect x="570" y="16" width="11" height="11" rx="2" fill="#46e0c0"/><text x="586" y="26" fill="#7788a1" font-family="ui-monospace,monospace" font-size="11">CodeSearch</text>
<line x1="54" y1="266.0" x2="704" y2="266.0" stroke="#1c2a3d"/>
<text x="48" y="269.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">$0.00</text>
<line x1="54" y1="213.0" x2="704" y2="213.0" stroke="#1c2a3d"/>
<text x="48" y="216.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">$0.45</text>
<line x1="54" y1="160.0" x2="704" y2="160.0" stroke="#1c2a3d"/>
<text x="48" y="163.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">$0.90</text>
<line x1="54" y1="107.0" x2="704" y2="107.0" stroke="#1c2a3d"/>
<text x="48" y="110.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">$1.35</text>
<line x1="54" y1="54.0" x2="704" y2="54.0" stroke="#1c2a3d"/>
<text x="48" y="57.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">$1.80</text>
<rect x="90.8" y="204.1" width="60.7" height="61.9" rx="3" fill="#9d7bff"/>
<text x="121.2" y="199.1" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$0.53</text>
<rect x="173.2" y="228.3" width="60.7" height="37.7" rx="3" fill="#46e0c0"/>
<text x="203.5" y="223.3" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$0.32</text>
<text x="162.3" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">gpt-5.5</text>
<rect x="307.5" y="69.6" width="60.7" height="196.4" rx="3" fill="#9d7bff"/>
<text x="337.8" y="64.6" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$1.67</text>
<rect x="389.8" y="87.4" width="60.7" height="178.6" rx="3" fill="#46e0c0"/>
<text x="420.2" y="82.4" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$1.52</text>
<text x="379.0" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">claude-fable-5</text>
<rect x="524.2" y="225.5" width="60.7" height="40.5" rx="3" fill="#9d7bff"/>
<text x="554.5" y="220.5" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$0.34</text>
<rect x="606.5" y="230.1" width="60.7" height="35.9" rx="3" fill="#46e0c0"/>
<text x="636.8" y="225.1" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">$0.30</text>
<text x="595.7" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">grok-4.3</text>
<text x="54" y="314" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9">cost per full flight (USD) · lower is better</text>
</svg>

| Model | Mode | Tokens | Latency | Cost | CodeSearch saves |
|---|---|--:|--:|--:|--:|
| **grok-4.3** 🏆 | CodeSearch | 99.5k | 31s | **$0.3050** | −11% |
| grok-4.3 | Standard | 113.0k | 25s | $0.3441 | baseline |
| gpt-5.5 | CodeSearch | 53.1k | 37s | $0.3201 | **−39%** |
| gpt-5.5 | Standard | 98.3k | 47s | $0.5252 | baseline |
| claude-fable-5 | CodeSearch | 165.6k | 101s | $1.5167 | −9% |
| claude-fable-5 | Standard | 159.5k | 79s | $1.6676 | baseline |

> **CodeSearch saves** = each model's CodeSearch run vs *its own* Standard run — the tool mode's effect on that model. It's a big lever for gpt-5.5 (−39%) but small for grok (−11%) and Claude (−9%). The cross-model *cost* winner is grok either way — it's ~1/5th of Claude's bill, but that's the **model** choice, not the tool mode.

Three findings, in order of how much money they save you:

- **grok-4.3 is the cheapest *and* the fastest.** ~$0.30–0.34 a flight, done in ~25–31s. It's almost comically terse — asked to flip, it replied *"Forward flip completed."* — **4 output tokens.** Cheap talk, literally.
- **gpt-5.5 is right behind on cost and the leanest on tokens** ($0.32–0.53, 53–98k tokens). It's the model that responds best to the tool-mode trick below.
- **claude-fable-5 is the premium option** — the most thorough answers, but **~5× grok's cost and ~3× gpt-5.5's** for the exact same mission. Great model; you pay for it.

If the only thing you care about is the bill, **grok wins, gpt-5.5 is a close and leaner second, Claude is a deliberate splurge.**

> Cost = tokens × each model's price. gpt-5.5 and Claude are priced by Langfuse; grok-4.3 I priced from [models.dev](https://models.dev) at the grok-4 rate ($3/M in, $15/M out).

## Why the gap is so wide

It isn't just per-token price — it's **how much each model says**. Claude reasons out loud and writes verbose tool-discovery code, so it burns 160k+ tokens on a flight. grok is monosyllabic. gpt-5.5 sits in between but is disciplined. Two models can complete the identical mission and differ 5× on the bill purely from verbosity × price. You only see that if you meter it — which is the whole reason agentgateway sits in the middle.

## The second lever: MCP tool mode

There's a knob *within* each model. Every MCP call injects the **tool catalog** — the schema of all 28 tools — into the prompt. agentgateway can hide that behind two modes:

- **Standard** — all 28 tools, full schemas, every turn.
- **CodeSearch** — two meta-tools (`get_tool` to fetch one signature on demand, `run_code` to batch calls in a JS sandbox). Tiny context, fewer round-trips.

Here's tokens per flight, both modes, all three models:

<svg viewBox="0 0 720 320" role="img" aria-label="Tokens per flight — Standard vs CodeSearch, three models" style="width:100%;height:auto">
<text x="54" y="26" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="13" font-weight="700">Tokens per flight — Standard vs CodeSearch, three models</text>
<rect x="470" y="16" width="11" height="11" rx="2" fill="#9d7bff"/><text x="486" y="26" fill="#7788a1" font-family="ui-monospace,monospace" font-size="11">Standard</text>
<rect x="570" y="16" width="11" height="11" rx="2" fill="#46e0c0"/><text x="586" y="26" fill="#7788a1" font-family="ui-monospace,monospace" font-size="11">CodeSearch</text>
<line x1="54" y1="266.0" x2="704" y2="266.0" stroke="#1c2a3d"/>
<text x="48" y="269.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">0k</text>
<line x1="54" y1="213.0" x2="704" y2="213.0" stroke="#1c2a3d"/>
<text x="48" y="216.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">45k</text>
<line x1="54" y1="160.0" x2="704" y2="160.0" stroke="#1c2a3d"/>
<text x="48" y="163.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">90k</text>
<line x1="54" y1="107.0" x2="704" y2="107.0" stroke="#1c2a3d"/>
<text x="48" y="110.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">135k</text>
<line x1="54" y1="54.0" x2="704" y2="54.0" stroke="#1c2a3d"/>
<text x="48" y="57.0" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9" text-anchor="end">180k</text>
<rect x="90.8" y="150.2" width="60.7" height="115.8" rx="3" fill="#9d7bff"/>
<text x="121.2" y="145.2" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">98k</text>
<rect x="173.2" y="203.5" width="60.7" height="62.5" rx="3" fill="#46e0c0"/>
<text x="203.5" y="198.5" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">53k</text>
<text x="162.3" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">gpt-5.5</text>
<rect x="307.5" y="78.1" width="60.7" height="187.9" rx="3" fill="#9d7bff"/>
<text x="337.8" y="73.1" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">160k</text>
<rect x="389.8" y="71.0" width="60.7" height="195.0" rx="3" fill="#46e0c0"/>
<text x="420.2" y="66.0" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">166k</text>
<text x="379.0" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">claude-fable-5</text>
<rect x="524.2" y="132.9" width="60.7" height="133.1" rx="3" fill="#9d7bff"/>
<text x="554.5" y="127.9" fill="#9d7bff" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">113k</text>
<rect x="606.5" y="148.8" width="60.7" height="117.2" rx="3" fill="#46e0c0"/>
<text x="636.8" y="143.8" fill="#46e0c0" font-family="ui-monospace,monospace" font-size="10" text-anchor="middle" font-weight="600">100k</text>
<text x="595.7" y="284.0" fill="#e4ecf7" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">grok-4.3</text>
<text x="54" y="314" fill="#4c5c76" font-family="ui-monospace,monospace" font-size="9">total tokens per flight (thousands) · lower is better</text>
</svg>

The catch: **the tool mode that saves money is model-dependent.**

- On **gpt-5.5**, CodeSearch cut tokens **~46%** and cost **~39%** ($0.5252 → $0.3201). Big win.
- On **grok**, a modest trim (it's already terse).
- On **Claude**, CodeSearch **did nothing** — its verbose `run_code`/discovery steps used *more* tokens than Standard. The saving was cancelled out.

So you can't pick a tool mode in the abstract. **Benchmark the mode with the model you'll actually ship.** For gpt-5.5, flip to CodeSearch. For Claude, don't bother — spend your savings on picking a cheaper model instead.

### Where gpt-5.5's savings come from

One prompt dominates — the status report, because the agent polls `get_state` repeatedly:

| # | Prompt | Standard (calls / tokens) | CodeSearch (calls / tokens) |
|---|---|---|---|
| 5 | **Land + status report** | **17 / 45.1k** | 5 / 13.3k |

Standard burns 17 calls and 45k tokens on that one turn; CodeSearch collapses it into a single `run_code` that reads state once — 5 calls, 13k tokens. That's most of the −39%.

## The receipts — kagent tracing

None of this is estimated. kagent (Solo Enterprise for kagent) traces every flight — one trace per prompt, with input, output, duration, and tokens — and exports the same spans to Langfuse:

![kagent Tracing list: drone_agent flight traces, each a prompt (Take off, Do a flip, Take a photo, Spin 360, Land + status) with duration ~0.7–2.4s and ~2.8k–3.8k tokens per trace.](/images/articles/2026-07-06-drone-tool-modes/kagent-tracing-list.png)

Drill into a trace and you see the execution flow and every tool call. CodeSearch on Claude — `get_tool` then `run_code` to take the photo:

![kagent trace detail for drone_agent_cs_claude: Execution Flow shows get_tool then run_code; Trace Tree shows call_llm → generate_content (claude-fable-5) → openai.chat → execute_tool; 5,623 tokens for the turn.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-cs-claude.png)

Claude on Standard, doing the 360° via the `celebrate` tool and reading `get_state`:

![kagent trace detail for drone_agent_claude: celebrate + get_state tools; output reports a full 360° spin, 80cm, battery 75%; 6,997 tokens.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-claude.png)

And grok on CodeSearch — same shape, but look how little it says (4 output tokens — that's why grok's bill is tiny):

![kagent trace detail for drone_agent_cs_xai: get_tool + run_code on grok-4.3; the Do-a-flip turn returns just 'Forward flip completed' — 4 output tokens, 2,933 total.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-cs-xai.png)

## The gateway sees — and prices — every hop

agentgateway routes each MCP call to the right backend and tags it with the tool mode, method, status, and latency — which is exactly why the cost numbers exist:

```text
info request gateway=virtual-mcp-gateway route=drone-mcp
  http.method=POST http.path=/drone http.status=200
  protocol=mcp mcp.method.name=tools/list duration=3ms
info request gateway=virtual-mcp-gateway route=drone-mcp-codesearch
  http.method=POST http.path=/drone-codesearch http.status=200
  protocol=mcp mcp.method.name=tools/list duration=2ms
```

Because the same proxy fronts both the models and the MCP server, it meters both sides — one place to compare gpt-5.5, Claude, and grok on an apples-to-apples flight, and to swap between them with a config change.

## The money lesson

1. **Pick the model first — it's the 5× lever.** grok-4.3 flew the mission for ~1/5th the cost of Claude and finished 3× faster; gpt-5.5 is the leaner near-tie. Claude is a deliberate premium.
2. **Then tune the tool mode for that model.** CodeSearch saves gpt-5.5 ~39%; it does nothing for Claude.
3. **Meter everything.** Two models can finish the identical job and differ 5× on cost from verbosity alone. agentgateway makes both the swap and the measurement a one-liner.

Full flight, all three models, the charts, and the traces live on the flight deck: **[goose.maniak.ai](https://goose.maniak.ai)**.
