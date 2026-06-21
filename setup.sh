#!/usr/bin/env bash
# setup.sh — Local DeepSeek setup via Ollama on Linux

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; [[ -n "${LOG_FILE:-}" ]] && log_result_err "FATAL: $*"; exit 1; }

# ─── Logging ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")" 2>/dev/null || pwd)" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE=""
TOTAL_STEPS=13
CURRENT_STEP=0

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_strip_ansi() {
    sed 's/\x1b\[[0-9;]*[mGKHFABCDsuJrhl]//g; s/\r/\n/g'
}

init_log() {
    mkdir -p "$LOG_DIR"
    local ts linux_user
    ts=$(date '+%Y-%m-%d-%H-%M-%S')
    linux_user=$(whoami)
    LOG_FILE="$LOG_DIR/${ts}-${linux_user}.log"
    cat >> "$LOG_FILE" <<EOF
================================================================================
  DEEPSEEK SETUP LOG
  Started:         $(_ts)
  Linux user:      $linux_user
  Hostname:        $(hostname)
  System:          $(uname -srm)
  Kernel:          $(uname -r)
  Total steps:     $TOTAL_STEPS
================================================================================
EOF
    info "Log started at: ${BOLD}${LOG_FILE}${NC}"
}

log_step() {
    local name="$1"
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    {
        printf '\n%s\n' \
            "────────────────────────────────────────────────────────────────────────────────"
        printf '[%s] STEP %d/%d: %s\n' "$(_ts)" "$CURRENT_STEP" "$TOTAL_STEPS" "$name"
        printf '%s\n' \
            "────────────────────────────────────────────────────────────────────────────────"
    } >> "$LOG_FILE"
    info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: ${name}"
}

