#!/usr/bin/env bash
# setup.sh — Instalação e configuração do DeepSeek local via Ollama no Linux

set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC} $*" >&2; }
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
  Início:          $(_ts)
  Usuário Linux:   $linux_user
  Hostname:        $(hostname)
  Sistema:         $(uname -srm)
  Kernel:          $(uname -r)
  Total de passos: $TOTAL_STEPS
================================================================================
EOF
    info "Log iniciado em: ${BOLD}${LOG_FILE}${NC}"
}

log_step() {
    local name="$1"
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    {
        printf '\n%s\n' \
            "────────────────────────────────────────────────────────────────────────────────"
        printf '[%s] PASSO %d/%d: %s\n' "$(_ts)" "$CURRENT_STEP" "$TOTAL_STEPS" "$name"
        printf '%s\n' \
            "────────────────────────────────────────────────────────────────────────────────"
    } >> "$LOG_FILE"
    info "Passo ${CURRENT_STEP}/${TOTAL_STEPS}: ${name}"
}

log_action()      { printf '  [%s] AÇÃO:      %s\n'            "$(_ts)" "$*" >> "$LOG_FILE"; }
log_cmd()         { printf '  [%s] COMANDO:   %s\n'            "$(_ts)" "$*" >> "$LOG_FILE"; }
log_data()        { printf '  [%s] DADO:      %s\n'            "$(_ts)" "$*" >> "$LOG_FILE"; }
log_choice()      { printf '  [%s] ESCOLHA:   %s\n'            "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_ok()   { printf '  [%s] RESULTADO: OK    — %s\n'   "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_warn() { printf '  [%s] RESULTADO: AVISO — %s\n'   "$(_ts)" "$*" >> "$LOG_FILE"; }
log_result_err()  { printf '  [%s] RESULTADO: ERRO  — %s\n'   "$(_ts)" "$*" >> "$LOG_FILE"; }

log_output() {
    local label="$1"; shift
    local content="${*:-}"
    [[ -z "$content" ]] && return 0
    printf '  [%s] %s:\n' "$(_ts)" "$label" >> "$LOG_FILE"
    printf '%s\n' "$content" | sed 's/^/      /' >> "$LOG_FILE"
}

# Executa um comando capturando a saída; loga e ecoa para o terminal.
# Uso: run_capture "Descrição da ação" comando [args...]
run_capture() {
    local desc="$1"; shift
    log_action "$desc"
    log_cmd "$*"
    local output="" exit_code=0
    output=$("$@" 2>&1) || exit_code=$?
    [[ -n "$output" ]] && log_output "Saída" "$output"
    if [[ $exit_code -eq 0 ]]; then
        log_result_ok "exit $exit_code"
    else
        log_result_err "exit $exit_code"
    fi
    [[ -n "$output" ]] && echo "$output"
    return $exit_code
}

# Executa um comando com saída ao vivo no terminal; loga a saída sem ANSI.
# Uso: run_live "Descrição da ação" comando [args...]
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

# ─── 1. Verificação de privilégios ────────────────────────────────────────────
check_root() {
    log_step "Verificação de privilégios"
    log_action "Checando se o script está rodando como root (EUID=$EUID)"
    if [[ $EUID -eq 0 ]]; then
        log_result_err "Script iniciado como root — abortando por segurança"
        die "Não execute este script como root. Use seu usuário normal."
    fi
    log_data "Usuário: $(whoami) | EUID: $EUID"
    log_result_ok "Usuário não-root confirmado"
}

# ─── 2. Verificação de internet ───────────────────────────────────────────────
check_internet() {
    log_step "Verificação de conectividade com a internet"
    log_action "Testando acesso HTTP a https://ollama.com (timeout: 5s)"
    log_cmd "curl -fsS --max-time 5 https://ollama.com"
    if ! curl -fsS --max-time 5 https://ollama.com > /dev/null 2>&1; then
        log_result_err "Sem resposta de ollama.com após 5s"
        die "Sem acesso à internet. Verifique sua conexão e tente novamente."
    fi
    log_result_ok "Resposta recebida de https://ollama.com"
    success "Internet OK"
}

# ─── 3. Detecção de distribuição ──────────────────────────────────────────────
detect_distro() {
    log_step "Detecção da distribuição Linux"
    log_action "Lendo /etc/os-release"
    if [[ ! -f /etc/os-release ]]; then
        log_result_err "/etc/os-release não encontrado"
        die "Não foi possível detectar a distribuição Linux."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    log_data "ID=$DISTRO_ID"
    log_data "ID_LIKE=${DISTRO_ID_LIKE:-<vazio>}"
    log_data "PRETTY_NAME=${PRETTY_NAME:-n/a}"
    log_data "VERSION_ID=${VERSION_ID:-n/a}"

    if echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qi "fedora"; then
        DISTRO_FAMILY="fedora"
    elif echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "(debian|ubuntu)"; then
        DISTRO_FAMILY="debian"
    else
        DISTRO_FAMILY="debian"
        log_result_warn "Distro '$DISTRO_ID' não testada — usando fallback debian"
        warn "Distribuição '$DISTRO_ID' não testada. Tentando como Debian-compatível."
    fi
    log_data "Família resolvida: $DISTRO_FAMILY"
    log_result_ok "${PRETTY_NAME:-$DISTRO_ID} — família: $DISTRO_FAMILY"
    success "Distribuição: ${BOLD}${PRETTY_NAME:-$DISTRO_ID}${NC} (família: $DISTRO_FAMILY)"
}

# ─── 4. Detecção de GPU ───────────────────────────────────────────────────────
detect_gpu() {
    log_step "Detecção de GPU"
    GPU_VENDOR="none"
    GPU_NAME="Nenhuma GPU dedicada detectada"

    if ! command -v lspci &>/dev/null; then
        log_result_warn "lspci não disponível — não foi possível detectar GPU"
        warn "lspci não encontrado. Detecção de GPU ignorada."
        return 0
    fi

    log_action "Listando dispositivos PCI via lspci"
    log_cmd "lspci"
    local lspci_out
    lspci_out=$(lspci 2>/dev/null)
    log_output "Dispositivos VGA/Display detectados" \
        "$(echo "$lspci_out" | grep -iE "(vga|display|3d)" || echo "(nenhum)")"

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
        log_action "Consultando detalhes da GPU via nvidia-smi"
        log_cmd "nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader"
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free \
            --format=csv,noheader 2>/dev/null || echo "indisponível")
        log_output "nvidia-smi" "$smi_out"
    fi

    log_result_ok "GPU: $GPU_NAME (vendor: $GPU_VENDOR)"
    info "GPU detectada: ${BOLD}${GPU_NAME}${NC}"
}

