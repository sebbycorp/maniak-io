---
title: "Hard Spend Limits for LLM Traffic: AI Budgets in Enterprise AgentGateway v2026.6.3"
date: 2026-07-02
description: "A day-one, hands-on look at the new EnterpriseAgentgatewayBudget CRD — dollar- and token-denominated budgets with Audit/Block enforcement, a model cost catalog, and a live 429 when the money runs out. Built and verified on a bare-metal Talos lab."
---

Enterprise AgentGateway v2026.6.3 shipped on July 1st with a changelog line that
FinOps-minded platform teams have been waiting for: **Enterprise Budgets and
Dimensions**. Until now, "budgeting" LLM traffic through a gateway meant
approximating it with token-based rate limiting — workable, but request-window
based, tokens-only, and fiddly to reason about. The new release replaces that
with a first-class Kubernetes resource: `EnterpriseAgentgatewayBudget`, a
declarative spending limit in **US dollars or tokens**, accumulated over a
**calendar window** (day, week, month, year), with a choice of **audit** or
**block** when the budget runs dry.

This post is a day-one field report. The docs for the feature are still
catching up with the release (only the API reference covers it as I write
this), so everything below was derived from the live CRD schemas on my cluster
and verified with real traffic — including tripping a budget on purpose and
watching the gateway return `429` with the daily window in the reset header.

## Why budgets, not rate limits

Rate limits answer "how fast?" Budgets answer "how much, in dollars, this
month?" — which is the question your finance team actually asks. The
difference shows up in three places:

* **Unit.** A budget is denominated in `USD` or `Tokens`. USD budgets use a
  *model cost catalog* (per-model input/output rates) so the gateway computes
  the realized cost of every request as it happens.
* **Window.** Budgets accumulate over fixed calendar windows — `Day`, `Week`,
  `Month`, `Year` — not sliding rate-limit intervals.
* **Action.** `onBudgetExceeded: Audit` logs and lets traffic through (perfect
  for rollout); `Block` returns `429` until the window resets. You can run
  both at once: a generous audited dollar budget for visibility, plus a hard
  token stop as a circuit breaker.

## The moving parts

Three resources cooperate, all in the `enterpriseagentgateway.solo.io/v1alpha1`
API group:

1. **`EnterpriseAgentgatewayBudget`** — the budget definitions themselves. Each
   entry has a `name`, a `limit` (`unit` + `amount`), a `window`, an
   `onBudgetExceeded` action, and an optional `subject` — up to **16 key/value
   dimensions** that scope the entry to matching requests (per user, team, API
   key, model… `"*"` matches any non-missing value; omit `subject` and the
   budget applies to every request on the enforced target).
2. **`EnterpriseAgentgatewayPolicy`** with `traffic.entBudgetEnforcement` —
   switches enforcement on for the gateways or routes in `targetRefs`, and
   controls *discovery*: which namespaces the controller scans for Budget
   resources (`Same`, `Selector`, or `All` — handy for letting each team keep
   its own Budget objects in its own namespace).
3. **`EnterpriseAgentgatewayParameters`** with `modelCatalog` — loads per-model
   pricing from a ConfigMap so USD budgets (and per-request cost telemetry)
   have something to compute with.

## The lab

My setup is a bare-metal Talos Kubernetes cluster running Solo Enterprise
AgentGateway v2026.6.3, fully GitOps-managed by ArgoCD — every manifest below
lives in a repo and lands via auto-sync. The main gateway (`agentgateway-proxy`)
already fronts OpenAI at `/openai`.

One design note worth stealing: my `/openai` route is also the default model
path for kagent agents in the same cluster. A blocking budget that trips would
cut those agents off for the rest of the day. So the demo gets a **dedicated
route** — same backend, different path — and the budget policy targets only
that route. Blast radius: zero.

## Step 1 — the model cost catalog

Per-model USD rates, per **1M tokens**, as a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: model-cost-catalog
  namespace: agentgateway-system
data:
  catalog.json: |
    {
      "providers": {
        "openai": {
          "models": {
            "gpt-4o": {
              "rates": { "input": "2.50", "output": "10.00" }
            },
            "gpt-4o-mini": {
              "rates": { "input": "0.15", "output": "0.60" }
            }
          }
        }
      }
    }