log_action()      { printf '  [%s] ACTION:    %s\n'           "$(_ts)" "$*" >> "$LOG_FILE"; }
log_cmd()         { printf '  [%s] COMMAND:   %s\n'           "$(_ts)" "$*" >> "$LOG_FILE"; }
log_data()        { printf '  [%s] DATA:      %s\n'           "$(_ts)" "$*" >> "$LOG_FILE"; }
log_choice()      { printf '  [%s] CHOICE:    %s\n'           "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_ok()   { printf '  [%s] RESULT:    OK    — %s\n'  "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_warn() { printf '  [%s] RESULT:    WARN  — %s\n'  "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_err()  { printf '  [%s] RESULT:    ERROR — %s\n'  "$(_ts)" "$*" >> "$LOG_FILE"; }

log_output() {
    local label="$1"; shift
    local content="${*:-}"
    [[ -z "$content" ]] && return 0
    printf '  [%s] %s:\n' "$(_ts)" "$label" >> "$LOG_FILE"
    printf '%s\n' "$content" | sed 's/^/      /' >> "$LOG_FILE"
}

# Runs a command capturing full output; logs it and echoes to the terminal.
# Usage: run_capture "Description" command [args...]
run_capture() {
    local desc="$1"; shift
    log_action "$desc"
    log_cmd "$*"
    local output="" exit_code=0
    output=$("$@" 2>&1) || exit_code=$?
    [[ -n "$output" ]] && log_output "Output" "$output"
    if [[ $exit_code -eq 0 ]]; then
        log_result_ok "exit $exit_code"
    else
        log_result_err "exit $exit_code"
    fi
    [[ -n "$output" ]] && echo "$output"
    return $exit_code
}

# Runs a command with live terminal output; saves ANSI-stripped copy to log.
# Usage: run_live "Description" command [args...]
run_live() {
    local desc="$1"; shift
    log_action "$desc"
    log_cmd "$*"
    local tmpfile exit_code=0
    tmpfile=$(mktemp)
    set +o pipefail
    "$@" 2>&1 | tee "$tmpfile"
    exit_code=${PIPESTATUS[0]}
    set -o pipefail
    _strip_ansi < "$tmpfile" >> "$LOG_FILE"
    rm -f "$tmpfile"
    if [[ $exit_code -eq 0 ]]; then
        log_result_ok "exit $exit_code"
    else
        log_result_err "exit $exit_code"
    fi
    return $exit_code
}

# ─── 1. Privilege check ───────────────────────────────────────────────────────
check_root() {
    log_step "Privilege check"
    log_action "Checking whether the script is running as root (EUID=$EUID)"
    if [[ $EUID -eq 0 ]]; then
        log_result_err "Script started as root — aborting for safety"
        die "Do not run this script as root. Use your regular user account."
    fi
    log_data "User: $(whoami) | EUID: $EUID"
    log_result_ok "Non-root user confirmed"
}

# ─── 2. Internet connectivity check ──────────────────────────────────────────
check_internet() {
    log_step "Internet connectivity check"
    log_action "Testing HTTP access to https://ollama.com (timeout: 5s)"
    log_cmd "curl -fsS --max-time 5 https://ollama.com"
    if ! curl -fsS --max-time 5 https://ollama.com > /dev/null 2>&1; then
        log_result_err "No response from ollama.com after 5s"
        die "No internet access. Check your connection and try again."
    fi
    log_result_ok "Response received from https://ollama.com"
    success "Internet OK"
}

# ─── 3. Linux distribution detection ─────────────────────────────────────────
detect_distro() {
    log_step "Linux distribution detection"
    log_action "Reading /etc/os-release"
    if [[ ! -f /etc/os-release ]]; then
        log_result_err "/etc/os-release not found"
        die "Could not detect the Linux distribution."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    log_data "ID=$DISTRO_ID"
    log_data "ID_LIKE=${DISTRO_ID_LIKE:-<empty>}"
    log_data "PRETTY_NAME=${PRETTY_NAME:-n/a}"
    log_data "VERSION_ID=${VERSION_ID:-n/a}"

    if echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qi "fedora"; then
        DISTRO_FAMILY="fedora"
    elif echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "(debian|ubuntu)"; then
        DISTRO_FAMILY="debian"
    else
        DISTRO_FAMILY="debian"
        log_result_warn "Distro '$DISTRO_ID' not tested — falling back to debian"
        warn "Distribution '$DISTRO_ID' not tested. Attempting Debian-compatible mode."
    fi
    log_data "Resolved family: $DISTRO_FAMILY"
    log_result_ok "${PRETTY_NAME:-$DISTRO_ID} — family: $DISTRO_FAMILY"
    success "Distribution: ${BOLD}${PRETTY_NAME:-$DISTRO_ID}${NC} (family: $DISTRO_FAMILY)"
}

# ─── 4. GPU detection ─────────────────────────────────────────────────────────
detect_gpu() {
    log_step "GPU detection"
    GPU_VENDOR="none"
    GPU_NAME="No dedicated GPU detected"

    if ! command -v lspci &>/dev/null; then
        log_result_warn "lspci not available — GPU detection skipped"
        warn "lspci not found. GPU detection skipped."
        return 0
    fi

    log_action "Listing PCI devices via lspci"
    log_cmd "lspci"
    local lspci_out
    lspci_out=$(lspci 2>/dev/null)
    log_output "VGA/Display devices detected" \
        "$(echo "$lspci_out" | grep -iE "(vga|display|3d)" || echo "(none)")"

    if echo "$lspci_out" | grep -qi nvidia; then
        GPU_VENDOR="nvidia"
        GPU_NAME=$(echo "$lspci_out" | grep -i nvidia | grep -iE "(vga|display|3d)" | head -1 | sed 's/.*: //')
    elif echo "$lspci_out" | grep -qiE "(amd|radeon)"; then
        GPU_VENDOR="amd"
        GPU_NAME=$(echo "$lspci_out" | grep -iE "(amd|radeon)" | grep -iE "(vga|display|3d)" | head -1 | sed 's/.*: //')
    fi

    log_data "GPU_VENDOR=$GPU_VENDOR"
    log_data "GPU_NAME=$GPU_NAME"

    if [[ "$GPU_VENDOR" == "nvidia" ]] && command -v nvidia-smi &>/dev/null; then
        log_action "Querying GPU details via nvidia-smi"
        log_cmd "nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader"
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free \
            --format=csv,noheader 2>/dev/null || echo "unavailable")
        log_output "nvidia-smi" "$smi_out"
    fi

    log_result_ok "GPU: $GPU_NAME (vendor: $GPU_VENDOR)"
    info "GPU detected: ${BOLD}${GPU_NAME}${NC}"
}

# ─── 5. RAM detection ─────────────────────────────────────────────────────────
detect_ram() {
    log_step "RAM detection"
    log_action "Reading memory stats from /proc/meminfo"
    log_cmd "awk '/MemTotal/ { printf \"%.0f\", \$2/1024/1024 }' /proc/meminfo"
    TOTAL_RAM_GB=$(awk '/MemTotal/ { printf "%.0f", $2/1024/1024 }' /proc/meminfo)
    local mem_detail
    mem_detail=$(grep -E "^Mem(Total|Free|Available)" /proc/meminfo | \
        awk '{printf "  %-20s %s %s\n", $1, $2, $3}')
    log_output "Memory (/proc/meminfo)" "$mem_detail"
    log_data "Total RAM: ${TOTAL_RAM_GB} GB"
    log_result_ok "Total RAM: ${TOTAL_RAM_GB} GB"
    success "Total RAM: ${BOLD}${TOTAL_RAM_GB} GB${NC}"
}

# ─── 6. Model selection ───────────────────────────────────────────────────────
suggest_model() {
    log_step "DeepSeek model selection"
    log_action "Estimating best model based on available RAM and VRAM"

    VRAM_MB=0
    if [[ "$GPU_VENDOR" == "nvidia" ]] && command -v nvidia-smi &>/dev/null; then
        log_action "Querying total VRAM via nvidia-smi"
        log_cmd "nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits"
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
            2>/dev/null | head -1 | tr -d ' ' || echo 0)
        log_data "Total VRAM: ${VRAM_MB} MB"
    else
        log_data "nvidia-smi unavailable — VRAM assumed as 0 MB"
    fi
    VRAM_GB=$(( VRAM_MB / 1024 ))
    log_data "Selection criteria: RAM=${TOTAL_RAM_GB}GB | VRAM=${VRAM_GB}GB"

    if [[ $TOTAL_RAM_GB -ge 32 ]] || [[ $VRAM_GB -ge 16 ]]; then
        SUGGESTED_MODEL="deepseek-r1:14b"
        MODEL_NOTE="Sufficient RAM/VRAM for excellent reasoning quality"
    elif [[ $TOTAL_RAM_GB -ge 16 ]] || [[ $VRAM_GB -ge 8 ]]; then
        SUGGESTED_MODEL="deepseek-r1:7b"
        MODEL_NOTE="Best balance for modern workstations"
    else
        SUGGESTED_MODEL="deepseek-r1:1.5b"
        MODEL_NOTE="Limited hardware — lightweight model for maximum compatibility"
    fi
    log_data "Suggested model: $SUGGESTED_MODEL ($MODEL_NOTE)"

    echo ""
    echo -e "${BOLD}Available models:${NC}"
    echo "  1) deepseek-r1:1.5b  (~1.1 GB) — Light hardware / laptops"
    echo "  2) deepseek-r1:7b    (~4.7 GB) — Modern workstations [16GB RAM / 8GB VRAM]"
    echo "  3) deepseek-r1:14b   (~9.0 GB) — Mid-to-high tier GPUs"
    echo "  4) deepseek-r1:32b   (~20 GB)  — Enterprise / large VRAM"
    echo ""
    echo -e "  ${GREEN}Suggested for your hardware: ${BOLD}${SUGGESTED_MODEL}${NC} — ${MODEL_NOTE}"
    echo ""

    read -rp "Choose a model [1-4, Enter to use suggested]: " MODEL_CHOICE
    log_choice "User input: '$MODEL_CHOICE'"

    case "$MODEL_CHOICE" in
        1) OLLAMA_MODEL="deepseek-r1:1.5b" ;;
        2) OLLAMA_MODEL="deepseek-r1:7b" ;;
        3) OLLAMA_MODEL="deepseek-r1:14b" ;;
        4) OLLAMA_MODEL="deepseek-r1:32b" ;;
        *) OLLAMA_MODEL="$SUGGESTED_MODEL" ;;
    esac
    log_choice "Final model: $OLLAMA_MODEL"
    log_result_ok "Model selected: $OLLAMA_MODEL"
    success "Model selected: ${BOLD}${OLLAMA_MODEL}${NC}"
}

