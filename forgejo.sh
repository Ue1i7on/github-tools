#!/bin/sh
# script: forgejo.sh
# Finalidade: Conjunto de ferramentas para gerenciar repositórios Forgejo.
# Compatibilidade: POSIX sh - Sem bashismos.
# Versão: 3.2 - Usa nome da pasta como nome do repositório

SCRIPT_NAME="forgejo.sh"
SCRIPT_PATH="$0"

# ============================================
# CONFIGURAÇÃO - SEM VALORES PADRÃO
# ============================================

# Arquivo de configuração local (obrigatório)
CONFIG_FILE="${HOME}/.config/git-forge.conf"

# Variáveis serão carregadas do arquivo ou permanecerão vazias
FORGE_SERVER=""
FORGE_HOST=""
NUSER=""
UTOKEN=""

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

# Tinta Invisível para segurança
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

# Obter nome completo do repositório: owner/repo
get_repo_full() {
 printf "%s/%s" "$NUSER" "$(get_repo_name)"
}

# Carregar configuração - obrigatório
carregar_config() {
 if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
  # Extrair host se servidor definido
  if [ -n "$FORGE_SERVER" ]; then
   FORGE_HOST=$(echo "$FORGE_SERVER" | sed 's|https\?://||')
  fi
  return 0
 fi
 return 1
}

# Verificar se configuração está completa
configuracao_ok() {
 if [ -n "$FORGE_SERVER" ] && [ -n "$NUSER" ] && [ -n "$UTOKEN" ]; then
  return 0
 fi
 return 1
}

salvar_config() {
 mkdir -p "$(dirname "$CONFIG_FILE")"
 cat >"$CONFIG_FILE" <<EOF
FORGE_SERVER="$FORGE_SERVER"
NUSER="$NUSER"
UTOKEN="$UTOKEN"
EOF
 chmod 600 "$CONFIG_FILE" 2>/dev/null || true
 log "Configuração salva em $CONFIG_FILE"
}

validar_credenciais() {
 # Tentar carregar configuração existente
 if ! carregar_config; then
  log "Arquivo de configuração não encontrado: $CONFIG_FILE"
  funcao_config
  return $?
 fi

 # Verificar se todas as variáveis estão preenchidas
 if ! configuracao_ok; then
  log "Configuração incompleta no arquivo."
  funcao_config
  return $?
 fi

 # Testar conexão
 TEST_RESULT=$(curl -s -H "Authorization: token $UTOKEN" \
  "$FORGE_SERVER/api/v1/user" 2>/dev/null)

 if ! echo "$TEST_RESULT" | grep -q '"login"'; then
  log "Erro: Token inválido ou expirado."
  log "Reconfigure com: $0 --config"
  return 1
 fi

 # Sincronizar usuário se necessário
 USER_API=$(echo "$TEST_RESULT" | sed 's/.*"login":"\([^"]*\)".*/\1/')
 if [ "$USER_API" != "$NUSER" ]; then
  log "Aviso: Token pertence a '$USER_API' (configurado: '$NUSER')"
  NUSER="$USER_API"
  salvar_config
 fi

 log "Autenticado como: $NUSER"
 return 0
}

construir_url_repo() {
 _owner="$1"
 _repo="$2"
 printf "https://%s:%s@%s/%s/%s.git" "$NUSER" "$UTOKEN" "$FORGE_HOST" "$_owner" "$_repo"
}

# Configurar remote usando nome da pasta atual como nome do repositório
configurar_remote_com_credenciais() {
 REPO_NAME=$(get_repo_name)
 REPO_FULL=$(get_repo_full)

 # Construir URL correta
 NOVA_URL=$(construir_url_repo "$NUSER" "$REPO_NAME")

 # Verificar se já existe remote
 REMOTE_ATUAL=$(git remote get-url origin 2>/dev/null)

 if [ -n "$REMOTE_ATUAL" ]; then
  git remote set-url origin "$NOVA_URL"
 else
  git remote add origin "$NOVA_URL"
 fi

 log "Remote configurado: $REPO_FULL"
 return 0
}

api_get() {
 endpoint="$1"
 curl -s -H "Authorization: token $UTOKEN" \
  -H "Accept: application/json" \
  "$FORGE_SERVER/api/v1/$endpoint"
}

