---
title: "Cheap Flights: How the Right MCP Tool Mode Cut My Drone Agent's Bill ~40%"
date: 2026-07-06
description: "I let AI agents fly a Ryze RoboMaster TT drone over MCP through Enterprise agentgateway, then measured the bill. Switching the tool mode from Standard to CodeSearch cut gpt-5.5's tokens ~46% and cost ~39% on a 28-tool catalog. I re-ran the identical flight on Claude and xAI and the savings changed — because the cheapest setup is a combination of tool mode AND model, not either alone. Real graphs, real agentgateway logs, and real kagent traces."
tags: ["agentgateway", "kagent", "mcp", "tool-modes", "langfuse", "drone", "tokenomics", "cost"]
categories: ["AI Gateway"]
---

I gave an AI agent a drone and a single instruction set — *take off, flip, photograph the room, spin, land* — and let it fly a real **Ryze RoboMaster TT** by calling a **28-tool MCP server** through [Enterprise agentgateway](https://agentgateway.dev). It works, it's delightful, and it costs money on every turn.

This post is about that bill — and how I cut it by ~40% **without changing the agent, the drone, or the flight**. Just one config knob: the MCP **tool mode**. Then I swapped the model three ways and the answer moved again. Every number here is measured, not guessed — pulled straight from kagent's tracing and Langfuse.

Live flight deck for the whole rig: **[goose.maniak.ai](https://goose.maniak.ai)**.

## The tax nobody sees: your tool catalog

Every time an LLM talks to an MCP server, the **tool catalog** — the JSON schema of every tool, its params, its description — gets injected into the prompt. For 28 drone tools that's a few thousand tokens of overhead **on every single turn**, before the model does one useful thing. That's the tax. The tool mode decides how you pay it.

agentgateway can serve the same MCP server four ways. Two matter for a mid-sized catalog:

- **Standard** — all 28 tools, full schemas, every turn. The model calls a tool directly; you re-send the whole catalog each time.
- **CodeSearch** — the model gets two meta-tools: `get_tool` (fetch one tool's typed signature on demand) and `run_code` (write JavaScript that calls the tools in a sandbox). Tiny context, and you batch calls in code instead of round-tripping.

Same drone, same 5-prompt flight, only the mode changes.

## Standard vs CodeSearch (gpt-5.5): −46% tokens, −39% cost

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

| Mode | Model calls | Tokens | Latency | Cost | vs Standard |
|---|--:|--:|--:|--:|--:|
| **Standard** | 35 | 98.3k | 47s | $0.5252 | baseline |
| **CodeSearch** | 21 | 53.1k | 37s | **$0.3201** | **−39%** |

For a 28-tool catalog, not shoving all 28 schemas into every turn is free money: **fewer calls, ~46% fewer tokens, ~39% lower cost — and it finished faster.**

### Where the money actually goes

One prompt dominates every run — the status report, because the agent polls `get_state` over and over to compose it:

| # | Prompt | Standard (calls / tokens / $) | CodeSearch (calls / tokens / $) |
|---|---|---|---|
| 1 | Take off and hover | 3 / 7.4k / $0.0443 | 4 / 8.6k / $0.0490 |
| 2 | Do a flip | 4 / 10.8k / $0.0583 | 4 / 9.2k / $0.0574 |
| 3 | Take a photo and describe | 6 / 17.7k / $0.0938 | 3 / 7.2k / $0.0462 |
| 4 | Spin 360° | 5 / 15.9k / $0.0832 | 5 / 12.7k / $0.0752 |
| 5 | **Land + status report** | **17 / 45.1k / $0.2457** | 5 / 13.3k / $0.0922 |

In Standard, that one prompt burns **17 calls and 45k tokens** — nearly half the flight. CodeSearch collapses it into a single `run_code` that reads state once and summarizes: **5 calls, 13k tokens**. That's most of the savings right there.

## But does it hold on other models?

I re-ran the **identical** Standard and CodeSearch flights on Claude (`claude-fable-5`) and xAI (`grok-4.3`), each through its own agentgateway route. Nothing changed but the model:

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

| Model | Mode | Calls | Tokens | Latency | Cost |
|---|---|--:|--:|--:|--:|
| **gpt-5.5** | Standard | 35 | 98.3k | 47s | $0.5252 |
| **gpt-5.5** | CodeSearch | 21 | **53.1k** | 37s | $0.3201 |
| **claude-fable-5** | Standard | 26 | 159.5k | 79s | $1.6676 |
| **claude-fable-5** | CodeSearch | 33 | 165.6k | 101s | $1.5167 |
| **grok-4.3** | Standard | 34 | 113.0k | 25s | $0.3441 |
| **grok-4.3** | CodeSearch | 33 | 99.5k | 31s | **$0.3050** |

> Cost = tokens × each model's price. gpt-5.5 and Claude are priced by Langfuse; grok-4.3 I priced from [models.dev](https://models.dev) at the grok-4 rate ($3/M in, $15/M out).

Three things fall out, and they're the whole point:

- **CodeSearch is not universally a win.** It cut gpt-5.5's tokens ~46%, but on **Claude it did nothing** — Claude writes verbose discovery/`run_code` steps, so the smaller context is cancelled out by longer generations (its CodeSearch run actually used *more* tokens than Standard).
- **The model is the bigger lever than the mode.** `claude-fable-5` is thorough but costs **~5× grok and ~3× gpt-5.5** for the same flight. If you're cost-sensitive, picking the model matters more than picking the mode.
- **grok-4.3 is the sleeper** — cheapest run of the whole matrix ($0.3050) *and* fastest by a mile (~25–31s vs Claude's ~80–100s). It's almost comically terse: on "Do a flip" it replied *"Forward flip completed."* — **4 output tokens.**

**The cheapest setup is a combination:** the right tool mode *for that model*. Benchmark the pair you'll actually ship — don't pick either in the abstract.

## The receipts — kagent tracing

None of this is estimated. kagent (Solo Enterprise for kagent) traces every flight — one trace per prompt, with input, output, duration, and token count — and exports the same spans to Langfuse. Here's the tracing list for a flight:

![kagent Tracing list: drone_agent flight traces, each row a prompt (Take off and hover, Do a flip, Take a photo, Spin 360, Land + status report) with start time, duration ~0.7–2.4s, and ~2.8k–3.8k tokens per trace.](/images/articles/2026-07-06-drone-tool-modes/kagent-tracing-list.png)

Drill into a single trace and you get the **execution flow** and the **trace tree** — every `call_llm`, every `execute_tool`. Here's CodeSearch on Claude discovering a tool with `get_tool`, then running `run_code` to take the photo:

![kagent trace detail for drone_agent_cs_claude: Execution Flow shows the agent calling get_tool then run_code; Trace Tree shows call_llm → generate_content (claude-fable-5) → openai.chat → execute_tool get_tool/run_code; the output describes a bright indoor lab. 5,623 tokens for the turn.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-cs-claude.png)

Standard mode on Claude, doing the 360° spin via the `celebrate` tool and reading `get_state`:

![kagent trace detail for drone_agent_claude: Execution Flow shows celebrate and get_state tools; output reports a full 360° spin, height 80cm, battery 75%; 6,997 tokens for the turn.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-claude.png)

And grok on CodeSearch — same `get_tool` + `run_code` shape, but notice how little it says (that terseness is why grok's token counts stay low):

![kagent trace detail for drone_agent_cs_xai: Execution Flow shows get_tool and run_code on grok-4.3; the Do-a-flip turn returns just 'Forward flip completed' — 4 output tokens, 2,933 total.](/images/articles/2026-07-06-drone-tool-modes/kagent-trace-cs-xai.png)

## The gateway sees every hop

agentgateway sits in the middle and tags each MCP request with its tool-mode route, the MCP method, status, and latency — which is exactly why the cost numbers exist. Straight from the proxy:

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

One place to watch, meter, rate-limit, and guardrail every tool call — regardless of which agent or model made it.

## The kagent transcript

And the agent actually flying, prompt by prompt (the Standard/gpt-5.5 run):

```text
▸ Take off and hover.
  Airborne and hovering at ~80 cm. Battery 90%, link live, attitude stable.
▸ Do a flip.
  Front flip complete. Back in hover at ~80 cm.
▸ Take a photo and describe what you see.
  Photo captured. A bright indoor lab: desk with two monitors, a potted plant
  by a window, pale grey walls.
▸ Spin around 360 degrees.
  360° clockwise spin complete. Back in hover.
▸ Land and give me a status report.
  Landed. 0 cm, link live, attitude level (roll 0 / pitch 0 / yaw 0), battery 86%.
```

## The money lesson

Two knobs, and both are one-line changes because agentgateway sits between the model and the tools:

1. **Tool mode** (`toolMode: Standard` → `CodeSearch`) cut gpt-5.5's bill ~39% on this 28-tool catalog — but did nothing for Claude. Measure it on *your* catalog and *your* model.
2. **Model** (`modelConfig`) is the bigger lever: grok-4.3 flew the same mission for **~1/5th the cost of Claude** and finished 3× faster.

The gateway makes trying every combination a config change and a Langfuse query — so there's no excuse not to measure before you ship. Full 28-tool catalog, command lifecycle, and these results live on the flight deck: **[goose.maniak.ai](https://goose.maniak.ai)**.