# ─── 7. NVIDIA driver installation ────────────────────────────────────────────
install_nvidia_drivers() {
    log_step "NVIDIA driver check and installation"

    if [[ "$GPU_VENDOR" != "nvidia" ]]; then
        log_data "GPU vendor=$GPU_VENDOR — NVIDIA driver step skipped"
        log_result_ok "Not applicable (non-NVIDIA GPU)"
        return 0
    fi

    info "NVIDIA GPU detected. Checking drivers and CUDA support..."
    log_action "Checking for nvidia-smi presence and functionality"
    log_cmd "nvidia-smi"

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=name,driver_version,memory.total \
            --format=csv,noheader 2>/dev/null || true)
        log_output "nvidia-smi (name, driver, VRAM)" "$smi_out"
        log_result_ok "NVIDIA drivers functional — no installation needed"
        success "NVIDIA drivers already installed and working"
        return 0
    fi

    log_result_warn "nvidia-smi absent or non-functional"
    warn "NVIDIA drivers not found or not working."
    read -rp "Install NVIDIA drivers now? [y/N]: " INSTALL_DRIVERS
    log_choice "Install NVIDIA drivers: '$INSTALL_DRIVERS'"

    if [[ ! "$INSTALL_DRIVERS" =~ ^[yY]$ ]]; then
        log_result_warn "User skipped driver installation — Ollama will use CPU only"
        warn "Skipping driver installation. Ollama will use CPU (slower)."
        return 0
    fi

    if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        log_action "Enabling RPM Fusion and installing akmod-nvidia + CUDA (Fedora)"
        log_cmd "dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda"
        info "Enabling RPM Fusion and installing NVIDIA drivers..."
        local fed_ver
        fed_ver=$(rpm -E %fedora)
        log_data "Fedora version: $fed_ver"
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fed_ver}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fed_ver}.noarch.rpm" \
            2>&1 | tee -a "$LOG_FILE" || true
        sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda 2>&1 | tee -a "$LOG_FILE"
        log_result_ok "Drivers installed — system restart required"
        warn "NVIDIA drivers installed. ${BOLD}Restart the system before continuing.${NC}"
        exit 0

    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        log_action "Installing NVIDIA drivers via apt (Debian/Ubuntu)"
        log_cmd "apt-get install nvidia-driver cuda-toolkit"
        info "Installing NVIDIA drivers via apt..."
        sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
        sudo apt-get install -y nvidia-driver cuda-toolkit 2>&1 | tee -a "$LOG_FILE" || \
            sudo ubuntu-drivers install 2>&1 | tee -a "$LOG_FILE" || \
            { log_result_warn "Automatic installation failed"; warn "Install drivers manually."; }
        log_result_ok "Drivers installed — system restart required"
        warn "Drivers installed. ${BOLD}Restart the system before continuing.${NC}"
        exit 0
    fi
}