api_post() {
 endpoint="$1"
 data="$2"
 curl -s -X POST \
  -H "Authorization: token $UTOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$data" \
  "$FORGE_SERVER/api/v1/$endpoint"
}

api_patch() {
 endpoint="$1"
 data="$2"
 curl -s -X PATCH \
  -H "Authorization: token $UTOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$data" \
  "$FORGE_SERVER/api/v1/$endpoint"
}

# ============================================
# FUNÇÃO: Configurar (obrigatória na primeira vez)
# ============================================
funcao_config() {
 log "=========================================="
 log "  Configuração do Git Forge"
 log "=========================================="

 # Mostrar valores atuais se existirem
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
  NOVO_SERVER=$(ler_entrada_limpa) # Servidor não precisa ser oculto
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
  NOVO_USER=$(ler_entrada_limpa) # Usuário não precisa ser oculto
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

 salvar_config
 log ""
 log "Sucesso! Configurado para $NUSER em $FORGE_SERVER"

 return 0
}

# ============================================
# FUNÇÕES PRINCIPAIS
# ============================================

funcao_criar() {
 validar_credenciais || return 1

 log "=========================================="
 log "  Criar Novo Repositório"
 log "=========================================="
 log "Servidor: $FORGE_SERVER"
 log "Usuário: $NUSER"
 log ""

 log "Criar como:"
 log "  1) Usuário: $NUSER (padrão)"
 log "  2) Outra organização"
 printf "Escolha (1/2): "
 OPCAO_USER=$(ler_entrada)

 case "$OPCAO_USER" in
 2)
  while :; do
   printf "Nome da organização: "
   OWNER=$(ler_entrada)
   case "$OWNER" in
   *[!a-zA-Z0-9._-]*) log "Erro: Nome inválido." ;;
   *) [ -n "$OWNER" ] && break || log "Erro: Nome vazio." ;;
   esac
  done
  ;;
 *) OWNER="$NUSER" ;;
 esac

 log "-------------------------------------------"

 while :; do
  printf "Nome do repositório: "
  REPO_NAME=$(ler_entrada)
  case "$REPO_NAME" in
  *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
  *) [ -n "$REPO_NAME" ] && break || log "Erro: Nome vazio." ;;
  esac
 done

 log ""
 log "Visibilidade:"
 log "  1) Público"
 log "  2) Privado"
 printf "Escolha (1/2): "
 OPCAO_VISIB=$(ler_entrada)

 case "$OPCAO_VISIB" in
 2) VISIBILITY="false" ;;
 *) VISIBILITY="true" ;;
 esac

 log "-------------------------------------------"
 log "Resumo:"
 log "  Owner: $OWNER"
 log "  Repositório: $REPO_NAME"
 log "  Visibilidade: $([ "$VISIBILITY" = "true" ] && echo "Público" || echo "Privado")"
 log "-------------------------------------------"

 while :; do
  printf "Confirmar? (s/n): "
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

 PASTA_CRIAR="$REPO_NAME"
 log "Criando diretório local..."
 mkdir -p "$PASTA_CRIAR"

 if [ ! -d "$PASTA_CRIAR" ]; then
  log "Erro: Falha ao criar diretório."
  return 1
 fi

 cd "$PASTA_CRIAR" || exit 1

 log "Inicializando Git..."
 git init
 git branch -M main

 log "Criando arquivos básicos..."
 echo "# $REPO_NAME" >README.md
 echo "*.log" >.gitignore
 echo "node_modules/" >>.gitignore
 echo ".env" >>.gitignore

 log "Criando repositório no Forgejo..."

 DATA="{\"name\":\"$REPO_NAME\",\"private\":$VISIBILITY,\"auto_init\":false,\"default_branch\":\"main\"}"

 RESULT=$(api_post "user/repos" "$DATA")

 if echo "$RESULT" | grep -q '"id"'; then
  log "Repositório remoto criado."
 elif echo "$RESULT" | grep -q "already exists"; then
  log "Repositório já existe. Usando remoto existente."
 else
  log "Aviso: $RESULT"
 fi

 REMOTE_URL=$(construir_url_repo "$OWNER" "$REPO_NAME")
 log "Configurando remote..."
 git remote add origin "$REMOTE_URL"

 log "Criando primeiro commit..."
 git add .
 git commit -m "Initial commit"

 log "Enviando para o Forgejo..."
 if git push -u origin main; then
  log "-------------------------------------------"
  log "Sucesso! Repositório criado."
  log "  URL: $FORGE_SERVER/$OWNER/$REPO_NAME"
  log "-------------------------------------------"
 else
  log "Erro: Falha ao enviar."
  return 1
 fi

 return 0
}

