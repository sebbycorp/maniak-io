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

<div class="bt-traces">
  <div class="bt-card">
    <div class="bt-head"><span class="bt-name">Tracing</span><span class="bt-mode">one trace per prompt</span></div>
    <table class="bt-list">
      <tr><td>Take off and hover</td><td>1.11s</td><td>2,815</td></tr>
      <tr><td>Do a flip</td><td>0.74s</td><td>2,925</td></tr>
      <tr><td>Take a photo</td><td>1.51s</td><td>3,104</td></tr>
      <tr><td>Spin 360&deg;</td><td>1.03s</td><td>3,229</td></tr>
      <tr><td>Land + status report</td><td>1.46s</td><td>3,614</td></tr>
    </table>
  </div>
  <div class="bt-card">
    <div class="bt-head"><span class="bt-name">drone_agent_cs_claude</span><span class="bt-mode">CodeSearch &middot; claude-fable-5</span></div>
    <div class="bt-flow"><span class="bt-tool">get_tool</span><span class="bt-arr">&rarr;</span><span class="bt-tool">run_code</span></div>
    <div class="bt-badges"><span>prompt 5,503</span><span>output 120</span><span class="bt-tot">total 5,623</span></div>
    <div class="bt-out">&ldquo;&#128247; Photo captured &mdash; a bright indoor lab: a desk with two monitors, a potted plant by a window, pale grey walls.&rdquo;</div>
  </div>
  <div class="bt-card">
    <div class="bt-head"><span class="bt-name">drone_agent_claude</span><span class="bt-mode">Standard &middot; claude-fable-5</span></div>
    <div class="bt-flow"><span class="bt-tool">celebrate</span><span class="bt-arr">&middot;</span><span class="bt-tool">get_state</span></div>
    <div class="bt-badges"><span>prompt 6,898</span><span>output 99</span><span class="bt-tot">total 6,997</span></div>
    <div class="bt-out">&ldquo;&#127744; Full 360&deg; spin complete &mdash; height holding at 80 cm, battery 75%, attitude level.&rdquo;</div>
  </div>
  <div class="bt-card">
    <div class="bt-head"><span class="bt-name">drone_agent_cs_xai</span><span class="bt-mode">CodeSearch &middot; grok-4.3</span></div>
    <div class="bt-flow"><span class="bt-tool">get_tool</span><span class="bt-arr">&rarr;</span><span class="bt-tool">run_code</span></div>
    <div class="bt-badges"><span>prompt 2,921</span><span class="bt-hi">output 4</span><span class="bt-tot">total 2,933</span></div>
    <div class="bt-out">&ldquo;Forward flip completed.&rdquo; &mdash; grok in 4 output tokens. Terse and fast.</div>
  </div>
</div>
<style>
.bt-traces{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin:16px 0}
.bt-card{border:1px solid #26323f;border-radius:11px;background:#0b1119;padding:14px 15px;color:#9fb0c4}
.bt-head{display:flex;justify-content:space-between;align-items:baseline;gap:10px;border-bottom:1px solid #1c2a3d;padding-bottom:9px;margin-bottom:10px;flex-wrap:wrap}
.bt-name{font-family:ui-monospace,monospace;font-size:.82rem;color:#46e0c0;font-weight:600}
.bt-mode{font-family:ui-monospace,monospace;font-size:.6rem;letter-spacing:.1em;text-transform:uppercase;color:#6b7a90}
.bt-flow{display:flex;align-items:center;gap:8px;margin-bottom:11px}
.bt-tool{font-family:ui-monospace,monospace;font-size:.72rem;color:#dbe6f2;background:#16212e;border:1px solid #26323f;border-radius:6px;padding:4px 9px}
.bt-arr{color:#46e0c0;font-family:ui-monospace,monospace}
.bt-badges{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:10px}
.bt-badges span{font-family:ui-monospace,monospace;font-size:.58rem;letter-spacing:.06em;text-transform:uppercase;color:#8595a8;background:#101a26;border:1px solid #1c2a3d;border-radius:5px;padding:3px 7px}
.bt-badges .bt-tot{color:#dbe6f2}
.bt-badges .bt-hi{color:#ffb23e;border-color:#ffb23e}
.bt-out{font-size:.9rem;line-height:1.5;color:#9fb0c4}
.bt-list{width:100%;border-collapse:collapse;font-family:ui-monospace,monospace;font-size:.72rem;margin:0}
.bt-list td{padding:5px 4px;border-bottom:1px solid #1c2a3d;color:#9fb0c4}
.bt-list td:first-child{color:#dbe6f2}
.bt-list td:not(:first-child){text-align:right;color:#6b7a90}
@media(max-width:640px){.bt-traces{grid-template-columns:1fr}}
</style>

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
