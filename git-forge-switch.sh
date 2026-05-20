#!/bin/sh
# script: git-forge-switch.sh
# Finalidade: Alternar entre GitHub e Forgejo (git.disroot.org) para push/pull
# Compatibilidade: POSIX sh - Sem bashismos.

SCRIPT_NAME="git-forge-switch.sh"

# ============================================
# CONFIGURAÇÃO
# ============================================

CONFIG_FILE="${HOME}/.config/git-forge.conf"
GITHUB_CONFIG="${HOME}/.config/git-github.conf"
FORGEJO_CONFIG="${HOME}/.config/git-forgejo.conf"

# Variáveis globais
FORGE_SERVER=""
FORGE_HOST=""
NUSER=""
UTOKEN=""
GH_USER=""

# ============================================
# FUNÇÕES AUXILIARES
# ============================================

log() {
 printf "[%s] %s\n" "$(date +%H:%M:%S)" "$1"
}

ler_entrada() {
 dd bs=512 count=1 2>/dev/null | tr -d '[:space:]'
}

ler_entrada_limpa() {
 dd bs=512 count=1 2>/dev/null | tr -d '\n\r'
}

ler_entrada_segura() {
    COR_INVISIVEL="\033[30;40m"
    RESET="\033[0m"
    LIMPAR_LINHA="\033[1A\033[2K\r"

    printf "$COR_INVISIVEL" > /dev/tty
    SENHA=""
    while true; do
        CHAR=$(dd bs=1 count=1 status=none < /dev/tty)
        if [ "$CHAR" = "" ] || [ "$(printf '%s' "$CHAR" | tr -d '\n\r')" = "" ]; then
            break
        fi
        SENHA="${SENHA}${CHAR}"
    done
    printf "$RESET$LIMPAR_LINHA" > /dev/tty
    printf "%s" "$SENHA"
}

# Obter nome do repositório atual (nome da pasta)
get_repo_name() {
 basename "$(pwd)"
}

# Verificar se está em repositório Git
validar_git_repo() {
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  return 1
 fi
 return 0
}

# Carregar configuração do Forgejo
carregar_forgejo_config() {
 if [ -f "$FORGEJO_CONFIG" ]; then
  . "$FORGEJO_CONFIG"
  if [ -n "$FORGE_SERVER" ]; then
   FORGE_HOST=$(echo "$FORGE_SERVER" | sed 's|https\?://||')
  fi
  return 0
 fi
 return 1
}

# Carregar configuração do GitHub
carregar_github_config() {
 if [ -f "$GITHUB_CONFIG" ]; then
  . "$GITHUB_CONFIG"
  return 0
 fi
 return 1
}

# Salvar configuração do Forgejo
salvar_forgejo_config() {
 mkdir -p "$(dirname "$FORGEJO_CONFIG")"
 cat >"$FORGEJO_CONFIG" <<EOF
FORGE_SERVER="$FORGE_SERVER"
NUSER="$NUSER"
UTOKEN="$UTOKEN"
EOF
 chmod 600 "$FORGEJO_CONFIG" 2>/dev/null || true
 log "Configuração Forgejo salva em $FORGEJO_CONFIG"
}

# Salvar configuração do GitHub
salvar_github_config() {
 mkdir -p "$(dirname "$GITHUB_CONFIG")"
 cat >"$GITHUB_CONFIG" <<EOF
GH_USER="$GH_USER"
EOF
 chmod 600 "$GITHUB_CONFIG" 2>/dev/null || true
 log "Configuração GitHub salva em $GITHUB_CONFIG"
}

# Construir URL do Forgejo com credenciais
construir_forgejo_url() {
 _owner="$1"
 _repo="$2"
 printf "https://%s:%s@%s/%s/%s.git" "$NUSER" "$UTOKEN" "$FORGE_HOST" "$_owner" "$_repo"
}

# Construir URL do GitHub
construir_github_url() {
 _owner="$1"
 _repo="$2"
 printf "https://github.com/%s/%s.git" "$_owner" "$_repo"
}

# Obter remote atual
obter_remote_atual() {
 git remote get-url origin 2>/dev/null
}

# Extrair owner/repo da URL
extrair_owner_repo() {
 _url="$1"
 # Remove protocolo e credenciais
 _clean=$(echo "$_url" | sed 's|https\?://[^@]*@||;s|https\?://||;s|\.git$//')
 echo "$_clean"
}

