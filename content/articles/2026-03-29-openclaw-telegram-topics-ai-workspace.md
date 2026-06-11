---
title: "How I Built a Multi-Topic AI Workspace with OpenClaw and Telegram"
date: 2026-03-29
description: "A practical guide to configuring OpenClaw's Telegram forum topics as isolated AI workspaces — each with its own model, skills, memory, and storage. From one flat chat to a structured command center."
tags: ["openclaw", "ai", "telegram", "automation", "personal-ai"]
categories: ["AI & Agents"]
---

## The Problem with One Big Chat

When I first set up OpenClaw, I did what most people do — one Telegram chat, one conversation, everything in one place. It worked... for about a week.

Then things got messy. I'd ask about a Kubernetes issue and the AI would reference a recipe I'd asked about earlier. I'd try to draft a blog post and it would pull in context from a client billing discussion. The context window — the amount of conversation the AI can hold at once — was polluted with everything from smart home commands to security audits.

The real problem isn't that the AI is bad at context. It's that **a single conversation thread forces every topic to compete for the same limited context window.** When that window fills up, older messages get compressed into summaries. Summaries lose details. Your agent slowly forgets who you are, what you're working on, and what you told it yesterday.

I lost an entire project's context once because of this. Spent 2 hours re-explaining preferences and decisions my agent already knew. Never again.

## The Solution: Telegram Forum Topics

Telegram has a feature called **Topics** (or Forum mode) that turns a group into a structured space where each topic is its own isolated thread. OpenClaw supports this natively — you can configure each topic with:

- **Its own system prompt** (personality and instructions)
- **Its own model** (Opus for deep work, Sonnet for quick tasks)
- **Its own skills** (only the tools that topic needs)
- **Its own storage** (Notion page + Google Drive folder)
- **Its own memory path** (separate daily logs per domain)
- **Its own session** (isolated context window — zero cross-contamination)

Think of it as giving your AI a **different desk for each type of work.** When you walk up to the Content desk, it's already thinking about content. When you walk up to the Infra desk, it's in ops mode. They don't leak into each other.

## My Setup: 9 Topics

Here's how I have mine structured:

| Topic | Model | Skills | Purpose |
|-------|-------|--------|---------|
| 📋 Mission Control | Sonnet (default) | — | Tasks, priorities, reminders, deadlines |
| 🏠 Home | Sonnet | sonoscli, camsnap, weather | Smart home: Sonos, cameras, devices |
| ⚙️ Infra & K8s | Sonnet (default) | github, gh-issues, coding-agent, healthcheck | Kubernetes clusters, logs, incident response |
| ✍️ Content | **Opus** | notion, summarize, xurl, blogwatcher | Scripts, social posts, webinar prep |
| 🔍 Research | **Opus** | notion, summarize, blogwatcher, github | Deep dives on people, products, companies |
| 💪 Health & Fitness | Sonnet | weather | WHOOP data, workouts, health tracking |
| 🤖 AI & Agents | Sonnet (default) | — | OpenClaw config, skill development, experiments |
| ⚡ Overflow | Sonnet | — | Quick asks that don't fit elsewhere |
| 💼 Corp | Sonnet (default) | — | Client relationships, billing, time tracking |

## Step-by-Step Setup

### 1. Create the Telegram Forum Group

1. Open Telegram → **New Group** → name it (I called mine "OpenClaw")
2. Add your OpenClaw bot to the group
3. Go to **Group Settings → Edit → Enable Topics** (Forum mode)
4. Create each topic with an emoji prefix for quick scanning

Each topic gets a numeric ID from Telegram. You'll need these for the config.

### 2. Get Your IDs

You need three things:
- **Group chat ID**: the negative number for your group (check Gateway logs after sending a message)
- **Topic IDs**: each topic's thread number (also in logs)
- **Your Telegram user ID**: use `@userinfobot` in Telegram

### 3. Define Your Agents

Before configuring topics, set up agents in `openclaw.json`. Each agent maps to a model:

```json5
{
  agents: {
    defaults: {
      model: {
        primary: "anthropic/claude-sonnet-4-6",
        fallbacks: ["anthropic/claude-opus-4-6"]
      }
    },
    list: [
      { id: "main" },
      {
        id: "opus",
        name: "opus",
        workspace: "~/.openclaw/workspace",
        agentDir: "~/.openclaw/agents/opus/agent",
        model: "anthropic/claude-opus-4-6"
      },
      {
        id: "sonnet",
        name: "sonnet",
        workspace: "~/.openclaw/workspace",
        agentDir: "~/.openclaw/agents/sonnet/agent",
        model: "anthropic/claude-sonnet-4-6"
      }
    ]
  }
}
```