# ─── 5. Detecção de RAM ───────────────────────────────────────────────────────
detect_ram() {
    log_step "Detecção de memória RAM"
    log_action "Lendo estatísticas de memória em /proc/meminfo"
    log_cmd "awk '/MemTotal/ { printf \"%.0f\", \$2/1024/1024 }' /proc/meminfo"
    TOTAL_RAM_GB=$(awk '/MemTotal/ { printf "%.0f", $2/1024/1024 }' /proc/meminfo)
    local mem_detail
    mem_detail=$(grep -E "^Mem(Total|Free|Available)" /proc/meminfo | \
        awk '{printf "  %-20s %s %s\n", $1, $2, $3}')
    log_output "Memória (/proc/meminfo)" "$mem_detail"
    log_data "RAM total: ${TOTAL_RAM_GB} GB"
    log_result_ok "RAM total: ${TOTAL_RAM_GB} GB"
    success "RAM total: ${BOLD}${TOTAL_RAM_GB} GB${NC}"
}

# ─── 6. Seleção do modelo ─────────────────────────────────────────────────────
suggest_model() {
    log_step "Seleção do modelo DeepSeek"
    log_action "Estimando modelo ideal com base em RAM e VRAM disponíveis"

    VRAM_MB=0
    if [[ "$GPU_VENDOR" == "nvidia" ]] && command -v nvidia-smi &>/dev/null; then
        log_action "Consultando VRAM total via nvidia-smi"
        log_cmd "nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits"
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
            2>/dev/null | head -1 | tr -d ' ' || echo 0)
        log_data "VRAM total: ${VRAM_MB} MB"
    else
        log_data "nvidia-smi indisponível — VRAM assumida como 0 MB"
    fi
    VRAM_GB=$(( VRAM_MB / 1024 ))
    log_data "Critério de seleção: RAM=${TOTAL_RAM_GB}GB | VRAM=${VRAM_GB}GB"

    if [[ $TOTAL_RAM_GB -ge 32 ]] || [[ $VRAM_GB -ge 16 ]]; then
        SUGGESTED_MODEL="deepseek-r1:14b"
        MODEL_NOTE="RAM/VRAM suficiente para ótima qualidade de raciocínio"
    elif [[ $TOTAL_RAM_GB -ge 16 ]] || [[ $VRAM_GB -ge 8 ]]; then
        SUGGESTED_MODEL="deepseek-r1:7b"
        MODEL_NOTE="Melhor custo-benefício para workstations modernas"
    else
        SUGGESTED_MODEL="deepseek-r1:1.5b"
        MODEL_NOTE="Hardware limitado — modelo leve para máxima compatibilidade"
    fi
    log_data "Modelo sugerido: $SUGGESTED_MODEL ($MODEL_NOTE)"

    echo ""
    echo -e "${BOLD}Modelos disponíveis:${NC}"
    echo "  1) deepseek-r1:1.5b  (~1.1 GB) — Hardware leve / laptops"
    echo "  2) deepseek-r1:7b    (~4.7 GB) — Workstations modernas [16GB RAM / 8GB VRAM]"
    echo "  3) deepseek-r1:14b   (~9.0 GB) — GPUs mid-to-high tier"
    echo "  4) deepseek-r1:32b   (~20 GB)  — Enterprise / muita VRAM"
    echo ""
    echo -e "  ${GREEN}Sugestão para seu hardware: ${BOLD}${SUGGESTED_MODEL}${NC} — ${MODEL_NOTE}"
    echo ""

    read -rp "Escolha o modelo [1-4, Enter para usar o sugerido]: " MODEL_CHOICE
    log_choice "Entrada do usuário: '$MODEL_CHOICE'"

    case "$MODEL_CHOICE" in
        1) OLLAMA_MODEL="deepseek-r1:1.5b" ;;
        2) OLLAMA_MODEL="deepseek-r1:7b" ;;
        3) OLLAMA_MODEL="deepseek-r1:14b" ;;
        4) OLLAMA_MODEL="deepseek-r1:32b" ;;
        *) OLLAMA_MODEL="$SUGGESTED_MODEL" ;;
    esac
    log_choice "Modelo final: $OLLAMA_MODEL"
    log_result_ok "Modelo selecionado: $OLLAMA_MODEL"
    success "Modelo selecionado: ${BOLD}${OLLAMA_MODEL}${NC}"
}