# ============================================
# FUNÇÃO: Configurar Forgejo
# ============================================
funcao_config_forgejo() {
 log "=========================================="
 log "  Configuração do Forgejo (git.disroot.org)"
 log "=========================================="

 # Mostrar valores atuais se existirem
 carregar_forgejo_config
 if [ -n "$FORGE_SERVER" ]; then
  log "Servidor atual: $FORGE_SERVER"
 fi
 if [ -n "$NUSER" ]; then
  log "Usuário atual: $NUSER"
 fi
 if [ -n "$UTOKEN" ]; then
  TOKEN_PREVIEW=$(echo "$UTOKEN" | cut -c1-8)
  log "Token atual: ${TOKEN_PREVIEW}..."
 fi
 log ""

 # Solicitar servidor
 while :; do
  printf "Servidor Forgejo (ex: https://git.disroot.org): "
  NOVO_SERVER=$(ler_entrada_limpa)
  if [ -n "$NOVO_SERVER" ]; then
   FORGE_SERVER="$NOVO_SERVER"
   break
  elif [ -n "$FORGE_SERVER" ]; then
   break
  else
   log "Erro: Servidor é obrigatório."
  fi
 done

 FORGE_HOST=$(echo "$FORGE_SERVER" | sed 's|https\?://||')

 # Solicitar usuário
 while :; do
  printf "Nome de usuário: "
  NOVO_USER=$(ler_entrada_limpa)
  if [ -n "$NOVO_USER" ]; then
   NUSER="$NOVO_USER"
   break
  elif [ -n "$NUSER" ]; then
   break
  else
   log "Erro: Usuário é obrigatório."
  fi
 done

 # Solicitar token
 while :; do
  printf "Token de acesso (API): "
  NOVO_TOKEN=$(ler_entrada_segura)
  if [ -n "$NOVO_TOKEN" ]; then
   UTOKEN="$NOVO_TOKEN"
   break
  elif [ -n "$UTOKEN" ]; then
   break
  else
   log "Erro: Token é obrigatório."
  fi
 done

 # Testar conexão
 log ""
 log "Testando conexão..."
 TEST_RESULT=$(curl -s -H "Authorization: token $UTOKEN" \
  "$FORGE_SERVER/api/v1/user" 2>/dev/null)

 if ! echo "$TEST_RESULT" | grep -q '"login"'; then
  log "Erro: Não foi possível autenticar com as credenciais fornecidas."
  return 1
 fi

 # Confirmar usuário da API
 USER_API=$(echo "$TEST_RESULT" | sed 's/.*"login":"\([^"]*\)".*/\1/')
 if [ "$USER_API" != "$NUSER" ]; then
  log "Aviso: API retornou usuário '$USER_API'"
  printf "Usar '$USER_API'? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) NUSER="$USER_API" ;;
  esac
 fi

 salvar_forgejo_config
 log ""
 log "Sucesso! Configurado para $NUSER em $FORGE_SERVER"

 return 0
}

# ============================================
# FUNÇÃO: Configurar GitHub
# ============================================
funcao_config_github() {
 log "=========================================="
 log "  Configuração do GitHub"
 log "=========================================="

 # Tentar obter usuário via gh CLI
 GH_USER=$(gh api user -q .login 2>/dev/null)

 if [ -n "$GH_USER" ]; then
  log "Usuário GitHub detectado: $GH_USER"
  salvar_github_config
  log "Configuração GitHub salva."
  return 0
 fi

 log "gh CLI não encontrado ou não autenticado."
 log ""

 # Solicitar usuário manualmente
 while :; do
  printf "Nome de usuário GitHub: "
  NOVO_USER=$(ler_entrada_limpa)
  if [ -n "$NOVO_USER" ]; then
   GH_USER="$NOVO_USER"
   break
  elif [ -n "$GH_USER" ]; then
   break
  else
   log "Erro: Usuário é obrigatório."
  fi
 done

 salvar_github_config
 log ""
 log "Sucesso! Configurado para $GH_USER no GitHub"
 log "Dica: Execute 'gh auth login' para autenticação completa."

 return 0
}

# ============================================
# FUNÇÃO: Switch para Forgejo
# ============================================
funcao_switch_forgejo() {
 validar_git_repo || return 1

 if ! carregar_forgejo_config; then
  log "Configuração do Forgejo não encontrada."
  log "Execute: $0 --config-forgejo"
  return 1
 fi

 REPO_NAME=$(get_repo_name)
 REMOTE_ATUAL=$(obter_remote_atual)

 log "=========================================="
 log "  Alternar para Forgejo"
 log "=========================================="
 log "Repositório local: $REPO_NAME"
 log "Remote atual: $REMOTE_ATUAL"
 log ""

 # Construir nova URL
 NOVA_URL=$(construir_forgejo_url "$NUSER" "$REPO_NAME")

 log "Nova URL do remote:"
 log "  $NOVA_URL"
 log ""

 while :; do
  printf "Confirmar switch para Forgejo? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Digite 's' ou 'n'." ;;
  esac
 done

 git remote set-url origin "$NOVA_URL"
 log ""
 log "Sucesso! Remote alterado para Forgejo."
 log "  Servidor: $FORGE_SERVER"
 log "  Repositório: $NUSER/$REPO_NAME"
 log ""
 log "Agora você pode usar:"
 log "  git push origin main"
 log "  git pull origin main"

 return 0
}

