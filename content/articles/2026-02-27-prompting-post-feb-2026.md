---
title: "Prompting After Feb 2026: Prompt Craft → Context → Intent → Specs"
publishDate: 2026-02-27
author: "Sebastian Maniak"
description: "If you’re still ‘prompting’ like it’s a chat, you’re leaving 10x on the table. The modern stack is prompt craft, context engineering, intent engineering, and specification engineering. Here’s the practical playbook."
---

Most people mean “write better prompts” when they say *prompt engineering*.

That was a winning strategy in 2024–2025, when the dominant workflow was:

> ask in chat → get an answer → iterate in real time

But as models become longer-running and more autonomous, the bottleneck shifts. You don’t get to babysit the session. You have to **encode oversight up front**.

This post is a practical distillation of a YouTube video that argues “prompting” is now hiding **four different disciplines** — and you need all four to get consistent, production-quality outcomes.

Source video: https://youtu.be/BpibZSMGtdY

---

## The Four Disciplines of “Prompting” in 2026

### 1) Prompt craft (table stakes)
This is the classic skill:

- Clear instruction
- Examples + counterexamples
- Guardrails (what to do / what not to do)
- Explicit output format
- Rules for ambiguity (“if X conflicts with Y, do Z”)

It still matters — it just doesn’t differentiate you anymore.

### 2) Context engineering (your real leverage)
Your prompt might be 200 tokens.
Your context window might be 200k–1M.

That means your “prompt” is a rounding error.

Context engineering is the work of designing the information environment the agent runs inside:

- system prompts / agent instructions
- tool definitions + permissions
- RAG sources / docs / repos
- memory (what persists across runs)
- conventions (how this org writes, builds, tests, ships)

If you see someone getting 10x more out of the same model, they usually aren’t “better at wording.”
They built better context infrastructure.

### 3) Intent engineering (what the agent should *want*)
Context tells the agent **what to know**.
Intent tells the agent **what to optimize for**.

This is where teams break things at enterprise scale:

- speed vs quality
- cost vs correctness
- customer satisfaction vs ticket closure time
- “ship it” vs “fail safe”

If you don’t encode trade-offs and escalation triggers, the agent will “pick a metric” implicitly.

### 4) Specification engineering (blueprints for autonomous work)
Specs are what you write when you can’t rely on real-time correction.

A good spec is:

- self-contained
- structured
- internally consistent
- explicit about quality measurement

If your output keeps coming back “80% correct,” you don’t have a prompt problem.
You have a spec + evaluation problem.

---

## The 2026 Prompting Checklist (copy/paste)

Use this before you hand a long-running task to an agent.

- [ ] **Objective**: what outcome do you want, and why?
- [ ] **Success metric**: how will we measure success?
- [ ] **Inputs**: links/docs/data sources (authoritative only)
- [ ] **Definitions**: terms/acronyms the agent might misread
- [ ] **Deliverables**: files/sections/artifacts + exact output format
- [ ] **Acceptance criteria**: verifiable checks (someone else can evaluate)
- [ ] **Constraints**:
  - Must
  - Must not
  - Preferences
  - Escalate if
- [ ] **Plan-first**: ask for a plan + checkpoints before execution
- [ ] **Decomposition**: tasks broken into verifiable sub-steps
- [ ] **Eval**: test cases / verification steps
- [ ] **Progress log**: so the next session doesn’t start blind

---

## Templates (use these as your default “prompt format”)

### Template A — Self-contained spec (general)

```markdown
## Objective
- What to do:
- Why it matters:
- Audience:

## Inputs (authoritative)
- Links/docs:
- Definitions/glossary:

## Deliverables
- D1:
- D2:

## Acceptance criteria
- [ ]
- [ ]

## Constraints
- Must:
- Must not:
- Preferences:
- Escalate if:

## Workflow
1) Propose plan + checkpoints.
2) Wait for confirmation.
3) Execute.
4) Provide final output + verification notes.
```

### Template B — Coding task spec

```markdown
## Repo context
- Repo root:
- Build commands:
- Test commands:
- Conventions (style, lint, naming, etc.):

## Change request
- Feature/bug:
- Non-goals:

## Constraints
- Must not break:
- Security/perf constraints:
- Escalate if:

## Acceptance criteria
- Tests added/updated:
- Commands that must pass:
- Manual validation steps:

## Rollout
- Backwards compatibility:
- Migration steps:
```

### Template C — Research task spec

```markdown
## Question

## Constraints
- Time horizon:
- Must cite primary sources:
- Output format:

## Deliverables
- Executive summary (5 bullets)
- Findings (with links)
- Risks/unknowns
- Recommendations

## Evaluation
- What would make this wrong?
- How can we verify quickly?
```

---

## Failure Modes I See Constantly (and how to fix them)

1) **“It’s 80% right but takes forever to clean up.”**
   - Fix: acceptance criteria + explicit output format + examples/counterexamples.

2) **“The agent drifted after 30 minutes.”**
   - Fix: constraints + escalation triggers + checkpoints + progress log.

3) **“We loaded everything and quality got worse.”**
   - Fix: curate context; summarize; move stable conventions into a short, high-signal rule file.

4) **“It optimized for the wrong thing.”**
   - Fix: intent engineering — explicitly state trade-offs and priorities.

5) **“We can’t tell if outputs are good.”**
   - Fix: eval design — build test cases; rerun after model updates; track regressions.

---

## What to Do This Week

If you want an easy, practical on-ramp:

1) Pick **one recurring task** (deck creation, incident writeups, migration plans, content outlines).
2) Write a **self-contained spec** using Template A.
3) Define **acceptance criteria** that another person could verify.
4) Create **3–5 eval cases** (known-good examples).
5) Save it as your baseline prompt/spec and iterate as models change.

That’s the shift: from “chat tricks” to **repeatable systems**.