funcao_sync() {
 validar_credenciais || return 1

 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Não está em um repositório Git."
  return 1
 fi

 configurar_remote_com_credenciais || return 1

 REPO_FULL=$(get_repo_full)

 log "=========================================="
 log "  Sincronizar: $REPO_FULL"
 log "=========================================="

 git add .

 if git diff-index --quiet HEAD --; then
  log "Nada para commitar."
 else
  printf "Mensagem: "
  MSG=$(ler_entrada_limpa)
  [ -z "$MSG" ] && MSG="Update $(date +%H:%M:%S)"
  git commit -m "$MSG"
 fi

 BRANCH=$(git branch --show-current)
 log "Enviando..."

 if git push origin "$BRANCH"; then
  log "Sucesso!"
 else
  log "Erro no push."
  return 1
 fi
 return 0
}

funcao_pull() {
 log "=========================================="
 log "  Baixar Alterações"
 log "=========================================="

 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Não está em um repositório Git."
  return 1
 fi

 validar_credenciais || return 1
 configurar_remote_com_credenciais || return 1

 REPO_FULL=$(get_repo_full)
 BRANCH_ATUAL=$(git branch --show-current)

 log "Repositório: $REPO_FULL"
 log "Branch: $BRANCH_ATUAL"
 log "-------------------------------------------"

 if git diff-index --quiet HEAD --; then
  log "Não há mudanças locais."
 else
  log "ATENÇÃO: Mudanças locais não commitadas."
  log "  1) Commitar primeiro"
  log "  2) Stashar, pull, e aplicar stash"
  log "  3) Apenas pull (pode gerar conflitos)"
  log "  4) Cancelar"
  printf "Escolha (1-4): "
  OPCAO_PULL=$(ler_entrada)

  case "$OPCAO_PULL" in
  1)
   printf "Mensagem: "
   MSG=$(ler_entrada_limpa)
   [ -z "$MSG" ] && MSG="Update $(date +%H:%M:%S)"
   git add .
   git commit -m "$MSG"
   ;;
  2)
   git stash
   STASH=1
   ;;
  3) ;;
  *)
   log "Cancelado."
   return 1
   ;;
  esac
 fi

 log "Baixando alterações..."
 if git pull origin "$BRANCH_ATUAL" --rebase; then
  log "Sucesso!"
  [ "$STASH" = "1" ] && git stash pop
 else
  log "Erro ao mesclar."
  git rebase --abort 2>/dev/null
  [ "$STASH" = "1" ] && git stash pop 2>/dev/null
  return 1
 fi

 return 0
}