Key decisions:
- **All agents share the same workspace** — so `SOUL.md`, `AGENTS.md`, and `MEMORY.md` are consistent
- **Each agent gets its own `agentDir`** — for separate auth profiles and sessions
- **Sonnet is the default** — fast and cheap for 80% of tasks
- **Opus is reserved** — only for topics that need deep reasoning or creativity

### 4. Configure the Telegram Group

Here's the structure inside `openclaw.json`:

```json5
{
  telegram: {
    enabled: true,
    botToken: "YOUR_BOT_TOKEN",
    dmPolicy: "pairing",
    groupPolicy: "allowlist",

    groups: {
      // Default for ALL groups: require @mention
      "*": {
        requireMention: true
      },

      // Your specific forum group
      "-1003885751519": {
        requireMention: false,
        allowFrom: ["775644809"],  // Only YOUR Telegram user ID

        topics: {
          // Each topic goes here...
        }
      }
    }
  }
}
```

### 5. Configure Each Topic

Every topic follows the same pattern:

```json5
"TOPIC_ID": {
  requireMention: false,
  agentId: "opus",  // or "sonnet", or omit for default
  skills: ["skill-a", "skill-b"],
  systemPrompt: "MISSION + STYLE + STORAGE + MEMORY"
}
```

Here's a real example — my Content topic:

```json5
"48": {
  requireMention: false,
  agentId: "opus",
  skills: ["notion", "summarize", "xurl", "blogwatcher"],
  systemPrompt: "You help draft scripts, social posts, and webinar prep. Match the user's voice and tone. Ask clarifying questions before producing long-form content.\n\nStorage:\n- Notion page: 32d4d457-9015-8138-ba2d-e40df5d4b20e (Content)\n- Google Drive folder: 1__Z8KpROUZucvWbH-4cRzw8tA1BhWFDM (Content)\nUse Notion for drafts, content calendar, and outlines. Use Drive for final assets, slides, and media.\n\nDaily memory: Write dated notes to `memory/content/YYYY-MM-DD.md` for this topic."
}
```

### The System Prompt Pattern

Every topic system prompt follows four parts:

1. **MISSION** — What this topic does (1-2 sentences)
   > "You manage tasks, priorities, and reminders."

2. **STYLE** — How to respond
   > "Be proactive about deadlines. Keep answers practical."

3. **STORAGE** — Where to save work
   > "Notion page: `<ID>` (Mission Control) / Drive folder: `<ID>`"

4. **MEMORY** — Where to write daily logs
   > "Write dated notes to `memory/mission-control/YYYY-MM-DD.md`"

This ensures every topic knows its job, its voice, where to put things, and where to journal. When you open a topic, the AI is already in the right headspace.

## Model Routing: The Strategy

Not every task needs the most expensive model. Here's my routing logic:

**Use Opus (frontier model) when:**
- Creative writing — blog posts, scripts, social content
- Deep research — connecting non-obvious dots across sources
- Complex reasoning — architecture decisions, strategy

**Use Sonnet (fast/cheap) for everything else:**
- Task management — creating, updating, tracking tasks
- Smart home — "play jazz in the kitchen" doesn't need genius
- Health data — querying WHOOP stats is structured, not creative
- Quick asks — definitions, lookups, simple questions
- Ops work — kubectl commands, log parsing, incident response

The result: **~80% of my interactions use Sonnet** (faster, cheaper), and the 20% that use Opus actually benefit from it.

## Skills Routing: Keep It Lean

Each topic only loads the skills it needs. This matters because:

- Every skill adds instructions to the system prompt
- More instructions = more tokens consumed per turn
- More tokens = faster context window fill-up = more compaction = more forgetting

My mapping:

| Topic | Skills | Why |
|-------|--------|-----|
| 🏠 Home | sonoscli, camsnap, weather | Smart device control |
| ⚙️ Infra | github, gh-issues, coding-agent, healthcheck | DevOps workflow |
| ✍️ Content | notion, summarize, xurl, blogwatcher | Content pipeline |
| 🔍 Research | notion, summarize, blogwatcher, github | Research tools |
| 💪 Health | weather | Outdoor planning |
| Everything else | *(none)* | Keep it lean |

**Rule of thumb:** if a skill isn't used weekly in a topic, remove it.

