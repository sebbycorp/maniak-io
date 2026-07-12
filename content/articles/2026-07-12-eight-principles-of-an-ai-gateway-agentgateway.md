---
title: "The 8 Principles of an AI Gateway (and Why They Matter) — with agentgateway from Solo"
date: 2026-07-12
description: "AI agents don't fail like microservices fail. They leak, they loop, they overspend, and they call tools you never audited. This is a deep dive into the eight principles every AI gateway must satisfy — unified LLM access, MCP federation, A2A, guardrails, multi-auth, budgets and failover, observability, and YAML policy — grounded in agentgateway from Solo with real config."
tags: ["agentgateway", "solo", "ai-gateway", "mcp", "a2a", "guardrails", "rbac", "oauth", "jwt", "observability", "opentelemetry", "rate-limiting", "budgets", "failover", "cel", "yaml"]
categories: ["AI Gateway"]
---

You wouldn't put a hundred microservices into production with no gateway,
no auth, no rate limits, and no logs. Yet that is exactly how most teams
ship AI agents today: an API key baked into a container, a direct line to
an LLM, and a growing pile of MCP tool servers that nobody is governing.

Agents don't fail the way microservices fail. A microservice returns a 500
and you page someone. An agent quietly sends your customer table to a
third‑party model, loops a thousand times on a bad prompt and burns your
monthly budget before lunch, or discovers a tool you never meant to expose
and happily calls it. The failure modes are new, so the control plane has
to be new too.

That is what an **AI gateway** is for. Not "an API gateway with an LLM
route" — a purpose‑built data plane that understands LLM traffic, MCP
sessions, and agent‑to‑agent calls, and applies policy to all three.