```

Treat pricing as versioned configuration — when a provider changes rates, you
change a file in Git and your cost telemetry follows.

## Step 2 — load the catalog into the proxy

The catalog attaches to a gateway through `EnterpriseAgentgatewayParameters`:

```yaml
apiVersion: enterpriseagentgateway.solo.io/v1alpha1
kind: EnterpriseAgentgatewayParameters
metadata:
  name: agentgateway-proxy-params
  namespace: agentgateway-system
spec:
  modelCatalog:
    sources:
      - configMap:
          name: model-cost-catalog
          key: catalog.json
```

…and the Gateway references it via `infrastructure.parametersRef`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-proxy
  namespace: agentgateway-system
spec:
  gatewayClassName: enterprise-agentgateway
  infrastructure:
    parametersRef:
      group: enterpriseagentgateway.solo.io
      kind: EnterpriseAgentgatewayParameters
      name: agentgateway-proxy-params
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

Heads-up: attaching parameters rolls the proxy Deployment (a new pod came up in
seconds in my lab). On startup the proxy confirms the catalog load:

```
info  llm::cost  watching model catalog files  count=2
info  llm::cost  loaded model catalog  providers=3 models=80
```

Note `providers=3 models=80` — your catalog merges with a built-in one, so you
only need to define models where you want to pin your own rates.

## Step 3 — an isolated demo route

Same OpenAI backend, dedicated path:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: budget-demo
  namespace: agentgateway-system
spec:
  parentRefs:
    - name: agentgateway-proxy
      namespace: agentgateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /budget-demo
      backendRefs:
        - name: openai
          namespace: agentgateway-system
          group: agentgateway.dev
          kind: AgentgatewayBackend
```

## Step 4 — the budgets and their enforcement

