# DeepSeek on VS Code — Linux Setup Guide

Complete guide to integrating DeepSeek models with Visual Studio Code on **Fedora** and **Debian/Ubuntu/Zorin OS**, either via the cloud API or fully offline via Ollama.

---

## Quick Start

To set everything up automatically, run the included setup script:

```bash
bash setup.sh
```

The script detects your distro, GPU, and RAM; suggests the best model; installs Ollama; downloads the chosen model; and generates the Continue.dev configuration automatically. Follow the sections below for manual setup or to understand each step in detail.

---

## Table of Contents

- [Overview](#overview)
- [Cloud vs. Local Comparison](#cloud-vs-local-comparison)
- [Recommended Extensions](#recommended-extensions)
- [Local Installation with Ollama](#local-installation-with-ollama)
- [Extension Configuration](#extension-configuration)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

DeepSeek offers two primary models:

- **DeepSeek-R1** — advanced reasoning model, ideal for complex logic and coding tasks
- **DeepSeek-V3** — high-throughput Mixture-of-Experts model, excellent for code generation and general chat

Both can be used via the cloud API or run locally in fully offline mode.

---

## Cloud vs. Local Comparison

| Feature | Cloud API | Local via Ollama |
| :--- | :--- | :--- |
| Compute overhead | None (remote servers) | High (local GPU/CPU/RAM) |
| Data privacy | Subject to Terms of Service | 100% air-gapped / private |
| Available models | Full V3 (671B) and R1 (671B) | Quantized versions (1.5B to 70B) |
| Cost | Pay-per-token (very affordable) | Free (infrastructure power only) |
| Internet requirement | Continuous connection | Initial download only |

---

## Recommended Extensions

### Continue.dev

The leading open-source extension for LLM-assisted coding. Supports inline autocomplete (Tab), chat with codebase context (`@codebase`), and contextual refactoring.

**Installation:** search for `Continue` in the VS Code marketplace or visit [continue.dev](https://continue.dev).

### Cline / Roo Code

An autonomous agent that goes beyond chat: reads and writes files directly in your workspace, executes terminal commands, and iterates on compilation/lint errors automatically.

- **Cline** — original version
- **Roo Code** — actively maintained fork with additional features

Best suited for complex multi-file refactoring, test generation, and project scaffolding.

### Twinny

A fully local, open-source alternative to Continue that is lighter to configure and works well with Ollama out of the box. Good choice if Continue's indexing or context handling feels unreliable on lower-end hardware.

### Llama Coder

Focused exclusively on autocomplete. If tab completion is the primary feature you want and you find Continue's autocomplete laggy, Llama Coder is worth trying — it has less overhead and tends to produce faster inline suggestions.

### OpenAI-Compatible Extensions

DeepSeek's API is 100% compatible with the OpenAI `v1/chat/completions` format. Any extension that accepts a custom base URL works as a drop-in replacement, such as *Genie AI* and similar tools.

---

## Local Installation with Ollama

### 1. Install Ollama

#### Fedora (Workstation and Atomic variants)

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

> On Atomic systems (Silverblue, Kinoite), prefer running inside a container or via a user-managed systemd binary.

**NVIDIA GPU acceleration on Fedora** — enable RPM Fusion and install CUDA:

```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda -y
```

#### Debian / Ubuntu / Zorin OS

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Verify the service is running:

```bash
sudo systemctl status ollama
```

---

### 2. Choose and download a model

Select a size based on your available hardware:

| Model | Disk space | Recommended hardware |
| :--- | :--- | :--- |
| `deepseek-r1:1.5b` | ~1.1 GB | Laptops and light hardware |
| `deepseek-r1:7b` | ~4.7 GB | 16 GB RAM / 8 GB VRAM (recommended) |
| `deepseek-r1:14b` | ~9.0 GB | Mid-to-high tier GPUs |
| `deepseek-r1:32b` / `70b` | 20 GB+ | Enterprise setups with large VRAM |

Pull your chosen model:

```bash
ollama pull deepseek-r1:7b
```

Test it in the terminal:

```bash
ollama run deepseek-r1:7b
```

---

## Extension Configuration

### Continue.dev

`setup.sh` automatically generates `~/.continue/config.yaml` configured for the local Ollama stack. For the complete configuration reference — including the Continue 2.0 YAML format, model roles, troubleshooting, and cloud API setup — see [docs/continue-dev.md](docs/continue-dev.md).

**Quick summary of what gets configured:**

| Role | Model |
| :--- | :--- |
| Chat / Edit | `llama3.1:8b`, `qwen2.5-coder:7b` |
| Autocomplete | `qwen2.5-coder:1.5b` |
| Embeddings (`@codebase`) | `nomic-embed-text:latest` |

> `deepseek-r1` is not used for Continue — it outputs raw `<think>` reasoning tags that the extension does not render. Use it via Cline or directly in the terminal.

---

### Cline / Roo Code

1. Open the **Cline** panel in VS Code
2. Click the gear icon (Settings)
3. Under **Provider**, select based on your setup:

**Local via Ollama:**
- Base URL: `http://localhost:11434`
- Model: `deepseek-r1:7b` (or whichever size you downloaded)

**Cloud API:**
- Provider: `DeepSeek`
- API Key: your key from the DeepSeek portal
- Model: `deepseek-chat` (V3) or `deepseek-reasoner` (R1)

---

## Troubleshooting

### Very slow token generation

**Cause:** Ollama is falling back to CPU because it cannot detect the GPU.

**Fix:** Check whether CUDA/ROCm drivers are correctly installed:

```bash
sudo journalctl -u ollama --no-pager | grep -iE "(cuda|rocm|gpu)"
```

Make sure your user belongs to the `video` and `render` groups:

```bash
sudo usermod -aG video,render $USER
```

---

### Port conflict or remote access (devcontainers/VMs)

By default, Ollama listens only on `127.0.0.1:11434`. To expose it on the network:

1. Edit the systemd service:

```bash
sudo systemctl edit ollama
```

2. Add the environment variable:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```

3. Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## References

- [Ollama Documentation](https://ollama.com)
- [Continue.dev](https://continue.dev)
- [DeepSeek Developer Portal](https://platform.deepseek.com/)
- [Cline Repository](https://github.com/cline/cline)
- [Roo Code Repository](https://github.com/RooVetGit/Roo-Code)