# ─── 7. Drivers NVIDIA ────────────────────────────────────────────────────────
install_nvidia_drivers() {
    log_step "Verificação e instalação de drivers NVIDIA"

    if [[ "$GPU_VENDOR" != "nvidia" ]]; then
        log_data "GPU vendor=$GPU_VENDOR — passo de driver NVIDIA ignorado"
        log_result_ok "Não aplicável (GPU não-NVIDIA)"
        return 0
    fi

    info "GPU NVIDIA detectada. Verificando drivers e suporte CUDA..."
    log_action "Verificando presença e funcionamento do nvidia-smi"
    log_cmd "nvidia-smi"

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=name,driver_version,memory.total \
            --format=csv,noheader 2>/dev/null || true)
        log_output "nvidia-smi (nome, driver, VRAM)" "$smi_out"
        log_result_ok "Drivers NVIDIA funcionais — nenhuma instalação necessária"
        success "Drivers NVIDIA já instalados e funcionando"
        return 0
    fi

    log_result_warn "nvidia-smi ausente ou com falha"
    warn "Drivers NVIDIA não encontrados ou não funcionais."
    read -rp "Instalar drivers NVIDIA agora? [s/N]: " INSTALL_DRIVERS
    log_choice "Instalar drivers NVIDIA: '$INSTALL_DRIVERS'"

    if [[ ! "$INSTALL_DRIVERS" =~ ^[sS]$ ]]; then
        log_result_warn "Usuário optou por não instalar — Ollama utilizará somente CPU"
        warn "Pulando instalação de drivers. O Ollama usará CPU (mais lento)."
        return 0
    fi

    if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        log_action "Habilitando RPM Fusion e instalando akmod-nvidia + CUDA (Fedora)"
        log_cmd "dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda"
        info "Habilitando RPM Fusion e instalando drivers NVIDIA..."
        local fed_ver
        fed_ver=$(rpm -E %fedora)
        log_data "Versão Fedora: $fed_ver"
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fed_ver}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fed_ver}.noarch.rpm" \
            2>&1 | tee -a "$LOG_FILE" || true
        sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda 2>&1 | tee -a "$LOG_FILE"
        log_result_ok "Drivers instalados — reinicialização do sistema necessária"
        warn "Drivers NVIDIA instalados. ${BOLD}Reinicie o sistema antes de continuar.${NC}"
        exit 0

    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        log_action "Instalando drivers NVIDIA via apt (Debian/Ubuntu)"
        log_cmd "apt-get install nvidia-driver cuda-toolkit"
        info "Instalando drivers NVIDIA via apt..."
        sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
        sudo apt-get install -y nvidia-driver cuda-toolkit 2>&1 | tee -a "$LOG_FILE" || \
            sudo ubuntu-drivers install 2>&1 | tee -a "$LOG_FILE" || \
            { log_result_warn "Instalação automática falhou"; warn "Instale drivers manualmente."; }
        log_result_ok "Drivers instalados — reinicialização do sistema necessária"
        warn "Drivers instalados. ${BOLD}Reinicie o sistema antes de continuar.${NC}"
        exit 0
    fi
}

