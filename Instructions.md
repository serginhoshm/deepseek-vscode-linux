# DeepSeek Integration Guide for Visual Studio Code (Linux Environments)

An advanced, comprehensive technical manual for deploying DeepSeek models—both via the cloud-based Official API and 100% locally/offline—within Visual Studio Code on **Fedora (Workstation/Atomic)** and **Debian-based (Debian/Ubuntu/Zorin OS)** systems.

---

## 1. Executive Overview & Architecture
DeepSeek has emerged as a highly competitive, open-research AI architecture, offering state-of-the-art reasoning models (**DeepSeek-R1**) and high-throughput Mixture-of-Experts models (**DeepSeek-V3**). 

For developers utilizing Visual Studio Code on Linux, DeepSeek offers two principal execution models:
1. **Cloud-Hosted API (Commercial/Hybrid):** Low latency, zero local compute overhead, consumption-priced via token metrics, fully OpenAI-compatible.
2. **Local Deployment (Private/Offline):** Zero token costs, absolute data privacy, executed via **Ollama** using quantized GGML/GGUF weights.

### Architecture Comparison
| Feature | Cloud API Deployment | Local Deployment (via Ollama) |
| :--- | :--- | :--- |
| **Compute Overhead** | None (Remote Servers) | High (Local GPU/CPU/RAM) |
| **Data Privacy** | Subject to API Terms of Service | 100% Air-Gapped / Private |
| **Model Options** | Full V3 (671B) & Full R1 (671B) | Quantized Distilled R1 (1.5B to 70B) |
| **Cost** | Pay-per-token (Highly cost-effective) | Free (Infrastructure power cost only) |
| **Internet Dependency**| Continuous Connection Required | Initial Download Only |

---

## 2. Advanced Extension Ecosystem for VS Code

To bridge DeepSeek with your IDE workspace, three primary extension frameworks are widely adopted by the Linux development community:

### A. Continue.dev (The Leading Open-Source Framework)
`Continue` is a premier open-source autonomous coding assistant designed to fully customize your LLM development loop. It manages structural code context and hooks natively into local or remote language model orchestrators.
* **Core Capabilities:** Real-time inline code autocomplete (Tab-fill), persistent sidebar chat with codebase indexing (`@codebase`), and contextual file refactoring.
* **Context Awareness:** Automatically parses Git diffs, terminal outputs, and open editor tabs.

### B. Cline / Roo Code (The Agentic Execution System)
`Cline` (and its highly maintained fork `Roo Code`) represents a paradigm shift from chat assistants to **Autonomous AI Agents**. 
* **Core Capabilities:** Operates with a specific loop: read/write files directly in your workspace, inspect terminal output, execute shell commands, and iteratively fix compilation/linting errors.
* **Best Used For:** Complex refactoring across multiple files, automated test generation, and guided scaffolding of fresh repositories.

### C. Standard OpenAI-Compatible Extensions
Because DeepSeek's API adheres strictly to the `v1/chat/completions` specification established by OpenAI, it can be dropped as a transparent replacement into any extension that supports custom base URLs (e.g., *FauxPilot*, *Llama Coder*, or *Genie AI*).

---

## 3. Comprehensive Local Installation & Infrastructure Setup

This section details how to bootstrap a fully local instance of DeepSeek-R1 using Ollama on Linux.

### Step 1: Install Ollama on Linux

#### Option A: Fedora (Workstation & Silverblue/Atomic variants)
For standard Fedora Workstation, use the official optimized binary script. If you are on an atomic system like Silverblue or Kinoite, running it inside a container or using a systemd-managed user binary is recommended.

```bash
# Download and execute the automated installer script
curl -fsSL https://ollama.com/install.sh | sh
```

*Hardware Acceleration Note (Nvidia GPUs on Fedora):* Ensure you have the RPM Fusion repositories enabled and the CUDA toolkit installed so Ollama can offload layers to your VRAM:
```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda -y
```

#### Option B: Debian / Ubuntu / Zorin OS
Execute the standard installation script which automatically sets up a dedicated `ollama` user and registers a `systemd` service:
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Verify that the systemd service is alive and executing properly:
```bash
sudo systemctl status ollama
```

