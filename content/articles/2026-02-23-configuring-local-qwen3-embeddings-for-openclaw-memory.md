---
title: "Configuring Local Qwen3 Embeddings for OpenClaw Memory"
date: 2026-02-23T15:19:00-05:00
draft: false
categories:
  - OpenClaw
  - AI
  - Embeddings
tags:
  - OpenClaw
  - Memory
  - Embeddings
  - Qwen
  - LocalAI
---

# Configuring Local Qwen3 Embeddings for OpenClaw's Memory System

OpenClaw's `memory_search` and `memory_get` tools enable semantic recall from `MEMORY.md`, `memory/*.md`, and session transcripts **before** answering about prior work/decisions. Defaults use cloud embeddings, but I've switched to a **local Qwen3-Embedding-0.6B** (GGUF quantized) for privacy, speed, and zero cost.

## Why Qwen3-Embedding-0.6B?
- **Sweet Spot**: 0.6B params—20-100ms/chunk on CPU (10x faster than 7B).
- **Quality**: Tops MTEB benchmarks for retrieval, beats E5-small.
- **GGUF**: Q8_0 (~400MB, near-lossless) via llama.cpp.
- **Hybrid Mode**: CPU + auto-GPU (CUDA/Metal/ROCm).

## Model Specs
- **Repo**: [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF)
- **File**: `Qwen3-Embedding-0.6B-Q8_0.gguf`
- **Dims**: 1024 (semantic search optimized)
- **Provider**: `local` (llama.cpp backend)

## Setup (5 Mins)
1. **Download**:
   ```
   mkdir -p ~/.openclaw/models/embeddings
   cd ~/.openclaw/models/embeddings
   huggingface-cli download Qwen/Qwen3-Embedding-0.6B-GGUF Qwen3-Embedding-0.6B-Q8_0.gguf
   ```

2. **Config** (`~/.openclaw/config.yaml` or CLI):
   ```yaml
   agents:
     defaults:
       embeddingModel: "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf?provider=local&hybrid=true&cpu_threads=8"
   ```
   Params:
   | Key | Desc |
   |-----|------|
   | `provider=local` | llama.cpp |
   | `hybrid=true` | GPU auto |
   | `cpu_threads=8` | Cores |

   CLI: `openclaw configure --section agents.defaults.embeddingModel '...'` 

3. **Restart**: `openclaw gateway restart`

4. **Test**:
   ```
   memory_search query="test prior decision"  # ~80ms top-5
   ```

## Benchmarks (i7-12700K, 32GB, No GPU)
| Task | Time | RAM |
|------|------|-----|
| Embed 512t chunk | 45ms | 350MB |
| Search 100 docs | 80ms | <500MB |
| 100 queries/min | ✅ |     |

GPU (RTX 3060): 15ms/embed.

## How It Works
1. **Chunk**: Files → 512t snippets (w/ lines).
2. **Embed Query**: Qwen3 → vector.
3. **SimSearch**: Cosine top-k (minScore filter).
4. **Cite**: `path#line` for `memory_get`.

On-demand (snippet cache).

## Tweaks & Troubleshooting
- **Faster**: Q4_K_M.gguf.
- **GPU?**: `gpu=true`.
- **OOM**: `context_length=2048`.
- **Logs**: `journalctl -u openclaw-gateway | grep embedding`.
- **Verify**: `session_status` → embedding provider.

## Alternatives
| Model | Params | Speed | Use Case |
|-------|--------|-------|----------|
| Qwen3-0.6B-Q8 | 0.6B | 45ms | General |
| NV-Embed-4B-Q5 | 4B | 150ms | Code |
| all-minilm-L6 | 22M | 10ms | Light |

## Pro Tips
- **Pre-cache**: JSONL embeddings via cron.
- **Scale**: memory/ subdirs.
- **Monitor**: Query hit rates.

Local RAG + Claude = unbeatable. Questions?

[Docs](https://docs.openclaw.ai/tools/memory) | [Qwen](https://huggingface.co/Qwen)