## Memory: Separate Paths Per Domain

This is the key insight that makes the whole architecture work. Each topic writes its daily logs to a **separate memory subdirectory**:

```
memory/
├── mission-control/
│   └── 2026-03-29.md
├── home/
│   └── 2026-03-29.md
├── infra/
│   └── 2026-03-29.md
├── content/
│   └── 2026-03-29.md
├── research/
│   └── 2026-03-29.md
├── health/
│   └── 2026-03-29.md
├── ai/
│   └── 2026-03-29.md
├── corp/
│   └── 2026-03-29.md
└── general/
    └── 2026-03-29.md
```

Why this matters:
- **No cross-contamination** — infra notes don't pollute your content drafts
- **Vector search stays relevant** — when searching memory from the Content topic, you find content notes, not Kubernetes debugging logs
- **Compaction is less painful** — each topic's session is smaller and more focused, so compaction happens less often and loses less context

Combined with `MEMORY.md` for permanent long-term storage (key facts, project overviews, infrastructure details), this creates a layered memory system:

- **MEMORY.md** — permanent, cross-topic, loaded every session
- **memory/<domain>/YYYY-MM-DD.md** — daily, topic-specific, searched on demand

## Security: Three Layers

The config implements three security layers:

```json5
{
  groupPolicy: "allowlist",                    // Layer 1: only approved groups
  groups: {
    "*": { requireMention: true },             // Layer 2: strangers must @mention
    "-1003885751519": {
      requireMention: false,
      allowFrom: ["775644809"]                 // Layer 3: only YOUR user ID
    }
  },
  dmPolicy: "pairing"                          // DMs require pairing code
}
```

Even if someone joins your Telegram group:
- They can't trigger the bot in other groups (`groupPolicy: "allowlist"`)
- They'd need to @mention the bot in random groups (`requireMention: true` on `"*"`)
- They can't trigger actions in your forum (`allowFrom` restricts to your user ID)

## Storage: Per-Topic Notion + Drive

Each topic has its own Notion page and Google Drive folder. This means:

- **Content topic** → drafts go to the Content Notion page, final slides go to the Content Drive folder
- **Infra topic** → runbooks go to the Infra Notion page, log dumps go to the Infra Drive folder
- **Corp topic** → client notes go to the Corp Notion page, contracts go to the Corp Drive folder

No hunting. No "which folder was that in?" Everything is organized by domain from the moment it's created.

## Tips From 3+ Months of Use

1. **Start with 3-4 topics** — add more when you find natural boundaries
2. **Overflow is essential** — random questions need somewhere to go without polluting focused topics
3. **Emoji prefixes matter** — when you have 9 topics, visual scanning speed matters
4. **Review monthly** — merge underused topics, split overloaded ones
5. **Pin important messages** in each topic for quick reference
6. **Keep system prompts under 500 words** — they're injected every turn
7. **Memory subdirectories are non-negotiable** — this is what prevents context bleed
8. **Use a Meta topic** (my "AI & Agents") for discussing the setup itself
9. **Back up `openclaw.json`** — it's the single source of truth for this entire architecture
10. **The cheapest model that works is the right model** — don't waste Opus on "what's the weather"

## The Complete Config

Here's the full relevant section of my `openclaw.json` for reference:

```json5
{
  telegram: {
    enabled: true,
    botToken: "YOUR_BOT_TOKEN",
    dmPolicy: "pairing",
    groupPolicy: "allowlist",
    streaming: "off",

    groups: {
      "*": { requireMention: true },

      "-YOUR_GROUP_ID": {
        requireMention: false,
        allowFrom: ["YOUR_USER_ID"],

        topics: {
          "45": {
            requireMention: false,
            systemPrompt: "You manage tasks, priorities, and reminders. Be proactive about deadlines and follow-ups. Track what's pending and surface what needs attention.\n\nStorage:\n- Notion page: <ID> (Mission Control)\n- Google Drive folder: <ID> (Mission Control)\nUse Notion for tasks, SOPs, and structured notes. Use Drive for file attachments and exports.\n\nDaily memory: Write dated notes to `memory/mission-control/YYYY-MM-DD.md` for this topic."
          },
          "46": {
            requireMention: false,
            agentId: "sonnet",
            skills: ["sonoscli", "camsnap", "weather"],
            systemPrompt: "You assist with home automation: Sonos, cameras, and smart devices. Keep answers practical and action-oriented.\n\nStorage:\n- Notion page: <ID> (Home)\n- Google Drive folder: <ID> (Home)\n\nDaily memory: Write dated notes to `memory/home/YYYY-MM-DD.md` for this topic."
          },
          "47": {
            requireMention: false,
            skills: ["github", "gh-issues", "coding-agent", "healthcheck"],
            systemPrompt: "You assist with Kubernetes clusters, logs, and incident response. Be concise and ops-focused. Prefer actionable commands over lengthy explanations.\n\nStorage:\n- Notion page: <ID> (Infra & K8s)\n- Google Drive folder: <ID> (Infra & K8s)\n\nDaily memory: Write dated notes to `memory/infra/YYYY-MM-DD.md` for this topic."
          },
          "48": {
            requireMention: false,
            agentId: "opus",
            skills: ["notion", "summarize", "xurl", "blogwatcher"],
            systemPrompt: "You help draft scripts, social posts, and webinar prep. Match the user's voice and tone. Ask clarifying questions before producing long-form content.\n\nStorage:\n- Notion page: <ID> (Content)\n- Google Drive folder: <ID> (Content)\n\nDaily memory: Write dated notes to `memory/content/YYYY-MM-DD.md` for this topic."
          },
          "49": {
            requireMention: false,
            agentId: "opus",
            skills: ["notion", "summarize", "blogwatcher", "github"],
            systemPrompt: "You research people, products, companies, and ideas. Cite sources, be thorough, and surface non-obvious connections.\n\nStorage:\n- Notion page: <ID> (Research)\n- Google Drive folder: <ID> (Research)\n\nDaily memory: Write dated notes to `memory/research/YYYY-MM-DD.md` for this topic."
          },
          "50": {
            requireMention: false,
            agentId: "sonnet",
            skills: ["weather"],
            systemPrompt: "You help with WHOOP data, workout planning, and health dashboard work. Be data-driven and concise.\n\nStorage:\n- Notion page: <ID> (Health & Fitness)\n- Google Drive folder: <ID> (Health & Fitness)\n\nDaily memory: Write dated notes to `memory/health/YYYY-MM-DD.md` for this topic."
          },
          "51": {
            requireMention: false,
            systemPrompt: "You help with OpenClaw configuration, skill development, and agent experiments. You can be technical and detailed here.\n\nStorage:\n- Notion page: <ID> (AI & Agents)\n- Google Drive folder: <ID> (AI & Agents)\n\nDaily memory: Write dated notes to `memory/ai/YYYY-MM-DD.md` for this topic."
          },
          "66": {
            requireMention: false,
            agentId: "sonnet",
            systemPrompt: "You handle overflow and quick asks. Keep responses short and direct.\n\nDaily memory: Write dated notes to `memory/general/YYYY-MM-DD.md` for this topic."
          },
          "387": {
            requireMention: false,
            systemPrompt: "You manage customer relationships, project billing, and time tracking. Focus on: active clients, logged hours, invoices, and follow-ups. Be direct — flag unbilled time, overdue invoices, and upcoming deadlines.\n\nStorage:\n- Notion page: <ID> (Corp)\n- Google Drive folder: <ID> (Corp)\n\nDaily memory: Write dated notes to `memory/corp/YYYY-MM-DD.md` for this topic."
          }
        }
      }
    }
  },

  agents: {
    defaults: {
      model: {
        primary: "anthropic/claude-sonnet-4-6",
        fallbacks: ["anthropic/claude-opus-4-6"]
      }
    },
    list: [
      { id: "main" },
      {
        id: "opus",
        workspace: "~/.openclaw/workspace",
        agentDir: "~/.openclaw/agents/opus/agent",
        model: "anthropic/claude-opus-4-6"
      },
      {
        id: "sonnet",
        workspace: "~/.openclaw/workspace",
        agentDir: "~/.openclaw/agents/sonnet/agent",
        model: "anthropic/claude-sonnet-4-6"
      }
    ]
  }
}
```

## What's Next

This setup has transformed how I interact with AI. Instead of one overwhelmed assistant trying to be everything, I have a team of specialists — each focused, each equipped, each with its own memory. The context window problem is essentially solved because no single topic accumulates enough history to trigger aggressive compaction.

If you're running OpenClaw with a single chat thread and wondering why it "forgets things" — this is probably your answer. Thread it. Topic it. Give each domain its own space.

The AI doesn't forget when you organize its memory.

---

*Running OpenClaw? Join the community at [discord.com/invite/clawd](https://discord.com/invite/clawd). Find skills at [clawhub.ai](https://clawhub.ai).*