# ─── 8. Instalação do Ollama ──────────────────────────────────────────────────
install_ollama() {
    log_step "Instalação do Ollama"
    log_action "Verificando se o Ollama já está presente no PATH"
    log_cmd "which ollama && ollama --version"

    if command -v ollama &>/dev/null; then
        local ver path
        ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "desconhecida")
        path=$(which ollama)
        log_data "Caminho: $path"
        log_data "Versão: $ver"
        log_result_ok "Ollama já instalado — instalação ignorada (v$ver)"
        success "Ollama já instalado (versão: $ver)"
        return 0
    fi

    log_result_warn "Ollama não encontrado — iniciando instalação"
    info "Instalando Ollama..."
    log_action "Baixando e executando o instalador oficial via curl | sh"
    log_cmd "curl -fsSL https://ollama.com/install.sh | sh"
    run_live "Instalador oficial do Ollama" bash -c "curl -fsSL https://ollama.com/install.sh | sh"

    local ver path
    ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "desconhecida")
    path=$(which ollama 2>/dev/null || echo "não encontrado")
    log_data "Caminho pós-instalação: $path"
    log_data "Versão pós-instalação: $ver"
    log_result_ok "Ollama instalado com sucesso (v$ver)"
    success "Ollama instalado com sucesso"
}

# ─── 9. Inicialização do serviço ──────────────────────────────────────────────
start_ollama_service() {
    log_step "Inicialização do serviço Ollama"
    info "Verificando serviço do Ollama..."

    log_action "Consultando estado do serviço ollama no systemd"
    log_cmd "systemctl is-active ollama"

    if systemctl is-active --quiet ollama 2>/dev/null; then
        local status_out
        status_out=$(systemctl status ollama --no-pager -l 2>/dev/null | head -20 || true)
        log_output "systemctl status ollama" "$status_out"
        log_result_ok "Serviço já ativo (systemd)"
        success "Serviço Ollama já está rodando"
        return 0
    fi

    if systemctl is-enabled --quiet ollama 2>/dev/null; then
        log_action "Serviço habilitado mas parado — iniciando via systemd"
        log_cmd "systemctl start ollama"
        sudo systemctl start ollama
        sleep 2
        local status_out
        status_out=$(systemctl status ollama --no-pager -l 2>/dev/null | head -20 || true)
        log_output "systemctl status ollama" "$status_out"
        log_result_ok "Serviço iniciado via systemd"
        success "Serviço Ollama iniciado"
        return 0
    fi

    log_result_warn "Serviço systemd não encontrado — iniciando ollama serve manualmente"
    warn "Serviço systemd do Ollama não encontrado. Iniciando manualmente em background..."
    log_action "Executando 'ollama serve' em background"
    log_cmd "nohup ollama serve >> LOG_FILE 2>&1 &"
    nohup ollama serve >> "$LOG_FILE" 2>&1 &
    local pid=$!
    sleep 3
    log_data "PID do processo: $pid"

    if kill -0 "$pid" 2>/dev/null; then
        log_result_ok "Ollama rodando em background (PID: $pid)"
        success "Ollama rodando em background (PID: $pid)"
    else
        log_result_err "Processo terminou inesperadamente após inicialização"
        die "Falha ao iniciar o Ollama. Verifique o log: $LOG_FILE"
    fi
}

