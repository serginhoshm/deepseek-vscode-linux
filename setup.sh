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
die()     { error "$*"; exit 1; }

# ─── Verificações iniciais ─────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -eq 0 ]]; then
        die "Não execute este script como root. Use seu usuário normal (sudo será solicitado quando necessário)."
    fi
}

check_internet() {
    info "Verificando conectividade com a internet..."
    if ! curl -fsS --max-time 5 https://ollama.com > /dev/null 2>&1; then
        die "Sem acesso à internet. Verifique sua conexão e tente novamente."
    fi
    success "Internet OK"
}

# ─── Detecção de distribuição ─────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
    else
        die "Não foi possível detectar a distribuição Linux."
    fi

    if echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qi "fedora"; then
        DISTRO_FAMILY="fedora"
    elif echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "(debian|ubuntu)"; then
        DISTRO_FAMILY="debian"
    else
        warn "Distribuição '$DISTRO_ID' não testada. Tentando como Debian-compatível."
        DISTRO_FAMILY="debian"
    fi

    info "Distribuição detectada: ${BOLD}${PRETTY_NAME:-$DISTRO_ID}${NC} (família: $DISTRO_FAMILY)"
}

# ─── Detecção de GPU ──────────────────────────────────────────────────────────
detect_gpu() {
    GPU_VENDOR="none"
    GPU_NAME="Nenhuma GPU dedicada detectada"

    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qi nvidia; then
            GPU_VENDOR="nvidia"
            GPU_NAME=$(lspci 2>/dev/null | grep -i nvidia | grep -i vga | head -1 | sed 's/.*: //')
        elif lspci 2>/dev/null | grep -qiE "(amd|radeon)"; then
            GPU_VENDOR="amd"
            GPU_NAME=$(lspci 2>/dev/null | grep -iE "(amd|radeon)" | grep -i vga | head -1 | sed 's/.*: //')
        fi
    fi

    info "GPU detectada: ${BOLD}${GPU_NAME}${NC}"
}

# ─── Detecção de RAM disponível ───────────────────────────────────────────────
detect_ram() {
    TOTAL_RAM_GB=$(awk '/MemTotal/ { printf "%.0f", $2/1024/1024 }' /proc/meminfo)
    info "RAM total: ${BOLD}${TOTAL_RAM_GB} GB${NC}"
}

# ─── Sugestão de modelo ───────────────────────────────────────────────────────
suggest_model() {
    info "Analisando hardware para sugerir o modelo ideal..."

    # Tenta obter VRAM via nvidia-smi se disponível
    VRAM_MB=0
    if [[ "$GPU_VENDOR" == "nvidia" ]] && command -v nvidia-smi &>/dev/null; then
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' || echo 0)
    fi
    VRAM_GB=$(( VRAM_MB / 1024 ))

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
    case "$MODEL_CHOICE" in
        1) OLLAMA_MODEL="deepseek-r1:1.5b" ;;
        2) OLLAMA_MODEL="deepseek-r1:7b" ;;
        3) OLLAMA_MODEL="deepseek-r1:14b" ;;
        4) OLLAMA_MODEL="deepseek-r1:32b" ;;
        *) OLLAMA_MODEL="$SUGGESTED_MODEL" ;;
    esac

    success "Modelo selecionado: ${BOLD}${OLLAMA_MODEL}${NC}"
}

# ─── Instalação de drivers NVIDIA ────────────────────────────────────────────
install_nvidia_drivers() {
    if [[ "$GPU_VENDOR" != "nvidia" ]]; then
        return 0
    fi

    info "GPU NVIDIA detectada. Verificando drivers e suporte CUDA..."

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        success "Drivers NVIDIA já instalados e funcionando"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null | \
            while IFS=, read -r name driver vram; do
                info "  GPU: $name | Driver: $driver | VRAM:$vram"
            done
        return 0
    fi

    warn "Drivers NVIDIA não encontrados ou não funcionais."
    read -rp "Instalar drivers NVIDIA agora? [s/N]: " INSTALL_DRIVERS
    if [[ ! "$INSTALL_DRIVERS" =~ ^[sS]$ ]]; then
        warn "Pulando instalação de drivers. O Ollama usará CPU (mais lento)."
        return 0
    fi

    if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        info "Habilitando RPM Fusion e instalando drivers NVIDIA..."
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" 2>/dev/null || true
        sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
        warn "Drivers NVIDIA instalados. ${BOLD}Reinicie o sistema antes de continuar.${NC}"
        exit 0
    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "Instalando drivers NVIDIA via apt..."
        sudo apt-get update -qq
        sudo apt-get install -y nvidia-driver cuda-toolkit 2>/dev/null || \
            sudo ubuntu-drivers install 2>/dev/null || \
            warn "Instalação automática falhou. Instale os drivers manualmente via 'Additional Drivers'."
        warn "Drivers instalados. ${BOLD}Reinicie o sistema antes de continuar.${NC}"
        exit 0
    fi
}

# ─── Instalação do Ollama ─────────────────────────────────────────────────────
install_ollama() {
    if command -v ollama &>/dev/null; then
        OLLAMA_VERSION=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "desconhecida")
        success "Ollama já instalado (versão: $OLLAMA_VERSION)"
        return 0
    fi

    info "Instalando Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    success "Ollama instalado com sucesso"
}

