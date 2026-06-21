# Logging System Manual — setup.sh

This document describes the design, structure, and conventions of the logging system implemented in `setup.sh`.

---

## Table of Contents

- [Overview](#overview)
- [File Location and Naming](#file-location-and-naming)
- [Log File Structure](#log-file-structure)
- [Logging Functions](#logging-functions)
- [Execution-with-Logging Functions](#execution-with-logging-functions)
- [Record Types Reference](#record-types-reference)
- [Full Log Example](#full-log-example)
- [Maintenance Guidelines](#maintenance-guidelines)

---

## Overview

The logging system is designed to record every step of `setup.sh` execution with full precision, enabling:

- **Complete traceability** — every action, command, and result is documented with a timestamp
- **Easy diagnosis** — on failure, the log pinpoints exactly which step and command caused the error
- **User choice audit** — responses to interactive prompts are captured in the log
- **Isolated execution records** — each run produces its own identifiable log file

Logs are generated only at runtime and are **never version-controlled** (the `logs/` directory is listed in `.gitignore`).

---

## File Location and Naming

### Directory

```
<repository root>/logs/
```

The `logs/` directory is created automatically by the script on the first run if it does not exist.

### File name format

```
YYYY-MM-DD-HH-MM-SS-<linuxUser>.log
```

| Component | Description | Example |
| :--- | :--- | :--- |
| `YYYY` | 4-digit year | `2026` |
| `MM` | 2-digit month | `06` |
| `DD` | 2-digit day | `21` |
| `HH` | 2-digit hour (24h) | `14` |
| `MM` | 2-digit minutes | `30` |
| `SS` | 2-digit seconds | `05` |
| `<linuxUser>` | Output of `whoami` at execution time | `smarchiori` |

**Full name example:**

```
2026-06-21-14-30-05-smarchiori.log
```

Each script run produces a separate file, even if multiple runs happen on the same day. This prevents consecutive executions from overwriting each other.

---

## Log File Structure

The log file is divided into three parts:

### 1. Header

Generated once at startup by `init_log`. Contains environment metadata:

```
================================================================================
  DEEPSEEK SETUP LOG
  Started:         2026-06-21 14:30:05
  Linux user:      smarchiori
  Hostname:        my-machine
  System:          Linux x86_64 6.x.x
  Kernel:          6.x.x-xxx.fc44.x86_64
  Total steps:     13
================================================================================
```

### 2. Steps

Each main function of the script corresponds to a numbered step, delimited by visual separators:

```
────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:06] STEP 3/13: Linux distribution detection
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:06] ACTION:    Reading /etc/os-release
  [2026-06-21 14:30:06] DATA:      ID=fedora
  [2026-06-21 14:30:06] DATA:      PRETTY_NAME=Fedora Linux 44 (Cinnamon)
  [2026-06-21 14:30:06] RESULT:    OK    — Fedora Linux 44 — family: fedora
```

### 3. Footer

Generated at the end of a successful run by `print_summary`:

```
================================================================================
  SETUP COMPLETE
  Finished:         2026-06-21 14:52:18
  Model installed:  deepseek-r1:7b
  Steps:            13/13 completed
================================================================================
```

---

## Logging Functions

All logging functions write **exclusively to the log file** — they produce no terminal output. The general format of each line is:

```
  [YYYY-MM-DD HH:MM:SS] TYPE:      Content
```

The two-space indentation and column-aligned type labels make the log easy to scan visually.

---

### `log_step "<step name>"`

Increments the step counter and writes the section separator.

**When to use:** at the beginning of each main function, representing a high-level stage of the setup.

**Log output:**
```
────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:10] STEP 4/13: GPU detection
────────────────────────────────────────────────────────────────────────────────
```

---

### `log_action "<description>"`

Describes in plain language what is about to happen. Should precede `log_cmd` when a command will be executed.

**When to use:** before any relevant operation — a file read, a check, a call to an external tool.

**Log output:**
```
  [2026-06-21 14:30:10] ACTION:    Listing PCI devices via lspci
```

---

### `log_cmd "<command>"`

Records the exact command (with arguments) that will be or was executed.

**When to use:** whenever an external binary is invoked. Do not use for simple internal shell operations like variable assignments.

**Log output:**
```
  [2026-06-21 14:30:10] COMMAND:   lspci
```

> For dynamically built commands, log the expanded form:
> ```bash
> log_cmd "ollama pull $OLLAMA_MODEL"
> ```

---

### `log_data "<key>: <value>"` or `log_data "<free text>"`

Records a collected data point or a relevant variable value.

**When to use:** after gathering system information — RAM, GPU, software version, file path, etc.

**Log output:**
```
  [2026-06-21 14:30:11] DATA:      GPU_VENDOR=nvidia
  [2026-06-21 14:30:11] DATA:      GPU_NAME=NVIDIA GeForce GTX 1650 Mobile
  [2026-06-21 14:30:11] DATA:      VRAM total: 4096 MB
```

---

### `log_choice "<choice description>"`

Records the user's response to an interactive prompt (`read -rp`).

**When to use:** immediately after each `read` that collects user input.

**Log output:**
```
  [2026-06-21 14:30:45] CHOICE:    User input: '2'
  [2026-06-21 14:30:45] CHOICE:    Final model: deepseek-r1:7b
```

---

### `log_output "<label>" "<content>"`

Records the raw output of an external command, indented for visual distinction. Does nothing if the content is empty.

**When to use:** after capturing output from tools such as `lspci`, `nvidia-smi`, `ollama list`, `systemctl status`, etc.

**Log output:**
```
  [2026-06-21 14:30:11] VGA/Display devices detected:
      00:02.0 VGA compatible controller: Intel UHD Graphics
      01:00.0 VGA compatible controller: NVIDIA GeForce GTX 1650 Mobile
```

---

### `log_result_ok "<message>"`
### `log_result_warn "<message>"`
### `log_result_err "<message>"`

Record the outcome of a step or action, at three severity levels:

| Function | Log prefix | Meaning |
| :--- | :--- | :--- |
| `log_result_ok` | `RESULT: OK    —` | Action completed successfully |
| `log_result_warn` | `RESULT: WARN  —` | Action completed with caveats or fallback behavior |
| `log_result_err` | `RESULT: ERROR —` | Action failed |

**When to use:** at the end of each action or main step function, to close the context with a clear outcome.

**Log output:**
```
  [2026-06-21 14:30:11] RESULT:    OK    — GPU: NVIDIA GeForce GTX 1650 Mobile (vendor: nvidia)
  [2026-06-21 14:30:20] RESULT:    WARN  — nvidia-smi not found or non-functional
  [2026-06-21 14:30:55] RESULT:    ERROR — exit 1
```

> `log_result_err` is also called automatically by the `die()` function before the script exits.

---

## Execution-with-Logging Functions

These functions combine command execution with automatic log recording. They are the preferred way to call external tools in the script.

---

### `run_capture "<description>" <command> [args...]`

Executes a command by capturing its full output (stdout + stderr). The output is written to the log and also echoed to the terminal. Best for fast commands where the complete result is needed before continuing.

**Behavior:**
1. Writes `ACTION` and `COMMAND` to the log
2. Executes the command and captures output in memory
3. Writes captured output to the log via `log_output`
4. Writes `RESULT` with the exit code
5. Echoes the output to the terminal
6. Returns the original exit code

**When to use:** system checks, version queries, config reads — any command that finishes quickly and whose full output is relevant to the log.

**Example:**
```bash
run_capture "Checking Ollama version" ollama --version
```

**Limitation:** not suitable for long-running commands, as the terminal stays silent while waiting for completion.

---

### `run_live "<description>" <command> [args...]`

Executes a command with live output on the terminal (via `tee`), then saves a clean copy (ANSI-stripped) to the log after completion. Best for slow operations where real-time feedback matters.

**Behavior:**
1. Writes `ACTION` and `COMMAND` to the log
2. Runs the command with live output via `tee` to a temporary file
3. On completion, post-processes the temp file — removes ANSI escape sequences (`\x1b[...m`) and carriage returns (`\r`)
4. Appends the clean output to the log
5. Removes the temporary file
6. Writes `RESULT` with the exit code
7. Returns the original exit code

**When to use:** installations (`curl | sh`), model downloads (`ollama pull`), package manager operations (`dnf`, `apt-get`) — any command that takes seconds to minutes with visible progress.

**Example:**
```bash
run_live "Downloading deepseek-r1:7b" ollama pull deepseek-r1:7b
```

**Note on ANSI codes:** stripping ANSI is necessary because progress bars and colors would pollute the log with unreadable escape sequences. The terminal still receives the full colored output normally.

---

## Record Types Reference

| Type label | Responsible function | Purpose |
| :--- | :--- | :--- |
| `STEP N/T:` | `log_step` | Delimits a high-level setup stage |
| `ACTION:` | `log_action` | Describes the intent of the next operation |
| `COMMAND:` | `log_cmd` | Records the exact command to be executed |
| `DATA:` | `log_data` | Stores a value collected from the system |
| `CHOICE:` | `log_choice` | Records interactive user input |
| `<label>:` | `log_output` | Raw output from an external tool |
| `RESULT: OK` | `log_result_ok` | Action completed successfully |
| `RESULT: WARN` | `log_result_warn` | Action completed with fallback behavior |
| `RESULT: ERROR` | `log_result_err` | Action failed |

---

## Full Log Example

Representative excerpt from a real log file:

```
================================================================================
  DEEPSEEK SETUP LOG
  Started:         2026-06-21 14:30:05
  Linux user:      smarchiori
  Hostname:        dev-notebook
  System:          Linux x86_64
  Kernel:          7.0.12-201.fc44.x86_64
  Total steps:     13
================================================================================

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:05] STEP 1/13: Privilege check
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:05] ACTION:    Checking whether the script is running as root (EUID=1000)
  [2026-06-21 14:30:05] DATA:      User: smarchiori | EUID: 1000
  [2026-06-21 14:30:05] RESULT:    OK    — Non-root user confirmed

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:05] STEP 2/13: Internet connectivity check
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:05] ACTION:    Testing HTTP access to https://ollama.com (timeout: 5s)
  [2026-06-21 14:30:05] COMMAND:   curl -fsS --max-time 5 https://ollama.com
  [2026-06-21 14:30:06] RESULT:    OK    — Response received from https://ollama.com

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:06] STEP 4/13: GPU detection
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:06] ACTION:    Listing PCI devices via lspci
  [2026-06-21 14:30:06] COMMAND:   lspci
  [2026-06-21 14:30:06] VGA/Display devices detected:
      00:02.0 VGA compatible controller: Intel UHD Graphics (rev 05)
      01:00.0 VGA compatible controller: NVIDIA GeForce GTX 1650 Mobile (rev a1)
  [2026-06-21 14:30:06] DATA:      GPU_VENDOR=nvidia
  [2026-06-21 14:30:06] DATA:      GPU_NAME=NVIDIA GeForce GTX 1650 Mobile (rev a1)
  [2026-06-21 14:30:06] ACTION:    Querying GPU details via nvidia-smi
  [2026-06-21 14:30:06] COMMAND:   nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader
  [2026-06-21 14:30:06] nvidia-smi:
      GeForce GTX 1650, 535.183.01, 4096 MiB, 3800 MiB
  [2026-06-21 14:30:06] RESULT:    OK    — GPU: NVIDIA GeForce GTX 1650 Mobile (vendor: nvidia)

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:07] STEP 6/13: DeepSeek model selection
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:07] ACTION:    Estimating best model based on available RAM and VRAM
  [2026-06-21 14:30:07] DATA:      VRAM total: 4096 MB
  [2026-06-21 14:30:07] DATA:      Selection criteria: RAM=31GB | VRAM=4GB
  [2026-06-21 14:30:07] DATA:      Suggested model: deepseek-r1:7b (Best balance for modern workstations)
  [2026-06-21 14:30:12] CHOICE:    User input: '2'
  [2026-06-21 14:30:12] CHOICE:    Final model: deepseek-r1:7b
  [2026-06-21 14:30:12] RESULT:    OK    — Model selected: deepseek-r1:7b

================================================================================
  SETUP COMPLETE
  Finished:         2026-06-21 14:52:18
  Model installed:  deepseek-r1:7b
  Steps:            13/13 completed
================================================================================
```

---

## Maintenance Guidelines

### When adding a new step to the script

1. Call `log_step "<descriptive name>"` at the start of the function
2. Use `log_action` before each relevant operation
3. Use `log_cmd` whenever an external binary is invoked
4. Use `log_data` to record collected variables and values
5. Use `log_choice` after each interactive `read`
6. Use `log_output` for raw output from external tools
7. Close with `log_result_ok`, `log_result_warn`, or `log_result_err`
8. Update `TOTAL_STEPS` at the top of the script

### When invoking external commands

- Prefer `run_capture` for fast commands (< 2s)
- Prefer `run_live` for slow commands or those with visual progress output
- Never call external binaries without first logging via `log_action` + `log_cmd`

### What NOT to log

- Passwords, API tokens, or any credentials
- Contents of configuration files that may contain secrets
- Personal data beyond the operating system username

### Log retention and cleanup

Log files are not removed automatically. For manual cleanup:

```bash
# Remove logs older than 30 days
find logs/ -name "*.log" -mtime +30 -delete

# Remove all logs
rm -f logs/*.log
```
