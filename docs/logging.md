# Manual do Sistema de Logs — setup.sh

Este documento descreve o funcionamento, a estrutura e as convenções do sistema de logging implementado no `setup.sh`.

---

## Índice

- [Visão Geral](#visão-geral)
- [Localização e Nomenclatura dos Arquivos](#localização-e-nomenclatura-dos-arquivos)
- [Estrutura do Arquivo de Log](#estrutura-do-arquivo-de-log)
- [Funções de Logging](#funções-de-logging)
- [Funções de Execução com Log](#funções-de-execução-com-log)
- [Tipos de Registro](#tipos-de-registro)
- [Exemplo de Log Completo](#exemplo-de-log-completo)
- [Boas Práticas para Manutenção](#boas-práticas-para-manutenção)

---

## Visão Geral

O sistema de logs foi projetado para registrar com precisão cada etapa da execução do `setup.sh`, permitindo:

- **Rastreabilidade total** — cada ação, comando e resultado é documentado com timestamp
- **Diagnóstico facilitado** — em caso de falha, o log indica exatamente em qual passo e comando o erro ocorreu
- **Auditoria de escolhas** — as respostas do usuário nos prompts interativos são registradas
- **Separação de contextos** — cada execução gera um arquivo de log independente e identificável

Os logs são gerados exclusivamente em tempo de execução e **nunca são versionados** (a pasta `logs/` está no `.gitignore`).

---

## Localização e Nomenclatura dos Arquivos

### Pasta

```
<raiz do repositório>/logs/
```

A pasta `logs/` é criada automaticamente pelo script na primeira execução, caso não exista.

### Nome do arquivo

```
YYYY-MM-DD-HH-MM-SS-<usuarioLinux>.log
```

| Componente | Descrição | Exemplo |
| :--- | :--- | :--- |
| `YYYY` | Ano com 4 dígitos | `2026` |
| `MM` | Mês com 2 dígitos | `06` |
| `DD` | Dia com 2 dígitos | `21` |
| `HH` | Hora (24h) com 2 dígitos | `14` |
| `MM` | Minutos com 2 dígitos | `30` |
| `SS` | Segundos com 2 dígitos | `05` |
| `<usuarioLinux>` | Resultado de `whoami` no momento da execução | `smarchiori` |

**Exemplo de nome completo:**

```
2026-06-21-14-30-05-smarchiori.log
```

Cada execução do script produz um arquivo separado, mesmo que sejam executadas no mesmo dia. Isso garante que execuções consecutivas não se sobreponham.

---

## Estrutura do Arquivo de Log

O arquivo de log é dividido em três partes:

### 1. Cabeçalho

Gerado uma única vez no início da execução pela função `init_log`. Contém metadados do ambiente:

```
================================================================================
  DEEPSEEK SETUP LOG
  Início:          2026-06-21 14:30:05
  Usuário Linux:   smarchiori
  Hostname:        minha-maquina
  Sistema:         Linux x86_64 6.x.x
  Kernel:          6.x.x-xxx.fc44.x86_64
  Total de passos: 13
================================================================================
```

### 2. Passos

Cada função principal do script corresponde a um passo numerado. Os passos são delimitados por separadores visuais e identificados por número sequencial e nome:

```
────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:06] PASSO 3/13: Detecção da distribuição Linux
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:06] AÇÃO:      Lendo /etc/os-release
  [2026-06-21 14:30:06] DADO:      ID=fedora
  [2026-06-21 14:30:06] DADO:      PRETTY_NAME=Fedora Linux 44 (Cinnamon)
  [2026-06-21 14:30:06] RESULTADO: OK    — Fedora Linux 44 — família: fedora
```

### 3. Rodapé

Gerado ao final da execução bem-sucedida pela função `print_summary`:

```
================================================================================
  FIM DO SETUP
  Término:          2026-06-21 14:52:18
  Modelo instalado: deepseek-r1:7b
  Passos:           13/13 concluídos
================================================================================
```

---

## Funções de Logging

Todas as funções de log escrevem **exclusivamente no arquivo de log** (não exibem nada no terminal). O formato geral de cada linha é:

```
  [YYYY-MM-DD HH:MM:SS] TIPO:      Conteúdo
```

A indentação de dois espaços e o alinhamento dos tipos facilitam a leitura visual do log.

---

### `log_step "<nome do passo>"`

Incrementa o contador de passos e registra o separador de seção.

**Quando usar:** no início de cada função principal do script, representando uma etapa de alto nível.

**Efeito no log:**
```
────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:10] PASSO 4/13: Detecção de GPU
────────────────────────────────────────────────────────────────────────────────
```

---

### `log_action "<descrição>"`

Descreve em linguagem natural o que está prestes a ser feito. Deve preceder `log_cmd` quando um comando será executado.

**Quando usar:** antes de qualquer ação relevante — verificação, leitura de arquivo, chamada a ferramenta externa.

**Efeito no log:**
```
  [2026-06-21 14:30:10] AÇÃO:      Listando dispositivos PCI via lspci
```

---

### `log_cmd "<comando>"`

Registra o comando exato que será ou foi executado, incluindo argumentos.

**Quando usar:** sempre que um comando externo for invocado (não use para código shell interno simples como atribuições).

**Efeito no log:**
```
  [2026-06-21 14:30:10] COMANDO:   lspci
```

> Para comandos construídos dinamicamente, registre a forma expandida:
> ```bash
> log_cmd "ollama pull $OLLAMA_MODEL"
> ```

---

### `log_data "<chave>: <valor>"` ou `log_data "<texto livre>"`

Registra um dado coletado ou uma variável relevante para o contexto do passo.

**Quando usar:** após coletar informações do sistema (RAM, GPU, versão de software, caminho de arquivo, etc.).

**Efeito no log:**
```
  [2026-06-21 14:30:11] DADO:      GPU_VENDOR=nvidia
  [2026-06-21 14:30:11] DADO:      GPU_NAME=NVIDIA GeForce GTX 1650 Mobile
  [2026-06-21 14:30:11] DADO:      VRAM total: 4096 MB
```

---

### `log_choice "<descrição da escolha>"`

Registra a resposta do usuário a um prompt interativo (`read -rp`).

**Quando usar:** imediatamente após cada `read` que coleta input do usuário.

**Efeito no log:**
```
  [2026-06-21 14:30:45] ESCOLHA:   Entrada do usuário: '2'
  [2026-06-21 14:30:45] ESCOLHA:   Modelo final: deepseek-r1:7b
```

---

### `log_output "<rótulo>" "<conteúdo>"`

Registra a saída de um comando externo, indentada para distinção visual. Não faz nada se o conteúdo for vazio.

**Quando usar:** após capturar a saída de ferramentas como `lspci`, `nvidia-smi`, `ollama list`, `systemctl status`, etc.

**Efeito no log:**
```
  [2026-06-21 14:30:11] Dispositivos VGA/Display detectados:
      00:02.0 VGA compatible controller: Intel UHD Graphics
      01:00.0 VGA compatible controller: NVIDIA GeForce GTX 1650 Mobile
```

---

### `log_result_ok "<mensagem>"`
### `log_result_warn "<mensagem>"`
### `log_result_err "<mensagem>"`

Registram o resultado de um passo ou ação, com três níveis de severidade:

| Função | Prefixo no log | Significado |
| :--- | :--- | :--- |
| `log_result_ok` | `RESULTADO: OK    —` | Ação concluída com sucesso |
| `log_result_warn` | `RESULTADO: AVISO —` | Ação concluída com ressalvas ou comportamento alternativo |
| `log_result_err` | `RESULTADO: ERRO  —` | Ação falhou |

**Quando usar:** ao final de cada ação ou ao final de cada função de passo, para fechar o contexto com um resultado claro.

**Efeito no log:**
```
  [2026-06-21 14:30:11] RESULTADO: OK    — GPU: NVIDIA GeForce GTX 1650 Mobile (vendor: nvidia)
  [2026-06-21 14:30:20] RESULTADO: AVISO — nvidia-smi ausente ou com falha
  [2026-06-21 14:30:55] RESULTADO: ERRO  — exit 1
```

> `log_result_err` também é chamado automaticamente pela função `die()` antes de encerrar o script.

---

## Funções de Execução com Log

Estas funções combinam execução de comando com registro automático no log. São a forma preferida de chamar ferramentas externas no script.

---

### `run_capture "<descrição>" <comando> [args...]`

Executa um comando capturando toda a sua saída (stdout + stderr). A saída é registrada no log e também ecoada no terminal. Ideal para comandos rápidos onde o resultado completo é necessário antes de continuar.

**Comportamento:**
1. Registra `AÇÃO` e `COMANDO` no log
2. Executa o comando e captura a saída em memória
3. Registra a saída no log via `log_output`
4. Registra `RESULTADO` com o exit code
5. Ecoa a saída no terminal
6. Retorna o exit code original do comando

**Quando usar:** verificações de sistema, consultas de versão, leitura de configurações — qualquer comando que termine rapidamente e cujo output completo seja relevante para o log.

**Exemplo de uso:**
```bash
run_capture "Verificando versão do Ollama" ollama --version
```

**Limitação:** não adequado para comandos de longa duração, pois o terminal fica em silêncio enquanto aguarda o término.

---

### `run_live "<descrição>" <comando> [args...]`

Executa um comando exibindo a saída em tempo real no terminal (via `tee`) e, ao final, salva uma cópia limpa (sem códigos ANSI) no log. Ideal para operações demoradas onde o feedback ao vivo é importante.

**Comportamento:**
1. Registra `AÇÃO` e `COMANDO` no log
2. Executa o comando com saída ao vivo via `tee` para um arquivo temporário
3. Ao concluir, processa o arquivo temporário removendo sequências ANSI (`\x1b[...m`) e carriage returns (`\r`)
4. Appenda a saída limpa ao log
5. Remove o arquivo temporário
6. Registra `RESULTADO` com o exit code
7. Retorna o exit code original do comando

**Quando usar:** instalações (`curl | sh`), downloads de modelos (`ollama pull`), operações de gerenciador de pacotes (`dnf`, `apt-get`) — qualquer comando com duração de segundos a minutos.

**Exemplo de uso:**
```bash
run_live "Download do modelo deepseek-r1:7b" ollama pull deepseek-r1:7b
```

**Nota sobre códigos ANSI:** a remoção de ANSI é necessária porque barras de progresso e cores poluiriam o log com sequências de escape ilegíveis. O terminal continua recebendo a saída colorida normalmente.

---

## Tipos de Registro

Resumo de todos os tipos de linha que podem aparecer no log e seu significado:

| Tipo | Função responsável | Propósito |
| :--- | :--- | :--- |
| `PASSO N/T:` | `log_step` | Delimita uma etapa de alto nível |
| `AÇÃO:` | `log_action` | Descreve a intenção da próxima operação |
| `COMANDO:` | `log_cmd` | Registra o comando exato a ser executado |
| `DADO:` | `log_data` | Armazena valor coletado do sistema ou variável |
| `ESCOLHA:` | `log_choice` | Registra input interativo do usuário |
| `<rótulo>:` | `log_output` | Saída bruta de uma ferramenta externa |
| `RESULTADO: OK` | `log_result_ok` | Ação concluída com sucesso |
| `RESULTADO: AVISO` | `log_result_warn` | Ação concluída com comportamento alternativo |
| `RESULTADO: ERRO` | `log_result_err` | Ação falhou |

---

## Exemplo de Log Completo

Trecho representativo de um log real gerado pelo script:

```
================================================================================
  DEEPSEEK SETUP LOG
  Início:          2026-06-21 14:30:05
  Usuário Linux:   smarchiori
  Hostname:        notebook-dev
  Sistema:         Linux x86_64
  Kernel:          7.0.12-201.fc44.x86_64
  Total de passos: 13
================================================================================

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:05] PASSO 1/13: Verificação de privilégios
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:05] AÇÃO:      Checando se o script está rodando como root (EUID=1000)
  [2026-06-21 14:30:05] DADO:      Usuário: smarchiori | EUID: 1000
  [2026-06-21 14:30:05] RESULTADO: OK    — Usuário não-root confirmado

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:05] PASSO 2/13: Verificação de conectividade com a internet
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:05] AÇÃO:      Testando acesso HTTP a https://ollama.com (timeout: 5s)
  [2026-06-21 14:30:05] COMANDO:   curl -fsS --max-time 5 https://ollama.com
  [2026-06-21 14:30:06] RESULTADO: OK    — Resposta recebida de https://ollama.com

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:06] PASSO 4/13: Detecção de GPU
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:06] AÇÃO:      Listando dispositivos PCI via lspci
  [2026-06-21 14:30:06] COMANDO:   lspci
  [2026-06-21 14:30:06] Dispositivos VGA/Display detectados:
      00:02.0 VGA compatible controller: Intel UHD Graphics (rev 05)
      01:00.0 VGA compatible controller: NVIDIA GeForce GTX 1650 Mobile (rev a1)
  [2026-06-21 14:30:06] DADO:      GPU_VENDOR=nvidia
  [2026-06-21 14:30:06] DADO:      GPU_NAME=NVIDIA GeForce GTX 1650 Mobile (rev a1)
  [2026-06-21 14:30:06] AÇÃO:      Consultando detalhes da GPU via nvidia-smi
  [2026-06-21 14:30:06] COMANDO:   nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader
  [2026-06-21 14:30:06] nvidia-smi:
      GeForce GTX 1650, 535.183.01, 4096 MiB, 3800 MiB
  [2026-06-21 14:30:06] RESULTADO: OK    — GPU: NVIDIA GeForce GTX 1650 Mobile (vendor: nvidia)

────────────────────────────────────────────────────────────────────────────────
[2026-06-21 14:30:07] PASSO 6/13: Seleção do modelo DeepSeek
────────────────────────────────────────────────────────────────────────────────
  [2026-06-21 14:30:07] AÇÃO:      Estimando modelo ideal com base em RAM e VRAM disponíveis
  [2026-06-21 14:30:07] DADO:      VRAM total: 4096 MB
  [2026-06-21 14:30:07] DADO:      Critério de seleção: RAM=31GB | VRAM=4GB
  [2026-06-21 14:30:07] DADO:      Modelo sugerido: deepseek-r1:7b (Melhor custo-benefício para workstations modernas)
  [2026-06-21 14:30:12] ESCOLHA:   Entrada do usuário: '2'
  [2026-06-21 14:30:12] ESCOLHA:   Modelo final: deepseek-r1:7b
  [2026-06-21 14:30:12] RESULTADO: OK    — Modelo selecionado: deepseek-r1:7b

================================================================================
  FIM DO SETUP
  Término:          2026-06-21 14:52:18
  Modelo instalado: deepseek-r1:7b
  Passos:           13/13 concluídos
================================================================================
```

---

## Boas Práticas para Manutenção

### Ao adicionar um novo passo ao script

1. Chame `log_step "<nome descritivo>"` no início da função
2. Use `log_action` antes de cada operação relevante
3. Use `log_cmd` sempre que invocar um binário externo
4. Use `log_data` para registrar variáveis e valores coletados
5. Use `log_choice` após cada `read` interativo
6. Use `log_output` para saídas de ferramentas externas
7. Finalize com `log_result_ok`, `log_result_warn` ou `log_result_err`
8. Atualize `TOTAL_STEPS` no topo do script

### Ao invocar comandos externos

- Prefira `run_capture` para comandos rápidos (< 2s)
- Prefira `run_live` para comandos lentos ou com progresso visual
- Nunca chame binários externos sem registrar antes com `log_action` + `log_cmd`

### O que NÃO registrar nos logs

- Senhas, tokens de API ou qualquer credencial
- Conteúdo de arquivos de configuração que possam conter segredos
- Dados pessoais além do nome de usuário do sistema operacional

### Retenção e limpeza

Os arquivos de log não são removidos automaticamente. Para limpeza manual:

```bash
# Remove logs com mais de 30 dias
find logs/ -name "*.log" -mtime +30 -delete

# Remove todos os logs
rm -f logs/*.log
```
