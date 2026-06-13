# Deploying Agent Gateway + Everything MCP Server on Proxmox LXC

This guide walks through deploying **Agent Gateway** (v1.3.0) with the official **Everything MCP server** inside a Proxmox LXC container.

## Prerequisites

- Proxmox VE host
- Access to the `172.16.10.x` network
- Docker Hub access (or equivalent)

## Step 1: Create LXC Container

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

## Step 2: Install Docker inside the LXC

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
  modelcontextprotocol/servers:2025.8.18 everything
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
        apiKey: "YOUR_OPENAI_API_KEY"
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
pct exec 210 -- chmod 777 /config/data

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

## Step 6: Access the Services

After deployment, access the services at:

- **Admin UI**: `http://172.16.10.164:15000/ui`
- **LLM Proxy**: `http://172.16.10.164:4000`
- **MCP Server**: `http://172.16.10.164:3000`

## Key Configuration Notes

- Database must be placed under `config.database`
- MCP targets use `stdio` transport with `docker exec`
- Admin port must be bound to `0.0.0.0` using the `ADMIN_ADDR` environment variable
- Request logging requires a writable SQLite database with correct ownership

## Verification

Check that Logs and Analytics work in the UI without database errors, and that the Everything MCP server appears as a connected target.

---

*Deployed on Proxmox LXC 210 (172.16.10.164) - June 2026*
