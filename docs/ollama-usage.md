# Ollama Usage Reference

This document records the active Ollama configuration after a successful setup run and serves as a quick reference for day-to-day usage.

---

## Active Configuration

| Property | Value |
| :--- | :--- |
| **DeepSeek model** | `deepseek-r1:7b` (terminal / Cline) |
| **Endpoint** | `http://localhost:11434` |
| **Network exposure** | `0.0.0.0:11434` (accessible on local network) |
| **Continue.dev config** | `~/.continue/config.yaml` (primary) |

### Continue.dev model stack

| Role | Model | Purpose |
| :--- | :--- | :--- |
| Chat | `llama3.1:8b` | General-purpose chat |
| Coding chat | `qwen2.5-coder:7b` | Code-focused chat and refactoring |
| Autocomplete | `qwen2.5-coder:1.5b` | Fast inline tab completion |
| Embeddings | `nomic-embed-text:latest` | `@codebase` indexing and semantic search |

> `deepseek-r1:7b` outputs `<think>` reasoning tags that Continue.dev does not render correctly. The models above are the recommended stack for VS Code integration.

---

## VS Code Integration

### Continue.dev

The `~/.continue/config.yaml` was generated automatically by `setup.sh` (Continue 0.9+ uses YAML as the primary config format):

```yaml
version: 0.0.1
models:
  - name: Llama 3.1 8B
    provider: ollama
    model: llama3.1:8b
    apiBase: http://localhost:11434
    roles:
      - chat
      - edit
      - apply

  - name: Qwen 2.5 Coder 7B
    provider: ollama
    model: qwen2.5-coder:7b
    apiBase: http://localhost:11434
    roles:
      - chat
      - edit
      - apply

  - name: Qwen 2.5 Coder 1.5B (autocomplete)
    provider: ollama
    model: qwen2.5-coder:1.5b
    apiBase: http://localhost:11434
    roles:
      - autocomplete

  - name: Nomic Embed
    provider: ollama
    model: nomic-embed-text:latest
    apiBase: http://localhost:11434
    roles:
      - embed

tabAutocompleteModel:
  name: Qwen 2.5 Coder 1.5B
  provider: ollama
  model: qwen2.5-coder:1.5b
  apiBase: http://localhost:11434
```

To open it manually: gear icon at the bottom-right of the Continue panel → `config.yaml`.

### Cline / Roo Code

Settings → Provider → **Ollama** → Base URL: `http://localhost:11434` → Model: `deepseek-r1:7b`

---

## Useful Commands

```bash
# List all downloaded models
ollama list

# Chat with the model directly in the terminal
ollama run deepseek-r1:7b

# Pull a different model size
ollama pull deepseek-r1:1.5b
ollama pull deepseek-r1:14b

# Remove a model
ollama rm deepseek-r1:7b

# Check service status
sudo systemctl status ollama

# Watch live service logs
sudo journalctl -u ollama -f

# Check GPU usage during inference
nvidia-smi
```

---

## Service Management

Ollama runs as a systemd service and starts automatically on boot.

```bash
# Start the service
sudo systemctl start ollama

# Stop the service
sudo systemctl stop ollama

# Restart the service
sudo systemctl restart ollama

# Disable autostart
sudo systemctl disable ollama
```

### Network exposure

This installation has Ollama bound to `0.0.0.0:11434`, making it reachable from other machines on the local network (e.g. devcontainers or VMs). The override is at:

```
/etc/systemd/system/ollama.service.d/network.conf
```

To revert to localhost-only, remove that file and restart:

```bash
sudo rm /etc/systemd/system/ollama.service.d/network.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## Troubleshooting

### Model responds very slowly

Check whether Ollama is using the GPU:

```bash
sudo journalctl -u ollama --no-pager | grep -iE "(cuda|rocm|gpu)"
nvidia-smi
```

If the GPU is not being used, verify the NVIDIA driver is loaded:

```bash
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
```

### Service not starting

```bash
sudo journalctl -u ollama -n 50 --no-pager
```

### Port already in use

```bash
sudo lsof -i :11434
```
