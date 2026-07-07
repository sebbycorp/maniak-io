---
title: "My reMarkable Writes Back — and agentgateway Governs Every Word"
date: 2026-07-07
description: "I put a small C app on a reMarkable 2 that reads my pen, transcribes the handwriting with gpt-5.5 vision, asks the model I tap for, and writes the answer back onto the e-ink in cursive — letter by letter. Every question is a gateway call: keys in Vault, traces in Langfuse, and policies that can block or govern the request before it ever reaches a model. Two short demos: asking 'what is an agent substrate?' on paper, and watching agentgateway govern the traffic."
tags: ["agentgateway", "remarkable", "mcp", "llm-gateway", "governance", "langfuse", "vault", "e-ink", "kagent"]
categories: ["AI Gateway"]
---

Write a question on paper with a pen. Pause. The page **writes back** — a cursive answer, drawn onto the e-ink letter by letter, in the voice of whichever model you tapped. No screen glare, no keyboard, no page reload. Just ink answering ink.

That's the **ink desk** running on my reMarkable 2. It's a single self-contained C binary on the tablet that reads the Wacom pen, grabs the page as a PNG when I pause, has **gpt-5.5** vision transcribe my handwriting, sends the question to the model I've selected — OpenAI, Claude, Grok, or my **own local Qwen** — and renders the reply back onto the panel in a real cursive font.

Live page: **[goose.maniak.ai/remarkable.html](http://goose.maniak.ai/remarkable.html)**.

Here's the twist that matters to me: **the tablet never talks to a model directly.** Every call goes through *my* [agentgateway](https://agentgateway.dev). The keys live in Vault, every question is a trace in Langfuse, and any request can be **blocked or governed** by policy before it reaches a provider. This post is two acts — the desk itself, and the gateway that governs it.

---

## Act 1 — Write on paper, it writes back

The magic is a five-stage loop that never leaves the tablet except to call the gateway:

| # | Stage | What happens | On |
|---|-------|--------------|-----|
| 01 | **WRITE** | Reads the Wacom pen and draws your strokes straight to the panel | `evdev · rm2fb` |
| 02 | **READ** | On a short pause it captures the page as a PNG — in-app | `framebuffer → PNG` |
| 03 | **SEE** | gpt-5.5 vision reads the handwriting to text, so *any* model can answer | `gpt-5.5 · /openai` |
| 04 | **ASK** | The model you tapped replies — text, a flowchart, or a sketch | `via agentgateway` |
| 05 | **INK** | Rendered back onto the e-ink in cursive, letter by letter | `stb_truetype · A2` |

The reMarkable 2 has no usable framebuffer of its own, so the app drives the e-ink through **rm2fb** ([timower/rM2-stuff](https://github.com/timower/rM2-stuff)) — which means the tablet had to be downgraded to OS 3.22.4.2 (3.27 kept on the spare A/B partition as a fallback). The app is `diary.c`, cross-compiled for armv7 with the toltec toolchain, with **zero runtime dependencies**. Gestures are physical: tap the top-right to **switch models**, tap the top-left to **save the page** to your library, and flip the marker to its eraser end + tap to clear and start fresh. Ask it to *"diagram X"* and it auto-lays-out a mermaid-style flowchart on the page.

Here's the desk answering a real question — *"what is an agent substrate?"* — written by hand:

<div style="max-width:340px;margin:1.5rem auto;">
<div style="position:relative;padding-bottom:177.78%;height:0;overflow:hidden;border-radius:12px;">
<iframe src="https://www.youtube.com/embed/oeFj3B9T8M0" title="Asking a reMarkable 'what is an agent substrate?' — the page writes back in cursive" style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
</div>
</div>

I picked that question on purpose. An **[agent substrate](/articles/2026-06-25-kagent-agent-substrate-suspend-resume-kind/)** is the runtime layer that lets stateful agents suspend, resume, and survive — the thing that makes an agent more than a stateless prompt. Watching the tablet *hand-write the answer to a question about agent runtimes*, through the same gateway I use for everything else, is the whole point: the substrate, the governance, and the observability follow the agent — even onto paper.

---

## Act 2 — agentgateway governs every word

The desk is the fun part. The serious part is that **nothing on the tablet is privileged.** The app just hits OpenAI-compatible routes on the gateway's NodePorts over Wi-Fi:

- `:/openai` → OpenAI · gpt-5.5 (also the shared "eyes" that read every page)
- `:/anthropic` → Claude · claude-fable-5
- `:/grok` → xAI · Grok-4.3
- `:/spark` → local **Qwen3.6** on my own DGX Spark — no cloud, private model, on-paper ink

agentgateway injects each provider key (sourced from **Vault** via ESO), records every question as a **Langfuse** trace — latency, tokens, cost, like any other lab workload — and, crucially, applies policy. Because every answer is a gateway call, I can **govern and block** requests centrally: rate limits, spend caps, guardrails, and route rules all sit at the gateway, not on a tablet I'd have to re-flash to change my mind.

Here's agentgateway governing and blocking the traffic in real time:

<div style="max-width:340px;margin:1.5rem auto;">
<div style="position:relative;padding-bottom:177.78%;height:0;overflow:hidden;border-radius:12px;">
<iframe src="https://www.youtube.com/embed/amKZZEsimZc" title="agentgateway governing and blocking requests from the reMarkable ink desk" style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
</div>
</div>

Swap a model, tighten a limit, or block a route — and the tablet never changes. That's the difference between *a device that calls an API* and *an agent that runs behind a governed control plane*.

---

## The architecture, end to end

```text
reMarkable 2  (OS 3.22 · rm2fb drives the e-ink)
   pen ─► [ diary.c ] ─► capture page → PNG
                          │  Wi-Fi · agentgateway NodePorts (HTTP)
                          ▼
   ┌──────────────── agentgateway ────────────────┐
   │  gpt-5.5 reads the handwriting → text          │
   │  selected model answers → text / flowchart     │
   │  key from Vault (ESO) · traces → Langfuse      │
   │  policy: rate limits · spend caps · block      │
   └────────────────────────────────────────────────┘
        OpenAI · Claude · Grok · local Qwen (DGX Spark)
                          │
                          ▼
   answer written to the e-ink in cursive (letter by letter)
```

Everything model-facing is configured in one `MODELS[]` table in `diary.c`; everything *policy*-facing lives at the gateway. The tablet holds no secrets and enforces no rules — it just writes, captures, asks, and inks. Vault holds the keys, Langfuse holds the truth, and agentgateway holds the line.

The takeaway is small and stubborn: **governance follows the agent everywhere it goes — even to paper.** Your pen in, a cursive answer in your model's voice back on the page, and every word of it metered, traced, and governable.

Try it live at **[goose.maniak.ai/remarkable.html](http://goose.maniak.ai/remarkable.html)**.