funcao_topicos() {
 validar_credenciais || return 1

 log "=========================================="
 log "  Atualizar Tópicos do Repositório"
 log "  Usuário: $NUSER"
 log "=========================================="

 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Não está em um repositório Git."
  return 1
 fi

 REPO_FULL=$(get_repo_full)

 log "Repositório: $REPO_FULL"
 log "-------------------------------------------"

 printf "Tópicos (separados por vírgula): "
 TOPICS_RAW=$(ler_entrada)

 if [ -z "$TOPICS_RAW" ]; then
  log "Erro: Tópicos vazios."
  return 1
 fi

 # Converte entrada para JSON array
 TOPICS_JSON="["
 IFS=','
 for t in $TOPICS_RAW; do
  [ "$TOPICS_JSON" != "[" ] && TOPICS_JSON="$TOPICS_JSON,"
  TOPICS_JSON="$TOPICS_JSON\"$(echo $t | tr -d ' ')\""
 done
 TOPICS_JSON="$TOPICS_JSON]"

 DATA="{\"topics\":$TOPICS_JSON}"

 # Forgejo/Gitea requer PUT para atualizar tópicos no endpoint /topics
 URL_API="$FORGE_SERVER/api/v1/repos/$REPO_FULL/topics"
 RESPONSE=$(curl -s -X PUT \
  -H "Authorization: token $UTOKEN" \
  -H "Content-Type: application/json" \
  -d "$DATA" \
  "$URL_API")

 if echo "$RESPONSE" | grep -q "message"; then
  log "Erro ao atualizar tópicos: $(echo $RESPONSE | sed 's/.*"message":"\([^"]*\)".*/\1/')"
  return 1
 else
  log "Tópicos atualizados com sucesso."
 fi

 return 0
}

funcao_renomear() {
 validar_credenciais || return 1

 log "=========================================="
 log "  Renomear Repositório"
 log "=========================================="

 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Não está em um repositório Git."
  return 1
 fi

 REPO_NAME_ATUAL=$(get_repo_name)
 REPO_FULL_ATUAL=$(get_repo_full)
 NOME_PASTA=$(basename "$(pwd)")

 log "Repositório atual: $REPO_FULL_ATUAL"
 log "Pasta local: $NOME_PASTA"

 printf "Novo nome do repositório: "
 NOVO_NOME=$(ler_entrada)

 case "$NOVO_NOME" in
 *[!a-zA-Z0-9._-]*)
  log "Nome inválido."
  return 1
  ;;
 "")
  log "Nome vazio."
  return 1
  ;;
 esac

 [ "$NOVO_NOME" = "$REPO_NAME_ATUAL" ] && log "Nome igual ao atual." && return 1

 log "Renomeando repositório remoto..."
 DATA="{\"name\":\"$NOVO_NOME\"}"

 if api_patch "repos/$REPO_FULL_ATUAL" "$DATA" | grep -q '"id"'; then
  log "Repositório remoto renomeado."
 else
  log "Erro ao renomear no servidor."
  return 1
 fi

 # Atualizar remote local
 NOVA_URL=$(construir_url_repo "$NUSER" "$NOVO_NOME")
 git remote set-url origin "$NOVA_URL"

 # Renomear pasta local se o usuário quiser
 if [ "$NOVO_NOME" != "$NOME_PASTA" ]; then
  printf "Renomear pasta local para '$NOVO_NOME'? (s/n): "
  RENOMEAR_PASTA=$(ler_entrada)
  case "$RENOMEAR_PASTA" in
  *[sS])
   cd ..
   mv "$NOME_PASTA" "$NOVO_NOME" 2>/dev/null && cd "$NOVO_NOME"
   log "Pasta local renomeada."
   ;;
  esac
 fi

 log "Sucesso! Repositório renomeado para: $NOVO_NOME"
 return 0
}

funcao_limpar_historico() {
 validar_credenciais || return 1

 log "=========================================="
 log "  Limpar Histórico"
 log "=========================================="

 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Não está em um repositório Git."
  return 1
 fi

 configurar_remote_com_credenciais || return 1

 REPO_FULL=$(get_repo_full)
 BRANCH_ATUAL=$(git branch --show-current)
 QTD_COMMITS=$(git rev-list --count HEAD)

 log "Repositório: $REPO_FULL"
 log "Branch: $BRANCH_ATUAL"
 log "Commits: $QTD_COMMITS"
 log ""
 log "ATENÇÃO: IRREVERSÍVEL!"

printf "Confirmar? (s/n): "
CONFIRMA=$(ler_entrada)
case "$(echo "$CONFIRMA" | tr '[:upper:]' '[:lower:]')" in
  s|sim|y|yes) ;;
  *) log "Cancelado."; return 1 ;;
esac

 log "Limpando histórico..."
 git checkout --orphan newBranch
 git add -A
 git commit -m "Histórico limpo - $(date +%Y-%m-%d)"

 git branch -D "$BRANCH_ATUAL" 2>/dev/null || git branch -D main 2>/dev/null || true
 git branch -m main

 log "Enviando..."
 if git push -f origin main; then
  log "Sucesso!"
  git gc --aggressive --prune=all
 else
  log "Erro no push."
  return 1
 fi
 return 0
}