This post walks through the **eight principles** an AI gateway has to get
right, why each one matters in production, and how
[**agentgateway**](https://github.com/agentgateway/agentgateway) — the
open‑source (CNCF) project, packaged and hardened by
[**Solo.io**](https://www.solo.io/) as Enterprise agentgateway — implements
them. Every principle gets a *why* and a *how*, with config you can read.

If you want the "why does this exist at all" version first, start with
[What is agentgateway.dev?](/articles/2026-03-12-what-is-agentgateway-dev/)
and [Why your AI agents need a gateway](/articles/2026-02-19-why-your-ai-agents-need-a-gateway/).

---

## The eight principles at a glance

| # | Principle | The problem it solves |
|---|-----------|-----------------------|
| 1 | **Unified OpenAI‑compatible LLM access** | Every provider has a different SDK, auth, and payload. Apps get locked to one vendor. |
| 2 | **MCP tool federation** (stdio/HTTP/SSE/OpenAPI) | Each tool server is a separate connection, auth surface, and thing to secure. |
| 3 | **Secure A2A agent discovery & collaboration** | Agents calling agents with no identity, no scoping, no audit. |
| 4 | **Built‑in guardrails** (regex / moderation / webhooks) | PII, secrets, and prompt injection flow straight through to the model. |
| 5 | **Multi‑auth security** (JWT / OAuth / RBAC / CEL) | One coarse API key can do everything. No per‑user, per‑tool authorization. |
| 6 | **Rate limiting, budgets & failover routing** | One runaway loop drains the budget; one provider outage kills every agent. |
| 7 | **Full observability** (OpenTelemetry / TLS) | No traces, no token accounting, no idea what a prompt cost or where it went. |
| 8 | **YAML policy‑driven config** | Governance living in app code and dashboards can't be reviewed, versioned, or rolled back. |

None of these is optional at scale. Skip one and it becomes the incident.
Let's take them one at a time.

---

## 1. Unified, OpenAI‑compatible LLM access

**Why it matters.** The moment you have more than one model provider — and
you will, the day OpenAI has an outage or Anthropic ships something better
— you feel the tax. OpenAI, Anthropic, Gemini, Bedrock, Vertex, and your
self‑hosted vLLM all speak *almost* the same dialect but differ in auth
headers, request shape, streaming semantics, and error codes. If each
application wires directly to each provider, you've hard‑coded vendor
lock‑in into every service, and swapping a model means a code change and a
redeploy.

An AI gateway makes this a routing concern. Apps speak **one**
OpenAI‑compatible API to the gateway; the gateway translates to whatever
provider sits behind the route. Changing models becomes a config change,
not a code change.

**How agentgateway does it.** A backend declares the provider; a route maps
a path prefix to that backend and normalizes the API surface. Here's a
single standalone config front‑ending both Anthropic and OpenAI behind one
port:

```yaml
binds:
- port: 4001

listeners:
- name: default
  protocol: HTTP

routes:
- name: claude
  matches:
  - path:
      pathPrefix: /claude
  policies:
    urlRewrite:
      path:
        prefix: /
  backends:
  - ai:
      name: claude
      provider:
        anthropic: {}

- name: openai
  matches:
  - path:
      pathPrefix: /openai
  policies:
    urlRewrite:
      path:
        prefix: /
  backends:
  - ai:
      name: openai
      provider:
        openAI:
          model: gpt-4o-mini
```

Your application points `OPENAI_BASE_URL` (or `ANTHROPIC_BASE_URL`) at the
gateway and never holds a provider key again. On Kubernetes the same idea
is expressed as an `AgentgatewayBackend` with an `ai.provider` block and an
`HTTPRoute` — see
[Your first AI route](/articles/2026-02-11-your-first-ai-route-connecting-to-openai-opensource/).
The payoff shows up later: because everything is normalized here, principles
6 (failover), 7 (token accounting), and 8 (policy) get to work on a single,
consistent stream instead of N provider dialects.

---

## 2. MCP tool federation (stdio / HTTP / SSE / OpenAPI)

**Why it matters.** The [Model Context Protocol](https://modelcontextprotocol.io/)
is how agents get hands — GitHub, Slack, a database, an internal API. But
MCP servers multiply fast, and each one is a separate connection, a
separate auth story, and a separate thing to monitor. Worse, MCP is not
plain request/response: it's **stateful JSON‑RPC over long‑lived sessions**,
with server‑initiated SSE events that must route back to the *correct*
client session. A path‑based reverse proxy can't do that correctly.

Federation means the gateway presents **one** MCP endpoint to the agent and
multiplexes it across many backend tool servers — regardless of whether a
given server speaks stdio, streamable HTTP, SSE, or is really an OpenAPI
service wrapped as MCP. The agent sees one tool catalog; the gateway owns
the fan‑out, the session affinity, and the per‑target security.

**How agentgateway does it.** A single MCP listener with multiple targets,
each using whatever transport the server actually speaks:

```yaml
mcp:
  port: 3000
  targets:
    - name: everything
      stdio:
        cmd: docker
        args: ["exec", "-i", "mcp-everything", "node", "dist/index.js"]
    - name: github
      http:
        host: github-mcp.tools.svc.cluster.local
        port: 8080
    - name: internal-api
      openapi:
        schema: /config/openapi/orders.yaml
        host: orders.internal.svc.cluster.local
        port: 80
```

The agent connects once; agentgateway keeps the JSON‑RPC session coherent,
routes SSE events back to the right client, and — critically — lets you
decide *which* tools each caller may even see. That last part is where
federation meets authorization (principle 5). For the deep version of
multiplexing and how tool exposure affects token cost, see
[MCP multiplexing](/articles/2026-02-20-mcp-multiplexing-tool-access-agentgateway/)
and [GitHub MCP token economics](/articles/2026-06-20-github-mcp-token-economics-agentgateway-tool-modes/).

---

## 3. Secure A2A agent discovery & collaboration

**Why it matters.** The next step past "agent calls tools" is "agent calls
agent." A planner delegates to a researcher; the researcher calls a
summarizer. [A2A](https://a2a-protocol.org/) standardizes that handoff. But
without a gateway in the middle, agent‑to‑agent traffic is the wild west:
no shared identity, no way to scope what one agent may ask another to do,
and no audit trail when a delegated call does something expensive or
sensitive. Multi‑agent systems fail *between* the agents, and that seam is
exactly where nobody is looking.

An AI gateway treats A2A as first‑class traffic: agents are discoverable
through the gateway, every cross‑agent call carries identity, and the same
auth, rate‑limit, and observability policies that guard LLM and MCP traffic
also guard the handoffs. The blast radius of a misbehaving agent stays
contained because there's a kill switch and a policy boundary at the seam.

**How agentgateway does it.** A2A is routed and secured like any other
backend — an A2A route carries JWT identity forward, applies RBAC on what
the calling agent is allowed to invoke, and emits the same traces as
everything else. The multi‑agent kill‑switch pattern (revoke one agent's
access at the gateway and it's instantly cut off from peers and tools) is
covered in
[Multi‑agent architecture + kill switch](/articles/2026-02-21-multi-agent-architecture-agentgateway-kill-switch/),
and a full A2A/MCP stack running on kagent is in
[AgentX](/articles/2026-07-11-agentx-spacexai-x-mcp-agentgateway-kagent/).

---

## 4. Built‑in guardrails (regex / moderation / webhooks)

**Why it matters.** This is the principle that keeps security teams up at
night. Between the user and the model — in both directions — you need a
decision point that can *see* the content and act on it: redact a credit
card, block a prompt‑injection attempt, drop a response that leaks an
internal hostname, or send the payload to an external moderation service and
honor its verdict. Bolt this into every app and you get inconsistent
coverage and a dozen places to audit. It belongs in the gateway, inline on
the request and response path.

Guardrails come in layers, and a good gateway supports all three:

- **Regex / pattern** rules for the cheap, deterministic cases (SSNs,
  API‑key shapes, email addresses).
- **Moderation** via a model or classification service for the fuzzy cases
  (toxicity, jailbreaks, category policy).
- **Webhook** callouts to an external decision engine — e.g. **F5 AI
  Guardrails** — for enterprise‑grade scanning, redaction, and audit,
  either inline (block before it reaches the model) or out‑of‑band.

**How agentgateway does it.** Guardrail policies attach to a route and run
on the prompt and/or the completion:

```yaml
routes:
- name: openai
  matches:
  - path:
      pathPrefix: /openai
  policies:
    ai:
      promptGuard:
        request:
          regex:
            rules:
              - pattern: '\b\d{3}-\d{2}-\d{4}\b'   # US SSN
                action: reject
          webhook:
            host: f5-guardrails.security.svc.cluster.local
            port: 8080
        response:
          regex:
            rules:
              - pattern: '(?i)internal[- ]only'
                action: mask
  backends:
  - ai:
      name: openai
      provider:
        openAI: {}
```

The point is that a blocked request returns a clean, inspectable decision —
security sees *why* it was blocked, the app sees a status code, and nothing
leaked. The full inline + out‑of‑band F5 pattern is in
[agentgateway + F5 AI Guardrails architectures](/articles/2026-07-02-agentgateway-f5-ai-guardrails-architectures/)
and the hands‑on UI walkthrough is
[here](/articles/2026-07-03-agentgateway-f5-guardrails-ui-first-steps/).

---

## 5. Multi‑auth security (JWT / OAuth / RBAC / CEL)

**Why it matters.** A single API key is a skeleton key: whoever holds it can
do everything the key can do. That's fine for a demo and catastrophic in
production. Real systems need *who* (authentication), *what are they allowed
to do* (authorization), and the ability to express that at the granularity
of "this team's agents may call these three MCP tools and this model, but
not that one." Coarse keys can't express that. You need identity flowing
through the gateway and policy evaluated per request.

An AI gateway should support:

- **JWT** validation — verify tokens, check issuer/audience, extract claims.
- **OAuth** — front the gateway with an IdP (Okta, Keycloak, Entra) so
  agents authenticate as real principals.
- **RBAC** — map identities/claims to roles, and roles to what they may
  reach.
- **CEL** ([Common Expression Language](https://cel.dev/)) — fine‑grained,
  attribute‑based rules like "allow only if `jwt.groups` contains
  `platform` **and** the requested tool isn't in the destructive set."

**How agentgateway does it.** JWT auth is a policy on the listener or route;
RBAC and CEL express which authenticated principals may reach which backends
or MCP tools:

```yaml
routes:
- name: github-mcp
  matches:
  - path:
      pathPrefix: /mcp
  policies:
    jwtAuth:
      issuer: https://login.example.com/
      audiences: ["agentgateway"]
      jwks:
        url: https://login.example.com/.well-known/jwks.json
    authorization:
      rules:
        # only the platform group may use write-capable tools
        - 'jwt.groups.exists(g, g == "platform") || !request.mcp.tool.startsWith("create_")'
  backends:
  - mcp:
      name: github
```

Identity established at the gateway then travels *with* the request into
MCP and A2A calls (principles 2 and 3), so authorization is consistent end
to end instead of re‑invented per hop. For a full OAuth chain into a cloud
runtime, see
[AWS AgentCore with agentgateway and Okta OAuth](/articles/2026-02-19-why-your-ai-agents-need-a-gateway/).

---

## 6. Rate limiting, budgets & failover routing

**Why it matters.** LLM traffic has a property normal traffic doesn't:
**every request costs money**, and a bad one can cost a lot. An agent stuck
in a reasoning loop doesn't crash — it spends. So the gateway needs two
knobs traditional gateways never had:

- **Budgets** — a hard ceiling in *dollars or tokens* per user, per team,
  per agent. When it's hit, the gateway returns `429`, not a surprise
  invoice. This is FinOps as a policy, not a monthly spreadsheet.
- **Failover routing** — provider A is the primary; on error, timeout, or
  overload, the gateway transparently fails over to provider B (or a
  cheaper/local model) without the app knowing. One outage stops being one
  outage for every agent.

Plus classic **rate limiting** (requests per second per principal) to
protect both your budget and the upstream provider's limits.

**How agentgateway does it.** Budgets attach a cost model and a ceiling; the
gateway meters real token usage against it. Failover is expressed as an
ordered/weighted backend list with health‑aware routing:

```yaml
routes:
- name: chat
  matches:
  - path:
      pathPrefix: /chat
  policies:
    rateLimit:
      local:
        maxTokens: 100
        tokensPerFill: 100
        fillInterval: 1m
    ai:
      budget:
        currency: USD
        limit: 50.00           # $50/day hard cap
        interval: 24h
        onExceeded: reject      # -> 429
  backends:                     # failover: primary first, fallback second
  - ai:
      name: primary
      provider:
        openAI:
          model: gpt-4o
    weight: 100
  - ai:
      name: fallback
      provider:
        anthropic:
          model: claude-sonnet-5
    weight: 0                   # only used when primary is unhealthy
```

The hard‑spend‑limit behavior — model cost catalogs, dollar/token budgets,
and a real `429` on exhaustion — is walked through in
[AI budgets & hard spend limits](/articles/2026-07-02-agentgateway-ai-budgets-hard-spend-limits/),
and the "how much headroom do you actually have" analysis is in
[Headroom: MCP token stacking](/articles/2026-06-22-headroom-agentgateway-mcp-token-stacking/).

---

## 7. Full observability (OpenTelemetry / TLS)

**Why it matters.** You cannot govern what you cannot see. With agents, the
questions are specific and expensive to answer without instrumentation:
*What prompt was sent? What did it cost? Which model, which tool, which
agent? Where did latency come from — the model, the tool call, or the
gateway?* If observability is bolted on per app, you get inconsistent,
non‑comparable data. If it lives in the gateway, every request — LLM, MCP,
A2A — emits the same **OpenTelemetry** traces, metrics, and logs, complete
with token counts and cost, and every hop is encrypted with **TLS**.

This is the principle that makes the other seven *auditable*. Budgets
(principle 6) are only trustworthy because token accounting is real.
Guardrail decisions (principle 4) are only defensible because they're
logged. RBAC (principle 5) is only verifiable because you can see who called
what.

**How agentgateway does it.** Tracing is a gateway‑level policy that exports
OTLP to any collector — Langfuse, Tempo, Jaeger, an OTel Collector fan‑out:

```yaml
config:
  tracing:
    otlp:
      endpoint: http://otel-collector.observability.svc.cluster.local:4317
      protocol: grpc
    # token usage and cost are attached to spans automatically
```

Because the gateway sits on the normalized stream from principle 1, the
spans carry `gen_ai.*` attributes — model, input/output tokens, cost —
consistently across providers. The end‑to‑end Langfuse integrations
(direct OTLP and via an OTel Collector) are in
[agentgateway + Langfuse direct OTLP](/articles/2026-06-10-agentgateway-standalone-langfuse-direct-otlp/)
and [via the OTel Collector](/articles/2026-06-10-agentgateway-langfuse-integration-with-otel-collector/),
and the cost dashboards built on that data are in
[the cost & tokenomics dashboard](/articles/2026-06-24-agentgateway-cost-tokenomics-dashboard/).

---

## 8. YAML policy‑driven config

**Why it matters.** The previous seven principles are only as good as the
place they're defined. If routing, auth, guardrails, and budgets live in
application code and clicked‑together dashboards, then your governance is
un‑reviewable, un‑versioned, and un‑reproducible. Someone changes a limit in
a UI at 2am and there's no diff, no approval, no rollback.

Declarative **YAML** flips that. Every policy — every route, backend,
guardrail, JWT rule, budget, and trace exporter — is text. Text goes in Git.
Git gives you pull‑request review, history, blame, environments, and
one‑command rollback. Your AI governance becomes a GitOps artifact: the same
config runs on a laptop (standalone) and in production (Kubernetes CRDs),
and "what is our policy?" has a single, diffable answer.

**How agentgateway does it.** Everything in this post *was* YAML. That's the
point — there is no hidden imperative layer. Standalone is a single
`config.yaml`; on Kubernetes the same model is expressed as Gateway API and
`agentgateway.dev` CRDs, reconciled by a controller. Both are declarative,
both live in Git. The GitOps pattern for agents is in
[GitOps for agents](/articles/2026-04-02-gitops-for-agents-deployment-and-management/),
and quickstarts for both surfaces are
[standalone](/articles/2026-03-12-agentgateway-quickstart-standalone/) and
[Kubernetes](/articles/2026-03-12-agentgateway-quickstart-kubernetes/).

---

## Why these eight, together

Any one of these principles is useful on its own. The reason they belong in
*one* gateway is that they compound:

- Unified access (1) gives you **one normalized stream** to apply
  everything else to.
- MCP federation (2) and A2A (3) put **tools and agent handoffs** on that
  same stream.
- Guardrails (4) and multi‑auth (5) turn the stream into a **policy
  enforcement point** — content and identity.
- Budgets and failover (6) make it **resilient and financially safe**.
- Observability (7) makes all of it **auditable and debuggable**.
- YAML (8) makes the whole thing **reviewable, versioned, and portable**.

Pull any one out and you reopen a gap: no observability and your budgets are
guesswork; no unified access and your policies fork per provider; no YAML
and none of it is reproducible. That's why "an API gateway with an LLM
route" isn't enough — the AI‑native concerns (tokens, sessions, tools,
agents, cost) have to be first‑class.

## Where to start

You don't have to adopt all eight on day one. A sane path:

1. **Front your LLM calls** through the gateway (principle 1) — kill the
   scattered API keys first.
2. **Turn on observability** (principle 7) — you can't tune what you can't
   see.
3. **Add budgets and rate limits** (principle 6) — cap the downside.
4. **Federate your MCP tools** (principle 2) and put **guardrails +
   auth** (4, 5) on them.
5. **Bring in A2A** (principle 3) as your agents start delegating.
6. **Commit all of it to Git** (principle 8) from the very first step.

agentgateway is open source and CNCF — you can run the whole thing on a
laptop today. When you need the enterprise hardening (the F5 AI Guardrails
integration, the Solo Enterprise UI, cost management, supported CRDs), Solo
packages it as **Enterprise agentgateway**.

- Project: <https://github.com/agentgateway/agentgateway>
- Docs: <https://agentgateway.dev/docs/>
- Solo.io: <https://www.solo.io/>

The gateway era of microservices taught us that governance can't be
per‑service and after‑the‑fact. Agents raise the stakes — the blast radius
now includes your data, your budget, and your users. These eight principles
are how you keep that in bounds.
