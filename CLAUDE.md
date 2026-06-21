# Project Guidelines for Claude

This file is read automatically by Claude Code at the start of every session. It captures the project's conventions, decisions, and context so they do not need to be re-established in each conversation.

---

## Language

**All content in this repository must be written in English.** This applies to:

- Source code comments
- Log messages and all user-facing output in scripts
- All documentation files (`.md`)
- Commit messages
- Variable names and identifiers

When editing existing files or creating new ones, always use English regardless of the language used in the conversation with the user.

---

## Git Configuration

- **Username:** `serginhoshm`
- **Email:** `serginhoshm@gmail.com`
- **Remote:** `git@github.com:serginhoshm/deepseek-vscode-linux.git`
- SSH authentication is configured and working for this account.

---

## Project Purpose

This repository is a setup guide and automation script for running DeepSeek AI models locally (via Ollama) and via the cloud API, integrated with Visual Studio Code on Linux (Fedora and Debian/Ubuntu).

The two primary artifacts are:

| File | Purpose |
| :--- | :--- |
| `setup.sh` | Interactive bash script that installs and configures everything end-to-end |
| `README.md` | User-facing guide covering both manual and automated setup paths |
| `Instructions.md` | Original technical reference document (source material) |
| `docs/logging.md` | Manual describing the logging system implemented in `setup.sh` |
| `docs/continue-dev.md` | Complete Continue.dev 2.0 configuration guide (YAML format, roles, troubleshooting) |
| `docs/ollama-usage.md` | Quick reference for active Ollama config and useful commands |

---

## Repository Structure

```
.
├── CLAUDE.md            # This file — project guidelines for Claude Code
├── README.md            # Main user-facing documentation
├── Instructions.md      # Original technical reference
├── setup.sh             # Interactive setup script
├── .gitignore           # Excludes logs/
├── docs/
│   ├── logging.md       # Logging system manual
│   ├── continue-dev.md  # Continue.dev 2.0 full configuration guide
│   └── ollama-usage.md  # Ollama quick reference
└── logs/                # Runtime log files (gitignored, created by setup.sh)
```

---

## setup.sh — Design Decisions

### General

- Uses `set -euo pipefail` — exits on any error, unset variable, or pipe failure.
- Never runs as root; exits immediately if `EUID == 0`.
- All interactive prompts use `read -rp`; answers are logged via `log_choice`.

### Step structure

The script has exactly **13 steps**, each mapped to a dedicated function:

| Step | Function | Purpose |
| ---: | :--- | :--- |
| 1 | `check_root` | Reject execution as root |
| 2 | `check_internet` | Verify connectivity to ollama.com |
| 3 | `detect_distro` | Identify Fedora vs. Debian family |
| 4 | `detect_gpu` | Find NVIDIA/AMD GPU via lspci + nvidia-smi |
| 5 | `detect_ram` | Read total RAM from /proc/meminfo |
| 6 | `suggest_model` | Recommend and let user pick a DeepSeek model |
| 7 | `install_nvidia_drivers` | Install CUDA drivers if NVIDIA GPU and no nvidia-smi |
| 8 | `install_ollama` | Install Ollama via official script if not present |
| 9 | `start_ollama_service` | Start via systemd or fallback to background process |
| 10 | `configure_network_access` | Optionally expose Ollama on 0.0.0.0 |
| 11 | `pull_model` | Download the selected DeepSeek model |
| 12 | `test_model` | Send a one-line test prompt to verify the model works |
| 13 | `generate_continue_config` | Write `~/.continue/config.json` for Continue.dev |

If steps are added or removed, update `TOTAL_STEPS` at the top of the script.

### Model selection logic

| Condition | Suggested model |
| :--- | :--- |
| RAM ≥ 32 GB or VRAM ≥ 16 GB | `deepseek-r1:14b` |
| RAM ≥ 16 GB or VRAM ≥ 8 GB | `deepseek-r1:7b` |
| Otherwise | `deepseek-r1:1.5b` |

### Execution helpers

- **`run_capture`** — for fast commands (< 2s): captures stdout+stderr, logs it, echoes to terminal.
- **`run_live`** — for slow commands (installs, downloads): pipes through `tee` to a temp file for live output, then strips ANSI codes and appends to the log. Use this for `ollama pull`, `curl | sh`, and package manager calls.

---

## Logging System

### File location and naming

- Directory: `logs/` at the repo root (gitignored).
- File name: `YYYY-MM-DD-HH-MM-SS-<linuxUser>.log`
- Each run produces a separate file — no overwriting.

### Log record types

| Label | Function | When to use |
| :--- | :--- | :--- |
| `STEP N/T:` | `log_step` | Once per main function |
| `ACTION:` | `log_action` | Before each relevant operation |
| `COMMAND:` | `log_cmd` | Whenever an external binary is invoked |
| `DATA:` | `log_data` | After collecting a system value or variable |
| `CHOICE:` | `log_choice` | After each `read` that captures user input |
| `<label>:` | `log_output` | Raw output from external tools |
| `RESULT: OK` | `log_result_ok` | Successful outcome |
| `RESULT: WARN` | `log_result_warn` | Completed with fallback/caveat |
| `RESULT: ERROR` | `log_result_err` | Failure |

Full documentation: [`docs/logging.md`](docs/logging.md)

---

## Conventions

- **No Portuguese** anywhere in code, docs, or commits — English only.
- **No sudo as the main user** — the script asks for `sudo` only for specific privileged operations (package install, systemd edits).
- **Soft failures preferred** — steps that can be skipped (NVIDIA drivers, network exposure, Continue.dev config) ask the user rather than failing hard.
- **ANSI stripping in logs** — `run_live` strips color codes before writing to the log file so logs are human-readable in any text editor.
- **Logs are never committed** — `logs/` is in `.gitignore`.
- **Interactive prompts use `[y/N]` or `[Y/n]`** — uppercase letter is the default; `log_choice` records the raw input immediately after each `read`.