# ─── 8. Ollama installation ───────────────────────────────────────────────────
install_ollama() {
    log_step "Ollama installation"
    log_action "Checking whether Ollama is already present in PATH"
    log_cmd "which ollama && ollama --version"

    if command -v ollama &>/dev/null; then
        local ver path
        ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
        path=$(which ollama)
        log_data "Path: $path"
        log_data "Version: $ver"
        log_result_ok "Ollama already installed — skipping (v$ver)"
        success "Ollama already installed (version: $ver)"
        return 0
    fi

    log_result_warn "Ollama not found — starting installation"
    info "Installing Ollama..."
    log_action "Downloading and running the official installer via curl | sh"
    log_cmd "curl -fsSL https://ollama.com/install.sh | sh"
    run_live "Official Ollama installer" bash -c "curl -fsSL https://ollama.com/install.sh | sh"

    local ver path
    ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
    path=$(which ollama 2>/dev/null || echo "not found")
    log_data "Post-install path: $path"
    log_data "Post-install version: $ver"
    log_result_ok "Ollama installed successfully (v$ver)"
    success "Ollama installed successfully"
}

# ─── 9. Ollama service startup ────────────────────────────────────────────────
start_ollama_service() {
    log_step "Ollama service startup"
    info "Checking Ollama service..."

    log_action "Querying ollama service state in systemd"
    log_cmd "systemctl is-active ollama"

    if systemctl is-active --quiet ollama 2>/dev/null; then
        local status_out
        status_out=$(systemctl status ollama --no-pager -l 2>/dev/null | head -20 || true)
        log_output "systemctl status ollama" "$status_out"
        log_result_ok "Service already active (systemd)"
        success "Ollama service is already running"
        return 0
    fi

    if systemctl is-enabled --quiet ollama 2>/dev/null; then
        log_action "Service enabled but stopped — starting via systemd"
        log_cmd "systemctl start ollama"
        sudo systemctl start ollama
        sleep 2
        local status_out
        status_out=$(systemctl status ollama --no-pager -l 2>/dev/null | head -20 || true)
        log_output "systemctl status ollama" "$status_out"
        log_result_ok "Service started via systemd"
        success "Ollama service started"
        return 0
    fi

    log_result_warn "systemd service not found — starting ollama serve manually"
    warn "Ollama systemd service not found. Starting manually in background..."
    log_action "Running 'ollama serve' in background"
    log_cmd "nohup ollama serve >> LOG_FILE 2>&1 &"
    nohup ollama serve >> "$LOG_FILE" 2>&1 &
    local pid=$!
    sleep 3
    log_data "Process PID: $pid"

    if kill -0 "$pid" 2>/dev/null; then
        log_result_ok "Ollama running in background (PID: $pid)"
        success "Ollama running in background (PID: $pid)"
    else
        log_result_err "Process died unexpectedly after startup"
        die "Failed to start Ollama. Check the log: $LOG_FILE"
    fi
}

