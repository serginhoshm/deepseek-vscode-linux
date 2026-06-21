# DeepSeek no VS Code — Guia de Configuração para Linux

Guia completo para integrar modelos DeepSeek ao Visual Studio Code em sistemas **Fedora** e **Debian/Ubuntu/Zorin OS**, tanto via API cloud quanto localmente via Ollama.

---

## Início Rápido

Para configurar tudo automaticamente, execute o script de setup incluído neste repositório:

```bash
bash setup.sh
```

O script detecta sua distro, GPU e RAM, sugere o modelo ideal, instala o Ollama, baixa o modelo escolhido e gera a configuração do Continue.dev automaticamente. Siga as instruções abaixo para configuração manual ou para entender cada etapa em detalhe.

---

## Índice

- [Visão Geral](#visão-geral)
- [Comparativo: Cloud vs. Local](#comparativo-cloud-vs-local)
- [Extensões Recomendadas](#extensões-recomendadas)
- [Instalação Local com Ollama](#instalação-local-com-ollama)
- [Configuração das Extensões](#configuração-das-extensões)
- [Troubleshooting](#troubleshooting)
- [Referências](#referências)

---

## Visão Geral

O DeepSeek oferece dois modelos principais:

- **DeepSeek-R1** — modelo de raciocínio avançado (reasoning), ideal para tarefas complexas de lógica e código
- **DeepSeek-V3** — modelo Mixture-of-Experts de alto throughput, excelente para geração de código e chat geral

Ambos podem ser usados via API cloud ou localmente de forma totalmente offline.

---

## Comparativo: Cloud vs. Local

| Característica | API Cloud | Local via Ollama |
| :--- | :--- | :--- |
| Overhead de compute | Nenhum (servidores remotos) | Alto (GPU/CPU/RAM local) |
| Privacidade dos dados | Sujeito aos Termos de Serviço | 100% air-gapped / privado |
| Modelos disponíveis | V3 (671B) e R1 (671B) completos | Versões quantizadas (1.5B a 70B) |
| Custo | Pay-per-token (muito barato) | Gratuito (apenas energia) |
| Necessidade de internet | Conexão contínua | Apenas no download inicial |

---

## Extensões Recomendadas

### Continue.dev

A principal extensão open-source para assistência de código com LLMs. Suporta autocomplete inline (Tab), chat com contexto do codebase (`@codebase`) e refatoração contextual.

**Instalação:** busque por `Continue` no marketplace do VS Code ou acesse [continue.dev](https://continue.dev).

### Cline / Roo Code

Agente autônomo que vai além do chat: lê e escreve arquivos diretamente no workspace, executa comandos no terminal e itera sobre erros de compilação/lint automaticamente.

- **Cline** — versão original
- **Roo Code** — fork ativamente mantido com funcionalidades adicionais

Ideal para refatorações complexas em múltiplos arquivos, geração de testes e scaffolding de projetos.

### Extensões compatíveis com OpenAI

A API do DeepSeek é 100% compatível com o formato `v1/chat/completions` da OpenAI. Qualquer extensão que aceite uma base URL customizada funciona, como *Genie AI*, *Llama Coder* e similares.

---

## Instalação Local com Ollama

### 1. Instalar o Ollama

#### Fedora (Workstation e variantes Atomic)

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

> Em sistemas Atomic (Silverblue, Kinoite), prefira rodar dentro de um container ou via binário gerenciado pelo systemd do usuário.

**Aceleração por GPU Nvidia no Fedora** — habilite o RPM Fusion e instale o CUDA:

```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda -y
```

#### Debian / Ubuntu / Zorin OS

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Verifique se o serviço está rodando:

```bash
sudo systemctl status ollama
```

---

### 2. Escolher e baixar o modelo

Selecione o tamanho conforme o hardware disponível:

| Modelo | Espaço em disco | Hardware recomendado |
| :--- | :--- | :--- |
| `deepseek-r1:1.5b` | ~1.1 GB | Laptops e hardware leve |
| `deepseek-r1:7b` | ~4.7 GB | 16 GB RAM / 8 GB VRAM (recomendado) |
| `deepseek-r1:14b` | ~9.0 GB | GPUs mid-to-high tier |
| `deepseek-r1:32b` / `70b` | 20 GB+ | Setups enterprise com muita VRAM |

Baixar o modelo escolhido:

```bash
ollama pull deepseek-r1:7b
```

Testar no terminal:

```bash
ollama run deepseek-r1:7b
```

---

## Configuração das Extensões

### Continue.dev

Abra o `config.json` do Continue (ícone de engrenagem no canto inferior direito do painel).

#### Com Ollama (local/offline)

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

> Usar o modelo 1.5B para autocomplete mantém a latência baixa enquanto o 7B fica disponível para o chat.

#### Com a API Cloud do DeepSeek

Gere sua chave em [platform.deepseek.com](https://platform.deepseek.com/) e configure:

```json
{
  "models": [
    {
      "title": "DeepSeek-V3 (Cloud)",
      "provider": "deepseek",
      "model": "deepseek-chat",
      "apiKey": "sua-chave-aqui"
    },
    {
      "title": "DeepSeek-R1 (Cloud Reasoning)",
      "provider": "deepseek",
      "model": "deepseek-reasoner",
      "apiKey": "sua-chave-aqui"
    }
  ]
}
```

---

### Cline / Roo Code

1. Abra o painel do **Cline** no VS Code
2. Clique no ícone de engrenagem (Settings)
3. Em **Provider**, selecione conforme o modo de uso:

**Local via Ollama:**
- Base URL: `http://localhost:11434`
- Model: `deepseek-r1:7b` (ou o tamanho baixado)

**API Cloud:**
- Provider: `DeepSeek`
- API Key: sua chave do portal DeepSeek
- Model: `deepseek-chat` (V3) ou `deepseek-reasoner` (R1)

---

## Troubleshooting

### Geração de tokens muito lenta

**Causa:** Ollama está rodando apenas na CPU, sem detectar a GPU.

**Solução:** Verifique se os drivers CUDA/ROCm estão corretamente instalados:

```bash
sudo journalctl -u ollama --no-pager | grep -iE "(cuda|rocm|gpu)"
```

Certifique-se de que seu usuário pertence aos grupos `video` e `render`:

```bash
sudo usermod -aG video,render $USER
```

---

### Conflito de porta ou acesso remoto (devcontainers/VMs)

Por padrão, o Ollama escuta apenas em `127.0.0.1:11434`. Para expor em rede (útil em devcontainers ou VMs):

1. Edite o serviço systemd:

```bash
sudo systemctl edit ollama
```

2. Adicione a variável de ambiente:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```

3. Recarregue e reinicie:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## Referências

- [Documentação do Ollama](https://ollama.com)
- [Continue.dev](https://continue.dev)
- [DeepSeek Developer Portal](https://platform.deepseek.com/)
- [Repositório do Cline](https://github.com/cline/cline)
- [Repositório do Roo Code](https://github.com/RooVetGit/Roo-Code)