Two entries: a $5/day audited dollar budget (visibility) and a deliberately
tiny 2,000-token/day blocking budget (the circuit breaker we're going to trip):

```yaml
apiVersion: enterpriseagentgateway.solo.io/v1alpha1
kind: EnterpriseAgentgatewayBudget
metadata:
  name: budget-demo
  namespace: agentgateway-system
spec:
  budgets:
    - name: demo-usd-audit
      limit:
        unit: USD
        amount: 5
      window:
        unit: Day
      onBudgetExceeded: Audit
    - name: demo-token-block
      limit:
        unit: Tokens
        amount: 2000
      window:
        unit: Day
      onBudgetExceeded: Block
---
apiVersion: enterpriseagentgateway.solo.io/v1alpha1
kind: EnterpriseAgentgatewayPolicy
metadata:
  name: budget-demo-enforcement
  namespace: agentgateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: budget-demo
  traffic:
    entBudgetEnforcement:
      discovery:
        namespaces:
          from: Same
```

Push, let ArgoCD sync, and check the policy attached:

```
$ kubectl -n agentgateway-system get enterpriseagentgatewaypolicy budget-demo-enforcement
NAME                      ACCEPTED   ATTACHED   AGE
budget-demo-enforcement   True       True       29s
```

## Tripping it

First request — normal:

```
$ curl -s http://<node-ip>:30160/budget-demo/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"In one sentence, what is a token budget?"}],"max_tokens":60}'

HTTP/1.1 200 OK
...
"usage":{"prompt_tokens":17,"completion_tokens":39,"total_tokens":56}
```

Then a few large completions (`max_tokens: 800`, a 500-word essay each) to burn
the 2,000-token daily budget:

```
request 1: HTTP/1.1 200 OK  "total_tokens":704
request 2: HTTP/1.1 200 OK  "total_tokens":711
request 3: HTTP/1.1 200 OK  "total_tokens":669
request 4: HTTP/1.1 429 Too Many Requests
```

56 + 704 + 711 + 669 = 2,140 tokens — over budget. Request 4 never reaches
OpenAI. The `429` response is admission-level and self-describing:

```
HTTP/1.1 429 Too Many Requests
x-ratelimit-limit: 2000
x-ratelimit-remaining: 0
x-ratelimit-reset: 86400

rate limit exceeded
```

`x-ratelimit-reset: 86400` — the fixed daily window. Clients get exactly what
they need to back off intelligently.

Meanwhile the production `/openai` route (which kagent's agents use) kept
returning `200` throughout — the budget is scoped to the demo route and
nothing else.

## What you get in the logs

This is my favorite part. With the catalog loaded, **every LLM request logs
its realized dollar cost** alongside the usual token telemetry:

```
info  request route=agentgateway-system/budget-demo ... http.status=200
      gen_ai.request.model=gpt-4o gen_ai.response.model=gpt-4o-2024-08-06
      gen_ai.usage.input_tokens=21 gen_ai.usage.output_tokens=683
      agw.ai.usage.cost.total=0.0068825
```

That's $0.0069 for a 704-token gpt-4o call, computed from the catalog at
request time — the same number your USD budgets accrue against, and it flows
into traces and metrics for your observability stack.

And when the blocking budget trips, the gateway says so in plain terms:

```
warn  budget  budget exceeded; blocking...
      budget_id=agentgateway-system/budget-demo/demo-token-block
      budget_action="BLOCK" budget_unit="TOKENS" budget_limit=2000
      budget_window="DAILY" phase="admission" outcome="over_limit_block"
```

Everything you'd want in an alert: which budget, which action, which window,
and the outcome. An `Audit` entry produces the same telemetry with a
non-blocking outcome — which is exactly how you should roll budgets out:
audit first, watch the logs for a week, then flip to `Block`.

## Dimensions: scoping budgets to teams and users

The demo entries above are unscoped — they apply to every request on the
enforced route. The `subject` field is where multi-tenancy comes in:

```yaml
    - name: dev-team-daily
      subject:
        teamId: dev          # up to 16 key/value dimensions per entry
      limit:
        unit: USD
        amount: 50
      window:
        unit: Day
      onBudgetExceeded: Block
```

A subject scopes the entry to requests whose resolved dimension values match
every key/value pair (a value of `"*"` means "any non-missing value"). Combined
with the discovery modes on the enforcement policy (`Same` / `Selector` /
`All`), the intended shape is clear: platform team owns the enforcement policy
on the gateway; each product team owns Budget resources in their own
namespace, scoped to their own dimensions. Org → team → user hierarchies with
different windows and actions per level.

One honest caveat for day one: how dimension values are *resolved* at request
time (trusted identity headers derived from JWT claims, per Solo's cost-controls
reference architecture) isn't fully documented yet outside the API reference.
For unscoped budgets like this demo, none of that matters — they just work.

## Gotchas from the field

* **The API group is `enterpriseagentgateway.solo.io/v1alpha1`.** The docs'
  model-catalog example shows `agentgateway.dev/v1alpha1` for the Parameters
  kind; the CRDs actually installed by the v2026.6.3 charts use the
  enterprise group. When in doubt, `kubectl get crd | grep -i budget` and read
  the schema — it also encodes useful validation (budget names must be
  alphanumeric-with-hyphens; subject keys/values can't contain `|`, `^`, or
  backticks; token budgets cap at 2^32−1).
* **Attaching `parametersRef` restarts the proxy.** Plan for a rollout, not a
  hot reload.
* **Budgets count input + output tokens.** Size token budgets against
  `total_tokens`, not your prompt sizes.
* **A tripped daily `Block` budget stays tripped until the window resets.**
  That's the point — but it's also why you should never put a small blocking
  budget on a route that shared infrastructure (agents, CI) depends on.
  Dedicated routes or subject-scoped entries are your friends.
* **v2026.6.x is not a long-term-support train.** AgentGateway moved to calver
  with this cycle; quarterly releases (first expected: 2026.7.x) get 12 months
  of patches. Fine for a lab, plan accordingly for production.

## Wrapping up

Budget enforcement at the gateway is the missing primitive for AI platform
FinOps: the place that already sees every request, every token, and (with a
cost catalog) every dollar is now the place that can say *no* — declaratively,
per team, per window, in the currency your CFO speaks. The rollout path is
gentle: load a catalog, watch `agw.ai.usage.cost.total` show up in your logs,
add `Audit` budgets, and only then arm `Block` where runaway spend would
actually hurt.

Total cost of this entire demo, per the gateway's own accounting: about two
cents.