# ─── 10. Network access configuration ────────────────────────────────────────
configure_network_access() {
    log_step "Network access configuration"
    log_action "Prompting user about network exposure"
    echo ""
    read -rp "Expose Ollama on the local network (useful for devcontainers/VMs)? [y/N]: " EXPOSE_NETWORK
    log_choice "Expose Ollama on network: '$EXPOSE_NETWORK'"

    if [[ ! "$EXPOSE_NETWORK" =~ ^[yY]$ ]]; then
        log_data "Ollama will remain on 127.0.0.1:11434 (default)"
        log_result_ok "Default network configuration kept"
        return 0
    fi

    info "Configuring Ollama to listen on 0.0.0.0:11434..."

    if systemctl list-unit-files ollama.service &>/dev/null; then
        log_action "Creating systemd service override with OLLAMA_HOST=0.0.0.0"
        log_cmd "systemctl edit ollama → Environment=OLLAMA_HOST=0.0.0.0"
        local override_path="/etc/systemd/system/ollama.service.d/network.conf"
        sudo mkdir -p "$(dirname "$override_path")"
        sudo tee "$override_path" > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
        log_data "Override created at: $override_path"
        log_cmd "systemctl daemon-reload && systemctl restart ollama"
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
        log_data "OLLAMA_HOST=0.0.0.0 active"
        log_result_ok "Ollama exposed on 0.0.0.0:11434"
        success "Ollama exposed on 0.0.0.0:11434"
    else
        log_result_warn "systemd unit not found — override not applied"
        warn "systemd service not found. Set OLLAMA_HOST=0.0.0.0 manually before starting Ollama."
    fi
}

# ─── 11. Model download ───────────────────────────────────────────────────────
pull_model() {
    log_step "Model download: $OLLAMA_MODEL"
    info "Downloading model ${BOLD}${OLLAMA_MODEL}${NC}..."
    log_action "Starting model pull via Ollama"
    log_cmd "ollama pull $OLLAMA_MODEL"
    echo ""

    if ! run_live "ollama pull $OLLAMA_MODEL" ollama pull "$OLLAMA_MODEL"; then
        log_result_err "Download failed for $OLLAMA_MODEL"
        die "Failed to download the model. Try manually: ollama pull $OLLAMA_MODEL"
    fi

    log_action "Verifying model in local list"
    log_cmd "ollama list"
    local list_out
    list_out=$(ollama list 2>/dev/null || true)
    log_output "ollama list" "$list_out"
    log_result_ok "Model $OLLAMA_MODEL available locally"
    success "Model ${OLLAMA_MODEL} downloaded successfully"
}