# ─── Inicialização do serviço Ollama ──────────────────────────────────────────
start_ollama_service() {
    info "Verificando serviço do Ollama..."

    # Tenta via systemd primeiro
    if systemctl is-active --quiet ollama 2>/dev/null; then
        success "Serviço Ollama já está rodando"
        return 0
    fi

    if systemctl is-enabled --quiet ollama 2>/dev/null; then
        info "Iniciando serviço Ollama via systemd..."
        sudo systemctl start ollama
        sleep 2
        success "Serviço Ollama iniciado"
        return 0
    fi

    # Fallback: inicia como processo em background
    warn "Serviço systemd do Ollama não encontrado. Iniciando manualmente em background..."
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    OLLAMA_PID=$!
    sleep 3

    if kill -0 "$OLLAMA_PID" 2>/dev/null; then
        success "Ollama rodando em background (PID: $OLLAMA_PID)"
    else
        die "Falha ao iniciar o Ollama. Verifique o log em /tmp/ollama.log"
    fi
}

# ─── Configuração de rede (opcional) ─────────────────────────────────────────
configure_network_access() {
    echo ""
    read -rp "Expor Ollama na rede local (útil para devcontainers/VMs)? [s/N]: " EXPOSE_NETWORK
    if [[ ! "$EXPOSE_NETWORK" =~ ^[sS]$ ]]; then
        return 0
    fi

    info "Configurando Ollama para escutar em 0.0.0.0:11434..."

    if systemctl list-unit-files ollama.service &>/dev/null; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        sudo tee /etc/systemd/system/ollama.service.d/network.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
        success "Ollama exposto em 0.0.0.0:11434"
    else
        warn "Serviço systemd não encontrado. Defina OLLAMA_HOST=0.0.0.0 manualmente antes de iniciar o Ollama."
    fi
}

# ─── Download do modelo ───────────────────────────────────────────────────────
pull_model() {
    info "Baixando modelo ${BOLD}${OLLAMA_MODEL}${NC}..."
    info "Isso pode demorar dependendo da sua conexão. Aguarde..."
    echo ""

    if ollama pull "$OLLAMA_MODEL"; then
        success "Modelo ${OLLAMA_MODEL} baixado com sucesso"
    else
        die "Falha ao baixar o modelo. Verifique sua conexão e tente: ollama pull $OLLAMA_MODEL"
    fi
}

# ─── Teste do modelo ──────────────────────────────────────────────────────────
test_model() {
    info "Testando o modelo com uma pergunta simples..."
    echo ""

    RESPONSE=$(ollama run "$OLLAMA_MODEL" "Responda em uma linha: qual linguagem de programação você recomendaria para iniciantes e por quê?" 2>/dev/null || echo "")

    if [[ -n "$RESPONSE" ]]; then
        success "Modelo respondeu com sucesso:"
        echo -e "  ${BOLD}${RESPONSE}${NC}"
    else
        warn "Modelo não respondeu ao teste. Verifique com: ollama run $OLLAMA_MODEL"
    fi
}

# ─── Geração do config do Continue.dev ───────────────────────────────────────
generate_continue_config() {
    CONTINUE_CONFIG_DIR="$HOME/.continue"
    CONTINUE_CONFIG_FILE="$CONTINUE_CONFIG_DIR/config.json"

    echo ""
    read -rp "Gerar configuração do Continue.dev para este modelo? [S/n]: " GEN_CONTINUE
    if [[ "$GEN_CONTINUE" =~ ^[nN]$ ]]; then
        return 0
    fi

    mkdir -p "$CONTINUE_CONFIG_DIR"

    # Determina modelo de autocomplete (sempre o mais leve)
    AUTOCOMPLETE_MODEL="deepseek-r1:1.5b"

    # Se o modelo principal já é o 1.5b, garante que está baixado também
    if [[ "$OLLAMA_MODEL" == "deepseek-r1:1.5b" ]]; then
        AUTOCOMPLETE_MODEL="deepseek-r1:1.5b"
    else
        info "Baixando modelo leve ${AUTOCOMPLETE_MODEL} para autocomplete..."
        ollama pull "$AUTOCOMPLETE_MODEL" &>/dev/null &
        AUTOCOMPLETE_PID=$!
    fi

    cat > "$CONTINUE_CONFIG_FILE" <<EOF
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
    "model": "${AUTOCOMPLETE_MODEL}"
  },
  "allowAnonymousTelemetry": false
}
EOF

    success "Configuração do Continue.dev salva em: $CONTINUE_CONFIG_FILE"

    if [[ -n "${AUTOCOMPLETE_PID:-}" ]]; then
        info "Aguardando download do modelo de autocomplete..."
        wait "$AUTOCOMPLETE_PID" 2>/dev/null && success "Modelo de autocomplete pronto" || \
            warn "Download do autocomplete falhou. Execute manualmente: ollama pull $AUTOCOMPLETE_MODEL"
    fi
}

# ─── Resumo final ─────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  Configuração concluída com sucesso!${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Modelo ativo:${NC}     $OLLAMA_MODEL"
    echo -e "  ${BOLD}Endpoint:${NC}         http://localhost:11434"
    echo ""
    echo -e "${BOLD}Próximos passos:${NC}"
    echo "  1. Instale a extensão Continue.dev ou Cline no VS Code"
    echo "  2. No Continue: ícone de engrenagem → config.json já configurado"
    echo "  3. No Cline: Settings → Provider → Ollama → Base URL → http://localhost:11434"
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