# ============================================
# FUNÇÃO: Switch para GitHub
# ============================================
funcao_switch_github() {
 validar_git_repo || return 1

 # Tentar carregar config ou obter via gh CLI
 carregar_github_config
 if [ -z "$GH_USER" ]; then
  GH_USER=$(gh api user -q .login 2>/dev/null)
 fi

 if [ -z "$GH_USER" ]; then
  log "Usuário do GitHub não configurado."
  log "Execute: $0 --config-github"
  return 1
 fi

 REPO_NAME=$(get_repo_name)
 REMOTE_ATUAL=$(obter_remote_atual)

 log "=========================================="
 log "  Alternar para GitHub"
 log "=========================================="
 log "Repositório local: $REPO_NAME"
 log "Remote atual: $REMOTE_ATUAL"
 log ""

 # Construir nova URL
 NOVA_URL=$(construir_github_url "$GH_USER" "$REPO_NAME")

 log "Nova URL do remote:"
 log "  $NOVA_URL"
 log ""

 while :; do
  printf "Confirmar switch para GitHub? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Digite 's' ou 'n'." ;;
  esac
 done

 git remote set-url origin "$NOVA_URL"
 log ""
 log "Sucesso! Remote alterado para GitHub."
 log "  Repositório: $GH_USER/$REPO_NAME"
 log ""
 log "Agora você pode usar:"
 log "  git push origin main"
 log "  git pull origin main"

 return 0
}

# ============================================
# FUNÇÃO: Mostrar Status
# ============================================
funcao_status() {
 validar_git_repo || return 1

 log "=========================================="
 log "  Status dos Remotes"
 log "=========================================="

 REPO_NAME=$(get_repo_name)
 REMOTE_ATUAL=$(obter_remote_atual)

 log "Repositório local: $REPO_NAME"
 log ""
 log "Remote 'origin':"
 log "  URL: $REMOTE_ATUAL"
 log ""

 # Detectar qual serviço está configurado
 if echo "$REMOTE_ATUAL" | grep -q "github.com"; then
  log "Serviço atual: GitHub"
 elif echo "$REMOTE_ATUAL" | grep -q "disroot.org"; then
  log "Serviço atual: Forgejo (git.disroot.org)"
 else
  log "Serviço atual: Desconhecido"
 fi

 log ""
 log "Branch atual: $(git branch --show-current)"
 log ""

 # Listar todos os remotes
 log "Todos os remotes configurados:"
 git remote -v

 return 0
}

# ============================================
# FUNÇÃO: Setup Dual Remote
# ============================================
funcao_setup_dual() {
 validar_git_repo || return 1

 log "=========================================="
 log "  Configurar Remotes Duplos"
 log "=========================================="
 log "Esta função configura ambos os remotes:"
 log "  - origin: remote principal (ativo)"
 log "  - github: remote do GitHub"
 log "  - forgejo: remote do Forgejo"
 log ""

 REPO_NAME=$(get_repo_name)

 # Configurar GitHub
 carregar_github_config
 if [ -z "$GH_USER" ]; then
  GH_USER=$(gh api user -q .login 2>/dev/null)
 fi

 if [ -n "$GH_USER" ]; then
  GITHUB_URL=$(construir_github_url "$GH_USER" "$REPO_NAME")
  log "GitHub: $GH_USER/$REPO_NAME"
  
  # Verificar se já existe remote github
  if git remote get-url github >/dev/null 2>&1; then
   git remote set-url github "$GITHUB_URL"
  else
   git remote add github "$GITHUB_URL"
  fi
  log "  Remote 'github' configurado."
 else
  log "GitHub não configurado. Use --config-github primeiro."
 fi

 # Configurar Forgejo
 carregar_forgejo_config
 if [ -n "$FORGE_SERVER" ] && [ -n "$NUSER" ]; then
  FORGEJO_URL=$(construir_forgejo_url "$NUSER" "$REPO_NAME")
  log "Forgejo: $NUSER/$REPO_NAME"
  
  # Verificar se já existe remote forgejo
  if git remote get-url forgejo >/dev/null 2>&1; then
   git remote set-url forgejo "$FORGEJO_URL"
  else
   git remote add forgejo "$FORGEJO_URL"
  fi
  log "  Remote 'forgejo' configurado."
 else
  log "Forgejo não configurado. Use --config-forgejo primeiro."
 fi

 log ""
 log "Remotes configurados:"
 git remote -v

 log ""
 log "Uso:"
 log "  git push github main    # Push para GitHub"
 log "  git push forgejo main   # Push para Forgejo"
 log "  git pull github main    # Pull do GitHub"
 log "  git pull forgejo main   # Pull do Forgejo"
 log ""
 log "Para alternar o remote 'origin':"
 log "  $0 --switch-github"
 log "  $0 --switch-forgejo"

 return 0
}