# ─── 10. Configuração de rede ─────────────────────────────────────────────────
configure_network_access() {
    log_step "Configuração de acesso de rede"
    log_action "Consultando usuário sobre exposição de rede"
    echo ""
    read -rp "Expor Ollama na rede local (útil para devcontainers/VMs)? [s/N]: " EXPOSE_NETWORK
    log_choice "Expor Ollama na rede: '$EXPOSE_NETWORK'"

    if [[ ! "$EXPOSE_NETWORK" =~ ^[sS]$ ]]; then
        log_data "Ollama permanecerá em 127.0.0.1:11434 (padrão)"
        log_result_ok "Configuração de rede padrão mantida"
        return 0
    fi

    info "Configurando Ollama para escutar em 0.0.0.0:11434..."

    if systemctl list-unit-files ollama.service &>/dev/null; then
        log_action "Criando override de serviço systemd com OLLAMA_HOST=0.0.0.0"
        log_cmd "systemctl edit ollama → Environment=OLLAMA_HOST=0.0.0.0"
        local override_path="/etc/systemd/system/ollama.service.d/network.conf"
        sudo mkdir -p "$(dirname "$override_path")"
        sudo tee "$override_path" > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
        log_data "Override criado em: $override_path"
        log_cmd "systemctl daemon-reload && systemctl restart ollama"
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
        log_data "OLLAMA_HOST=0.0.0.0 ativo"
        log_result_ok "Ollama exposto em 0.0.0.0:11434"
        success "Ollama exposto em 0.0.0.0:11434"
    else
        log_result_warn "Unidade systemd não encontrada — override não aplicado"
        warn "Serviço systemd não encontrado. Defina OLLAMA_HOST=0.0.0.0 manualmente."
    fi
}

# ─── 11. Download do modelo ───────────────────────────────────────────────────
pull_model() {
    log_step "Download do modelo $OLLAMA_MODEL"
    info "Baixando modelo ${BOLD}${OLLAMA_MODEL}${NC}..."
    log_action "Iniciando pull do modelo via Ollama"
    log_cmd "ollama pull $OLLAMA_MODEL"
    echo ""

    if ! run_live "ollama pull $OLLAMA_MODEL" ollama pull "$OLLAMA_MODEL"; then
        log_result_err "Falha no download de $OLLAMA_MODEL"
        die "Falha ao baixar o modelo. Tente manualmente: ollama pull $OLLAMA_MODEL"
    fi

    log_action "Verificando modelo na lista local"
    log_cmd "ollama list"
    local list_out
    list_out=$(ollama list 2>/dev/null || true)
    log_output "ollama list" "$list_out"
    log_result_ok "Modelo $OLLAMA_MODEL disponível localmente"
    success "Modelo ${OLLAMA_MODEL} baixado com sucesso"
}

