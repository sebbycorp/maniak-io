---
title: "Getting Started with agentgateway Series 01: Deploying and Configuring Your First LLM Request"
date: 2026-04-02
description: "Go from zero to a working LLM gateway in ~5 minutes. Spin up a Kind cluster, install agentgateway, configure OpenAI, and send your first chat completion through the gateway — all running locally on Kubernetes."
tags: ["agentgateway", "kubernetes", "llm", "openai", "gateway", "devops"]
categories: ["AI & Agents"]
youtubeId: "vhoIDikmG_w"
---

{{< youtube vhoIDikmG_w >}}

## Overview

Go from zero to a working LLM gateway in about five minutes. In this first video of the agentgateway series, we spin up a Kind cluster, install agentgateway, configure OpenAI as our first provider, and send a chat completion through the gateway — all running locally on Kubernetes.

## What We Cover

- Installing a Kind cluster for local Kubernetes
- Deploying Kubernetes Gateway API CRDs + agentgateway CRDs
- Installing the agentgateway controller (v1.0) via Helm
- Creating a Gateway proxy to handle traffic
- Configuring OpenAI as an LLM backend with secure secret storage
- Setting up an HTTPRoute to map requests to the backend
- Sending your first request — the model is auto-filled by the backend, so clients don't need to know which model they're hitting

## Key Takeaway

One of the nicest patterns for platform teams: the backend already has the model configured, so agentgateway fills it in automatically. Your clients don't even need to know which model they're hitting.

## What's Next

This is just the beginning. In the next videos we'll set up more providers (Mistral, Anthropic, self-hosted models), then get into failover, rate limiting, and cost tracking.

## Links

- [agentgateway docs](https://agentgateway.dev)
- [agentgateway GitHub](https://github.com/agentgateway/agentgateway)
- [Kind (Kubernetes in Docker)](https://kind.sigs.k8s.io)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io)
- [Helm](https://helm.sh)
- [OpenAI API](https://platform.openai.com)
- [Companion blog post: agentgateway Quickstart on Kubernetes]({{< relref "articles/2026-03-12-agentgateway-quickstart-kubernetes" >}})