funcao_instalar() {
 DEST=""

 if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
  DEST="$PREFIX/bin/forgejo"
 elif [ -d "$HOME/.local/bin" ]; then
  DEST="$HOME/.local/bin/forgejo"
  mkdir -p "$HOME/.local/bin"
 elif [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
  DEST="/usr/local/bin/forgejo"
 else
  DEST="$HOME/bin/forgejo"
  mkdir -p "$HOME/bin"
 fi

 log "=========================================="
 log "  Instalação do forgejo"
 log "=========================================="
 log "Destino: $DEST"

 cp "$SCRIPT_PATH" "$DEST"
 chmod +x "$DEST"

 if [ $? -eq 0 ]; then
  log "Instalado com sucesso!"
  log "Configure com: forgejo --config"
 else
  log "Erro na instalação."
  return 1
 fi
 return 0
}

funcao_desinstalar() {
 DEST=""
 FOUND=0

 for path in "$PREFIX/bin/forgejo" "$HOME/.local/bin/forgejo" "/usr/local/bin/forgejo" "$HOME/bin/forgejo"; do
  if [ -f "$path" ]; then
   DEST="$path"
   FOUND=1
   break
  fi
 done

 if [ "$FOUND" -eq 0 ]; then
  log "forgejo não encontrado instalado."
  return 1
 fi

 log "Encontrado em: $DEST"
 printf "Remover? (s/n): "
 CONFIRMA=$(ler_entrada)

 case "$CONFIRMA" in
 *[sS])
  rm -f "$DEST" && log "Removido com sucesso."
  ;;
 *) log "Cancelado." ;;
 esac
 return 0
}

# ============================================
# INICIALIZAÇÃO
# ============================================

# Tentar carregar configuração existente (silenciosamente)
carregar_config 2>/dev/null

if [ $# -gt 0 ]; then
 case "$1" in
 --create | -c) funcao_criar ;;
 --pull | -p) funcao_pull ;;
 --topicos | -t) funcao_topicos ;;
 --sync | -s) funcao_sync ;;
 --install | -i) funcao_instalar ;;
 --uninstall | -u) funcao_desinstalar ;;
 --rename | -r) funcao_renomear ;;
 --clear-history | -ch) funcao_limpar_historico ;;
 --config | -cfg) funcao_config ;;
 --help | -h)
  echo "Uso: forgejo [opção]"
  echo ""
  echo "Opções:"
  echo "  --create, -c         Criar novo repositório"
  echo "  --pull, -p           Baixar alterações"
  echo "  --topicos, -t        Aplicar tópicos"
  echo "  --sync, -s           Sincronizar (commit + push)"
  echo "  --rename, -r         Renomear repositório"
  echo "  --clear-history, -ch Limpar histórico"
  echo "  --config, -cfg       Configurar credenciais"
  echo "  --install, -i        Instalar globalmente"
  echo "  --uninstall, -u      Desinstalar"
  echo "  --help, -h           Ajuda"
  echo ""
  echo "Arquivo de config: ~/.config/git-forge.conf"
  echo "  FORGE_SERVER=\"https://git.exemplo.org\""
  echo "  NUSER=\"seu_usuario\""
  echo "  UTOKEN=\"seu_token\""
  echo ""
  echo "O nome do repositório é detectado automaticamente"
  echo "a partir do nome da pasta atual."
  ;;
 *) log "Opção inválida. Use: forgejo --help" ;;
 esac
 exit $?
fi

# Menu interativo - verificar configuração antes de mostrar
while :; do
 # Se não tiver configuração, forçar configuração
 if ! configuracao_ok; then
  log "=========================================="
  log "  Bem-vindo ao Git Forge!"
  log "  Configuração necessária"
  log "=========================================="
  funcao_config || exit 1
  continue
 fi

 log "=========================================="
 log "     Git Forge - Menu Principal"
 log "    Servidor: $FORGE_SERVER"
 log "    Usuário: $NUSER"
 log "=========================================="
 log "  1) Criar novo repositório"
 log "  2) Baixar/mesclar alterações (pull)"
 log "  3) Aplicar tópicos"
 log "  4) Sincronizar repositório"
 log "  5) Renomear repositório"
 log "  6) Limpar histórico de versões"
 log "  7) Configurar credenciais"
 log "  8) Instalar como comando global"
 log "  9) Desinstalar comando global"
 log " 10) Sair"
 log "=========================================="
 printf "Escolha (1-10): "
 OPCAO=$(ler_entrada)

 case "$OPCAO" in
 1) funcao_criar ;;
 2) funcao_pull ;;
 3) funcao_topicos ;;
 4) funcao_sync ;;
 5) funcao_renomear ;;
 6) funcao_limpar_historico ;;
 7) funcao_config ;;
 8) funcao_instalar ;;
 9) funcao_desinstalar ;;
 10)
  log "Saindo..."
  exit 0
  ;;
 *) log "Opção inválida." ;;
 esac

 echo ""
 printf "Pressione Enter para continuar..."
 ler_entrada >/dev/null
done