# ─── 12. Teste do modelo ──────────────────────────────────────────────────────
test_model() {
    log_step "Teste de funcionamento do modelo"
    info "Testando o modelo com uma pergunta simples..."
    local prompt="Responda em uma linha: qual linguagem de programação você recomendaria para iniciantes e por quê?"
    log_action "Enviando prompt de teste ao modelo"
    log_cmd "ollama run $OLLAMA_MODEL '<prompt>'"
    log_data "Prompt: $prompt"
    echo ""

    local response="" exit_code=0
    response=$(ollama run "$OLLAMA_MODEL" "$prompt" 2>/dev/null) || exit_code=$?

    log_output "Resposta do modelo" "$response"

    if [[ $exit_code -eq 0 ]] && [[ -n "$response" ]]; then
        log_result_ok "Modelo respondeu ao teste (exit $exit_code)"
        success "Modelo respondeu com sucesso:"
        echo -e "  ${BOLD}${response}${NC}"
    else
        log_result_warn "Modelo não respondeu (exit $exit_code) — pode ser problema de timeout ou memória"
        warn "Modelo não respondeu ao teste. Verifique com: ollama run $OLLAMA_MODEL"
    fi
}

# ─── 13. Configuração do Continue.dev ────────────────────────────────────────
generate_continue_config() {
    log_step "Geração de configuração do Continue.dev"
    local config_dir="$HOME/.continue"
    local config_file="$config_dir/config.json"
    local autocomplete_model="deepseek-r1:1.5b"

    echo ""
    read -rp "Gerar configuração do Continue.dev para este modelo? [S/n]: " GEN_CONTINUE
    log_choice "Gerar config Continue.dev: '$GEN_CONTINUE'"

    if [[ "$GEN_CONTINUE" =~ ^[nN]$ ]]; then
        log_data "Configuração do Continue.dev ignorada pelo usuário"
        log_result_ok "Passo ignorado pelo usuário"
        return 0
    fi

    log_action "Criando diretório $config_dir"
    log_cmd "mkdir -p $config_dir"
    mkdir -p "$config_dir"
    log_data "Modelo principal: $OLLAMA_MODEL"
    log_data "Modelo de autocomplete: $autocomplete_model"
    log_data "Arquivo destino: $config_file"

    log_action "Escrevendo config.json"
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
    log_output "Conteúdo do config.json gerado" "$(cat "$config_file")"

    if [[ "$OLLAMA_MODEL" != "$autocomplete_model" ]]; then
        log_action "Iniciando download do modelo de autocomplete em background"
        log_cmd "ollama pull $autocomplete_model (background)"
        info "Baixando modelo leve ${autocomplete_model} para autocomplete em background..."
        ollama pull "$autocomplete_model" >> "$LOG_FILE" 2>&1 &
        log_data "PID do download de autocomplete: $!"
    fi

    log_result_ok "config.json salvo em $config_file"
    success "Configuração do Continue.dev salva em: $config_file"
}

# ─── Resumo final ─────────────────────────────────────────────────────────────
print_summary() {
    {
        printf '\n%s\n' "================================================================================"
        printf '  FIM DO SETUP\n'
        printf '  Término:          %s\n' "$(_ts)"
        printf '  Modelo instalado: %s\n' "$OLLAMA_MODEL"
        printf '  Passos:           %d/%d concluídos\n' "$CURRENT_STEP" "$TOTAL_STEPS"
        printf '%s\n' "================================================================================"
    } >> "$LOG_FILE"

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  Configuração concluída com sucesso!${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Modelo ativo:${NC}     $OLLAMA_MODEL"
    echo -e "  ${BOLD}Endpoint:${NC}         http://localhost:11434"
    echo -e "  ${BOLD}Log completo:${NC}     $LOG_FILE"
    echo ""
    echo -e "${BOLD}Próximos passos:${NC}"
    echo "  1. Instale a extensão Continue.dev ou Cline no VS Code"
    echo "  2. No Continue: ícone de engrenagem → config.json já configurado"
    echo "  3. No Cline: Settings → Provider → Ollama → http://localhost:11434"
    echo ""
    echo -e "${BOLD}Comandos úteis:${NC}"
    echo "  ollama list                        # lista modelos baixados"
    echo "  ollama run $OLLAMA_MODEL   # chat direto no terminal"
    echo "  sudo systemctl status ollama       # status do serviço"
    echo "  sudo journalctl -u ollama -f       # logs em tempo real"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}   Setup DeepSeek Local via Ollama — Linux${NC}"
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