### Step 2: Select and Pull the Target DeepSeek Model
DeepSeek-R1 is available in multiple distilled sizes. Choose a parameter scale that fits your local system's VRAM/RAM capacity:

* **1.5B Model** (`deepseek-r1:1.5b`): ~1.1GB space. Runs efficiently on lightweight hardware/laptops.
* **7B Model** (`deepseek-r1:7b`): ~4.7GB space. Ideal balance for modern workstations (minimum 16GB RAM / 8GB VRAM).
* **14B Model** (`deepseek-r1:14b`): ~9.0GB space. Excellent logic comprehension, requires mid-to-high tier GPUs.
* **32B / 70B Models**: Aimed at enterprise-grade setups with massive VRAM allowances.

To pull your chosen model (e.g., the highly optimized 7B model), execute:
```bash
ollama pull deepseek-r1:7b
```
To verify it works locally in the terminal:
```bash
ollama run deepseek-r1:7b
```

---

## 4. IDE Configuration Guide

Once your back-end runtime (Ollama local or DeepSeek Cloud API) is ready, configure your VS Code plugins as outlined below.

### Config 1: Setting up `Continue`

Open your `config.json` file inside `Continue` (click the gear icon in the bottom-right corner of the Continue sidebar panel).

#### For Local DeepSeek-R1 (via Ollama):
Replace or append the following object into your `models` array:

```json
{
  "models": [
    {
      "title": "DeepSeek-R1 (Local)",
      "provider": "ollama",
      "model": "deepseek-r1:7b"
    }
  ],
  "tabAutocompleteModel": {
    "title": "DeepSeek-R1 1.5B Autocomplete",
    "provider": "ollama",
    "model": "deepseek-r1:1.5b"
  }
}
```

#### For Official DeepSeek Cloud API:
Obtain a valid API token from the [DeepSeek Developer Portal](https://platform.deepseek.com/). Update your `config.json` to leverage their infrastructure:

```json
{
  "models": [
    {
      "title": "DeepSeek-V3 (Cloud)",
      "provider": "deepseek",
      "model": "deepseek-chat",
      "apiKey": "your-deepseek-api-key-here"
    },
    {
      "title": "DeepSeek-R1 (Cloud Reasoning)",
      "provider": "deepseek",
      "model": "deepseek-reasoner",
      "apiKey": "your-deepseek-api-key-here"
    }
  ]
}
```

---

### Config 2: Setting up `Cline` / `Roo Code`

1. Open the **Cline** panel in VS Code.
2. Click the **Settings Icon** (Gear) at the top.
3. Under **Provider**, select one of the following based on your architecture:
   * **Ollama:** Set the Base URL to `http://localhost:11434` and select `deepseek-r1:7b` from the model dropdown list. This grants the agent full command execution liberties completely offline.
   * **DeepSeek:** Input your official secret token Key and select `deepseek-chat` (V3) or `deepseek-reasoner` (R1) to execute complex engineering agents using high-throughput cloud endpoints.

---

## 5. Troubleshooting & Optimization for Linux Workstations

### Issue: Extremely slow token-per-second generation on local setups
* **Root Cause:** Ollama is failing back to CPU execution because it cannot discover your graphics accelerator.
* **Remedy:** Ensure your user belongs to the video/render groups on legacy architectures, or verify CUDA/ROCm drivers. Check driver recognition logs:
    ```bash
    sudo journalctl -u ollama --no-pager | grep -iE "(cuda|rocm|gpu)"
    ```

### Issue: Port Collisions or Remote Access Requirements
By default, Ollama binds strictly to `127.0.0.1:11434`. If you are developing inside an isolated development container (e.g., Devcontainers) or a local virtual machine, you may need to instruct the systemd service to listen across networks.
1. Edit the systemd service override environment variables:
   ```bash
   sudo systemctl edit ollama
   ```
2. Inject the following environment variable configurations:
   ```ini
   [Service]
   Environment="OLLAMA_HOST=0.0.0.0"
   ```
3. Reload systemd definitions and restart the daemon:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart ollama
   ```

---
*Manual compiled and optimized for Linux configurations running modern open-source integrated development environments.*