# ============================================
# FUNÇÃO: Push para Ambos
# ============================================
funcao_push_both() {
 validar_git_repo || return 1

 BRANCH=$(git branch --show-current)
 log "=========================================="
 log "  Push para Ambos os Remotes"
 log "=========================================="
 log "Branch: $BRANCH"
 log ""

 # Push para GitHub se existir
 if git remote get-url github >/dev/null 2>&1; then
  log "Push para GitHub..."
  if git push github "$BRANCH"; then
   log "  GitHub: Sucesso!"
  else
   log "  GitHub: Falha!"
  fi
 else
  log "Remote 'github' não configurado."
 fi

 # Push para Forgejo se existir
 if git remote get-url forgejo >/dev/null 2>&1; then
  log "Push para Forgejo..."
  if git push forgejo "$BRANCH"; then
   log "  Forgejo: Sucesso!"
  else
   log "  Forgejo: Falha!"
  fi
 else
  log "Remote 'forgejo' não configurado."
 fi

 log ""
 log "Operação concluída."

 return 0
}

# ============================================
# FUNÇÃO: Pull de Ambos
# ============================================
funcao_pull_both() {
 validar_git_repo || return 1

 BRANCH=$(git branch --show-current)
 log "=========================================="
 log "  Pull de Ambos os Remotes"
 log "=========================================="
 log "Branch: $BRANCH"
 log ""

 # Pull do GitHub se existir
 if git remote get-url github >/dev/null 2>&1; then
  log "Pull do GitHub..."
  if git pull github "$BRANCH" --rebase; then
   log "  GitHub: Sucesso!"
  else
   log "  GitHub: Falha ou sem alterações."
  fi
 else
  log "Remote 'github' não configurado."
 fi

 # Pull do Forgejo se existir
 if git remote get-url forgejo >/dev/null 2>&1; then
  log "Pull do Forgejo..."
  if git pull forgejo "$BRANCH" --rebase; then
   log "  Forgejo: Sucesso!"
  else
   log "  Forgejo: Falha ou sem alterações."
  fi
 else
  log "Remote 'forgejo' não configurado."
 fi

 log ""
 log "Operação concluída."

 return 0
}

# ============================================
# FUNÇÃO: Ajuda
# ============================================
funcao_ajuda() {
 cat <<EOF
Uso: $0 [OPÇÃO]

Opções:
  --status              Mostrar status atual dos remotes
  --switch-github       Alternar remote para GitHub
  --switch-forgejo      Alternar remote para Forgejo (git.disroot.org)
  --setup-dual          Configurar remotes duplos (github e forgejo)
  --push-both           Fazer push para ambos os remotes
  --pull-both           Fazer pull de ambos os remotes
  --config-github       Configurar usuário do GitHub
  --config-forgejo      Configurar credenciais do Forgejo
  --help                Mostrar esta ajuda

Exemplos:
  $0 --status                    # Ver qual remote está ativo
  $0 --switch-github             # Alternar para GitHub
  $0 --switch-forgejo            # Alternar para Forgejo
  $0 --setup-dual                # Configurar ambos os remotes
  $0 --push-both                 # Push para GitHub e Forgejo
  $0 --pull-both                 # Pull de GitHub e Forgejo

Descrição:
  Este script permite alternar facilmente entre GitHub e Forgejo
  (git.disroot.org) para operações de push/pull.

  Modo Simples:
    Usa o remote 'origin' que aponta para um dos serviços.
    Use --switch-github ou --switch-forgejo para alternar.

  Modo Dual:
    Configura remotes separados ('github' e 'forgejo').
    Use --setup-dual para configurar.
    Depois use git push github main ou git push forgejo main.

EOF
}

# ============================================
# MAIN
# ============================================

case "$1" in
--status)
 funcao_status
 ;;
--switch-github)
 funcao_switch_github
 ;;
--switch-forgejo)
 funcao_switch_forgejo
 ;;
--setup-dual)
 funcao_setup_dual
 ;;
--push-both)
 funcao_push_both
 ;;
--pull-both)
 funcao_pull_both
 ;;
--config-github)
 funcao_config_github
 ;;
--config-forgejo)
 funcao_config_forgejo
 ;;
--help|-h)
 funcao_ajuda
 ;;
*)
 funcao_ajuda
 ;;
esac

exit 0