# ─── 12. Model test ───────────────────────────────────────────────────────────
test_model() {
    log_step "Model functionality test"
    info "Testing the model with a simple prompt..."
    local prompt="Answer in one line: which programming language would you recommend for beginners and why?"
    log_action "Sending test prompt to the model"
    log_cmd "ollama run $OLLAMA_MODEL '<prompt>'"
    log_data "Prompt: $prompt"
    echo ""

    local response="" exit_code=0
    response=$(ollama run "$OLLAMA_MODEL" "$prompt" 2>/dev/null) || exit_code=$?

    log_output "Model response" "$response"

    if [[ $exit_code -eq 0 ]] && [[ -n "$response" ]]; then
        log_result_ok "Model responded to the test (exit $exit_code)"
        success "Model responded successfully:"
        echo -e "  ${BOLD}${response}${NC}"
    else
        log_result_warn "Model did not respond (exit $exit_code) — may be a timeout or memory issue"
        warn "Model did not respond to the test. Check with: ollama run $OLLAMA_MODEL"
    fi
}

# ─── 13. Continue.dev configuration ──────────────────────────────────────────
generate_continue_config() {
    log_step "Continue.dev configuration"
    local config_dir="$HOME/.continue"
    local config_file="$config_dir/config.json"
    local autocomplete_model="deepseek-r1:1.5b"

    echo ""
    read -rp "Generate Continue.dev configuration for this model? [Y/n]: " GEN_CONTINUE
    log_choice "Generate Continue.dev config: '$GEN_CONTINUE'"

    if [[ "$GEN_CONTINUE" =~ ^[nN]$ ]]; then
        log_data "Continue.dev configuration skipped by user"
        log_result_ok "Step skipped by user"
        return 0
    fi

    log_action "Creating directory $config_dir"
    log_cmd "mkdir -p $config_dir"
    mkdir -p "$config_dir"
    log_data "Main model: $OLLAMA_MODEL"
    log_data "Autocomplete model: $autocomplete_model"
    log_data "Target file: $config_file"

    log_action "Writing config.json"
    cat > "$config_file" <<EOF
{
  "models": [
    {
      "title": "DeepSeek (Local)",
      "provider": "ollama",
      "model": "${OLLAMA_MODEL}"
    }
  ],
  "tabAutocompleteModel": {
    "title": "DeepSeek Autocomplete",
    "provider": "ollama",
    "model": "${autocomplete_model}"
  },
  "allowAnonymousTelemetry": false
}
EOF
    log_output "Generated config.json" "$(cat "$config_file")"

    if [[ "$OLLAMA_MODEL" != "$autocomplete_model" ]]; then
        log_action "Starting autocomplete model download in background"
        log_cmd "ollama pull $autocomplete_model (background)"
        info "Downloading lightweight model ${autocomplete_model} for autocomplete in background..."
        ollama pull "$autocomplete_model" >> "$LOG_FILE" 2>&1 &
        log_data "Autocomplete download PID: $!"
    fi

    log_result_ok "config.json saved to $config_file"
    success "Continue.dev configuration saved to: $config_file"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    {
        printf '\n%s\n' "================================================================================"
        printf '  SETUP COMPLETE\n'
        printf '  Finished:         %s\n' "$(_ts)"
        printf '  Model installed:  %s\n' "$OLLAMA_MODEL"
        printf '  Steps:            %d/%d completed\n' "$CURRENT_STEP" "$TOTAL_STEPS"
        printf '%s\n' "================================================================================"
    } >> "$LOG_FILE"

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  Setup completed successfully!${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Active model:${NC}     $OLLAMA_MODEL"
    echo -e "  ${BOLD}Endpoint:${NC}         http://localhost:11434"
    echo -e "  ${BOLD}Full log:${NC}         $LOG_FILE"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Install the Continue.dev or Cline extension in VS Code"
    echo "  2. In Continue: gear icon → config.json already configured"
    echo "  3. In Cline: Settings → Provider → Ollama → http://localhost:11434"
    echo ""
    echo -e "${BOLD}Useful commands:${NC}"
    echo "  ollama list                        # list downloaded models"
    echo "  ollama run $OLLAMA_MODEL   # chat directly in terminal"
    echo "  sudo systemctl status ollama       # service status"
    echo "  sudo journalctl -u ollama -f       # live service logs"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}   DeepSeek Local Setup via Ollama — Linux${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""

    init_log
    check_root
    check_internet
    detect_distro
    detect_gpu
    detect_ram
    suggest_model
    install_nvidia_drivers
    install_ollama
    start_ollama_service
    configure_network_access
    pull_model
    test_model
    generate_continue_config
    print_summary
}

main "$@"
