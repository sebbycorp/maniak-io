---
title: "Running agentgateway on Proxmox (LXC) guide"
date: 2026-06-18
draft: false
tags: ["agentgateway", "mcp", "proxmox", "talos", "kubernetes", "llm"]
---

# Running agentgateway on Proxmox (LXC) guide

**Date:** June 2026  
**Author:** Sebastian Maniak  
**Tags:** agentgateway, mcp, proxmox, talos, kubernetes, llm

## Overview

This guide walks through deploying **agentgateway** (v1.3.0) inside a Proxmox LXC container with the official "Everything" MCP server connected behind it. The setup includes request logging, cost tracking, and a working UI.

## Prerequisites

- Proxmox VE 8.x
- Access to a bridge (`vmbr0`) with DHCP on the `172.16.10.x` network
- Docker Hub access or local registry

## Step 1: Create the LXC Container

```bash
# Download Alpine template
pveam download local alpine-3.20-default_20240908_amd64.tar.xz

# Create container (CTID 210)
pct create 210 /var/lib/vz/template/cache/alpine-3.20-default_20240908_amd64.tar.xz \
  --hostname agentgateway \
  --cores 2 \
  --memory 2048 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --rootfs local-lvm:8 \
  --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --onboot 1

pct start 210
```

You should now see the container in the Proxmox UI:

![Proxmox LXC Container 210 (agentgateway)](/images/agentgateway-lxc-proxmox.png)

## Step 2: Install Docker Inside the LXC

```bash
pct exec 210 -- apk update
pct exec 210 -- apk add docker docker-compose
pct exec 210 -- rc-update add docker boot
pct exec 210 -- service docker start
```

## Step 3: Deploy the Everything MCP Server

```bash
pct exec 210 -- docker run -d \
  --name mcp-everything \
  --restart unless-stopped \
  modelcontextprotocol/servers:latest everything
```

## Step 4: Create Agent Gateway Configuration

Create `/config/config.yaml` inside the LXC:

```yaml
config:
  database:
    url: sqlite:///config/data/data.db

llm:
  port: 4000
  models:
    - name: openai/*
      provider: openai
      params:
        model: gpt-4.1-mini
        apiKey: "sk-..."
  policies:
    cors:
      allowOrigins:
        - "http://172.16.10.164:15000"
      allowHeaders:
        - "*"
      allowMethods:
        - GET
        - POST
  providers: []
  virtualModels: []

mcp:
  port: 3000
  targets:
    - name: everything
      stdio:
        cmd: docker
        args:
          - "exec"
          - "-i"
          - "mcp-everything"
          - "node"
          - "dist/index.js"
  policies:
    cors:
      allowOrigins:
        - "http://172.16.10.164:15000"
      allowHeaders:
        - "*"
      allowMethods:
        - GET
        - POST
      exposeHeaders:
        - Mcp-Session-Id

frontendPolicies:
  http:
    maxBufferSize: 33554432
```

## Step 5: Run Agent Gateway

```bash
pct exec 210 -- mkdir -p /config/data
pct exec 210 -- docker run -d \
  --name agentgateway \
  --restart unless-stopped \
  -v /config:/config \
  -p 4000:4000 \
  -p 3000:3000 \
  -p 15000:15000 \
  -e ADMIN_ADDR=0.0.0.0:15000 \
  cr.agentgateway.dev/agentgateway:v1.3.0 \
  -f /config/config.yaml
```

## Step 6: Verify Everything Works

Access the UI:

```
http://172.16.10.164:15000/ui
```

You should see:

- LLM proxy on port 4000
- MCP server (Everything) on port 3000
- Admin UI on port 15000
- Logs and Analytics working (no database errors)

## Final Notes

- The container IP is `172.16.10.164` (DHCP)
- All important ports are exposed on `0.0.0.0`
- The Everything MCP server is connected via Docker exec stdio

This setup gives you a production-ready Agent Gateway with full MCP support behind it on Proxmox.
Here's what the working UI looks like:

![Agent Gateway UI - Everything Working](/images/agentgateway-ui-working.png)
