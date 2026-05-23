#!/bin/sh
# script: github-tools.sh
# Finalidade: Conjunto de ferramentas para gerenciar repositórios GitHub.
# Funcionalidades: Aplicar tópicos, sincronizar, renomear, limpar histórico e instalar.
# Compatibilidade: POSIX sh - Sem bashismos.

SCRIPT_NAME="github-tools.sh"
SCRIPT_PATH="$0"

log() {
 printf "[%s] %s\n" "$(date +%H:%M:%S)" "$1"
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

# Ler entrada comum
ler_entrada() {
 dd bs=512 count=1 2>/dev/null | tr -d '[:space:]'
}

ler_entrada_limpa() {
 dd bs=512 count=1 2>/dev/null | tr -d '\n\r'
}


# ============================================
# FUNÇÃO: Criar Repositório
# ============================================
funcao_criar() {
 log "=========================================="
 log "  Criar Novo Repositório"
 log "=========================================="

 # Obter usuário atual do GitHub
 GH_USER=$(gh api user -q .login 2>/dev/null)

 if [ -z "$GH_USER" ]; then
  log "Erro: Não foi possível obter seu usuário do GitHub."
  log "Execute: gh auth login"
  return 1
 fi

 log "Usuário GitHub: $GH_USER"
 log ""

 # Perguntar se quer usar outro usuário
 log "Deseja criar repositório em outra conta?"
 log "  1) Usar: $GH_USER"
 log "  2) Informar outro usuário/organização"
 printf "Escolha (1/2): "
 OPCAO_USER=$(ler_entrada)

 case "$OPCAO_USER" in
 1) OWNER="$GH_USER" ;;
 2)
  while :; do
   printf "Digite o nome de usuário ou organização: "
   OWNER=$(ler_entrada)
   case "$OWNER" in
   *[!a-zA-Z0-9._-]*) log "Erro: Nome inválido." ;;
   *) [ -n "$OWNER" ] && break || log "Erro: Nome vazio." ;;
   esac
  done
  ;;
 *) OWNER="$GH_USER" ;;
 esac

 log "-------------------------------------------"

 # Solicitar nome do repositório
 while :; do
  printf "Digite o nome do repositório: "
  REPO_NAME=$(ler_entrada)
  case "$REPO_NAME" in
  *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
  *) [ -n "$REPO_NAME" ] && break || log "Erro: Nome vazio." ;;
  esac
 done

 # Perguntar sobre visibilidade
 log ""
 log "Visibilidade do repositório:"
 log "  1) Público"
 log "  2) Privado"
 printf "Escolha (1/2): "
 OPCAO_VISIB=$(ler_entrada)

 case "$OPCAO_VISIB" in
 2) VISIBILITY="--private" ;;
 *) VISIBILITY="--public" ;;
 esac

 # Perguntar onde criar
 log ""
 log "Onde criar o repositório?"
 log "  1) Diretório atual (cria pasta)"
 printf "Escolha (1): "
 OPCAO_DIR=$(ler_entrada)

 if [ "$OPCAO_DIR" = "1" ] || [ -z "$OPCAO_DIR" ]; then
  PASTA_CRIAR="$REPO_NAME"
 else
  PASTA_CRIAR="$REPO_NAME"
 fi

 # Confirmação
 log "-------------------------------------------"
 log "Resumo:"
 log "  Usuário/Org: $OWNER"
 log "  Repositório: $REPO_NAME"
 log "  Visibilidade: $(echo "$VISIBILITY" | sed 's/--//')"
 log "  Pasta: $PASTA_CRIAR"
 log "-------------------------------------------"

 while :; do
  printf "Confirmar criação? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Erro: Digite 's' ou 'n'." ;;
  esac
 done

 # Criar diretório local
 log "Criando diretório local..."
 mkdir -p "$PASTA_CRIAR"

 if [ ! -d "$PASTA_CRIAR" ]; then
  log "Erro: Falha ao criar diretório."
  return 1
 fi

 cd "$PASTA_CRIAR" || exit 1

 # Inicializar Git
 log "Inicializando Git..."
 git init
 git branch -M main

 # Criar arquivos básicos
 log "Criando arquivos básicos..."
 echo "# $REPO_NAME" >README.md
 echo "*.log" >.gitignore
 echo "" >>.gitignore
 echo "# Dependencies" >>.gitignore
 echo "node_modules/" >>.gitignore

 # Criar repositório remoto
 log "Criando repositório no GitHub..."
 if gh repo create "$OWNER/$REPO_NAME" $VISIBILITY --source=. --remote=origin 2>/dev/null; then
  log "Repositório remoto criado."
 else
  # Tentar sem --source se já existir local
  log "Tentando另一种方式..."
  if gh repo create "$OWNER/$REPO_NAME" $VISIBILITY --private --remote=origin 2>/dev/null; then
   log "Repositório remoto criado."
  else
   log "Erro: Repositório pode já existir ou sem permissão."
   log "Continuando com remote existente..."
  fi
 fi

 # Primeiro commit
 log "Criando primeiro commit..."
 git add .
 git commit -m "Initial commit"

 # Push inicial
 log "Enviando para o GitHub..."
 if git push -u origin main; then
  log "-------------------------------------------"
  log "Sucesso! Repositório criado e enviado."
  log "  URL: https://github.com/$OWNER/$REPO_NAME"
  log "-------------------------------------------"
 else
  log "Erro: Falha ao enviar. Verifique as credenciais."
  return 1
 fi

 return 0
}

# ============================================
# FUNÇÃO: Baixar/Mesclar Alterações
# ============================================
funcao_pull() {
 log "=========================================="
 log "  Baixar e Mesclar Alterações"
 log "=========================================="

 # Validar se está em repositório Git
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  return 1
 fi

 # Obter informações
 REPO_FULL=$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/\.git$//')
 BRANCH_ATUAL=$(git branch --show-current)

 log "Repositório: $REPO_FULL"
 log "Branch atual: $BRANCH_ATUAL"
 log "-------------------------------------------"

 # Verificar se há mudanças locais
 if git diff-index --quiet HEAD --; then
  log "Não há mudanças locais para commit."
  log "Baixando alterações remotas..."
 else
  log "ATENÇÃO: Você tem mudanças locais não commitadas."
  log ""
  log "O que deseja fazer?"
  log "  1) Commitar primeiro, depois pull"
  log "  2) Stashar mudanças, fazer pull, e aplicar stash"
  log "  3) Apenas fazer pull (pode gerar conflitos)"
  log "  4) Cancelar"
  printf "Escolha (1-4): "
  OPCAO_PULL=$(ler_entrada)

  case "$OPCAO_PULL" in
  1)
   # Commitar primeiro
   printf "Mensagem do commit: "
   MSG=$(ler_entrada_limpa)
   [ -z "$MSG" ] && MSG="Update $(date +%H:%M:%S)"
   git add .
   git commit -m "$MSG"
   ;;
  2)
   # Stash
   git stash
   STASH=1
   ;;
  3)
   # Apenas pull
   ;;
  *)
   log "Operação cancelada."
   return 1
   ;;
  esac
 fi

 log "-------------------------------------------"
 log "Baixando alterações do GitHub..."
 log "Executando: git pull origin $BRANCH_ATUAL --rebase"
 log "-------------------------------------------"

 # Pull com rebase
 if git pull origin "$BRANCH_ATUAL" --rebase; then
  log "Alterações mescladas com sucesso!"

  # Se tinha stash, aplicar
  if [ "$STASH" = "1" ]; then
   log "Aplicando stash..."
   if git stash pop; then
    log "Stash aplicado."
   else
    log "Conflitos ao aplicar stash. Resolva manualmente."
   fi
  fi

  # Perguntar se quer fazer push
  if [ "$STASH" != "1" ]; then
   while :; do
    printf "Deseja enviar as alterações? (s/n): "
    CONFIRMA=$(ler_entrada)
    case "$CONFIRMA" in
    *[sS])
     log "Enviando para o GitHub..."
     if git push origin "$BRANCH_ATUAL"; then
      log "Sucesso! Alterações enviadas."
     else
      log "Erro ao enviar."
     fi
     break
     ;;
    *[nN]) break ;;
    *) log "Erro: Digite 's' ou 'n'." ;;
    esac
   done
  fi
 else
  log "Erro ao baixar/mesclar alterações."
  log "Pode haver conflitos. Resolva manualmente."

  # Oferecer abortar rebase
  if git rebase --abort 2>/dev/null; then
   log "Rebase abortado."
  fi

  if [ "$STASH" = "1" ]; then
   log "Restaurando stash..."
   git stash pop 2>/dev/null
  fi

  return 1
 fi

 return 0
}

# ============================================
# FUNÇÃO: Aplicar Tópicos
# ============================================
funcao_topicos() {
 log "=========================================="
 log "  Configuração de Tópicos GitHub"
 log "=========================================="

 # Validar se está em repositório Git
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  log "Use: cd nome-do-repositorio e tente novamente."
  return 1
 fi

 # Obter repositório automaticamente do remote
 REPO_FULL=$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/\.git$//')

 if [ -z "$REPO_FULL" ]; then
  log "Erro: Repositório não possui remote configurado."
  return 1
 fi

 log "Repositório: $REPO_FULL"
 log "-------------------------------------------"

 # Input dos Tópicos
 while :; do
  log "Digite os tópicos (separados por vírgula):"
  printf "Exemplo: python,api,docker\n> "
  TOPICS_RAW=$(ler_entrada)
  TOPICS=$(echo "$TOPICS_RAW" | tr -d ' ')

  case "$TOPICS" in
  *[!a-zA-Z0-9,-]*) log "Erro: Use apenas letras, números e hífens." ;;
  *) [ -n "$TOPICS" ] && break || log "Erro: Tópicos vazios." ;;
  esac
 done

 # Processamento de Limites
 QTD_TOTAL=$(echo "$TOPICS" | tr ',' '\n' | grep -v '^$' | grep -c '.')

 if [ "$QTD_TOTAL" -gt 20 ]; then
  log "ATENÇÃO: Limitando aos 20 primeiros tópicos."
  TOPICS=$(echo "$TOPICS" | tr ',' '\n' | head -n 20 | tr '\n' ',' | sed 's/,$//')
  QTD_TOTAL=20
 fi

 log "-------------------------------------------"
 log "Tópicos a serem aplicados ($QTD_TOTAL):"
 echo "$TOPICS" | tr ',' '\n' | while read -r t; do
  [ -n "$t" ] && log "  - $t"
 done
 log "-------------------------------------------"

 # Confirmação
 while :; do
  printf "Deseja continuar? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Erro: Digite 's' ou 'n'." ;;
  esac
 done

 # Obter tópicos atuais e removê-los
 log "Limpando tópicos antigos..."
 TOPICOS_ATUAIS=$(gh api "repos/$REPO_FULL/topics" -q '.names[]' 2>/dev/null)

 if [ -n "$TOPICOS_ATUAIS" ]; then
  echo "$TOPICOS_ATUAIS" | while read -r topico; do
   [ -n "$topico" ] && gh repo edit "$REPO_FULL" --remove-topic "$topico" 2>/dev/null
  done
 fi

 # Aplicar novos tópicos
 log "Aplicando novos tópicos..."
 if gh repo edit "$REPO_FULL" --add-topic "$TOPICS"; then
  log "Sucesso! Tópicos atualizados no GitHub."
 else
  log "Erro: Falha na API. Verifique 'gh auth status'."
  return 1
 fi

 return 0
}

# ============================================
# FUNÇÃO: Renomear Repositório
# ============================================
funcao_renomear() {
 log "=========================================="
 log "  Renomear Repositório GitHub"
 log "=========================================="

 # Validar se está em repositório Git
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  return 1
 fi

 # Obter repositório atual
 REPO_FULL=$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/\.git$//')
 OWNER=$(echo "$REPO_FULL" | cut -d'/' -f1)
 NOME_REPO=$(echo "$REPO_FULL" | cut -d'/' -f2)

 # Obter caminho atual da pasta
 PASTA_ATUAL=$(pwd)
 NOME_PASTA=$(basename "$PASTA_ATUAL")

 log "Repositório remoto: $OWNER/$NOME_REPO"
 log "Pasta local: $NOME_PASTA"
 log ""

 # Verificar se os nomes são diferentes
 if [ "$NOME_REPO" != "$NOME_PASTA" ]; then
  log "ATENÇÃO: Os nomes são diferentes!"
  log "  Repositório: $NOME_REPO"
  log "  Pasta local: $NOME_PASTA"
  log ""
  log "O que deseja fazer?"
  log "  1) Renomear apenas o repositório remoto"
  log "  2) Renomear apenas a pasta local"
  log "  3) Renomear ambos"
  log "  4) Cancelar"
  printf "Escolha (1-4): "
  OPCAO=$(ler_entrada)

  case "$OPCAO" in
  1)
   funcao_renomear_remoto "$OWNER" "$NOME_REPO"
   return $?
   ;;
  2)
   funcao_renomear_local "$NOME_PASTA"
   return $?
   ;;
  3)
   funcao_renomear_ambos "$OWNER" "$NOME_REPO" "$NOME_PASTA"
   return $?
   ;;
  *)
   log "Operação cancelada."
   return 1
   ;;
  esac
 fi

 # Se os nomes são iguais, pedir novo nome
 while :; do
  printf "Digite o novo nome do repositório: "
  NOVO_NOME=$(ler_entrada)
  case "$NOVO_NOME" in
  *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
  *) [ -n "$NOVO_NOME" ] && break || log "Erro: Nome vazio." ;;
  esac
 done

 if [ "$NOVO_NOME" = "$NOME_REPO" ]; then
  log "O nome é o mesmo. Cancelando."
  return 1
 fi

 funcao_renomear_ambos "$OWNER" "$NOME_REPO" "$NOVO_NOME"
 return $?
}

# Renomear apenas repositório remoto
funcao_renomear_remoto() {
 _owner="$1"
 _nome_atual="$2"

 while :; do
  printf "Digite o novo nome do repositório: "
  NOVO_NOME=$(ler_entrada)
  case "$NOVO_NOME" in
  *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
  *) [ -n "$NOVO_NOME" ] && break || log "Erro: Nome vazio." ;;
  esac
 done

 if [ "$NOVO_NOME" = "$_nome_atual" ]; then
  log "O nome é o mesmo. Cancelando."
  return 1
 fi

 log "-------------------------------------------"
 log "Renomeando repositório remoto..."
 log "  De: $_nome_atual"
 log "  Para: $NOVO_NOME"
 log "-------------------------------------------"

 if gh repo rename "$NOVO_NOME" -R "$_owner/$_nome_atual" --yes; then
  git remote set-url origin "https://github.com/$_owner/$NOVO_NOME.git"
  log "Sucesso! Repositório remoto renomeado."
 else
  log "Erro: Falha ao renomear repositório remoto."
  return 1
 fi

 return 0
}

# Renomear apenas pasta local
funcao_renomear_local() {
 _nome_atual="$1"

 while :; do
  printf "Digite o novo nome da pasta: "
  NOVO_NOME=$(ler_entrada)
  case "$NOVO_NOME" in
  *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
  *) [ -n "$NOVO_NOME" ] && break || log "Erro: Nome vazio." ;;
  esac
 done

 if [ "$NOVO_NOME" = "$_nome_atual" ]; then
  log "O nome é o mesmo. Cancelando."
  return 1
 fi

 log "-------------------------------------------"
 log "Renomeando pasta local..."
 log "  De: $_nome_atual"
 log "  Para: $NOVO_NOME"
 log "-------------------------------------------"

 PASTA_PAI=$(dirname "$(pwd)")
 cd ..
 mv "$_nome_atual" "$NOVO_NOME"

 if [ -d "$NOVO_NOME" ]; then
  cd "$NOVO_NOME"
  log "Sucesso! Pasta local renomeada para: $NOVO_NOME"
 else
  log "Erro: Falha ao renomear pasta local."
  return 1
 fi

 return 0
}

# Renomear ambos (remoto e local)
funcao_renomear_ambos() {
 _owner="$1"
 _nome_atual="$2"
 _novo_nome="$3"

 if [ -z "$_novo_nome" ]; then
  while :; do
   printf "Digite o novo nome: "
   _novo_nome=$(ler_entrada)
   case "$_novo_nome" in
   *[!a-zA-Z0-9._-]*) log "Erro: Use apenas letras, números, pontos e hífens." ;;
   *) [ -n "$_novo_nome" ] && break || log "Erro: Nome vazio." ;;
   esac
  done
 fi

 if [ "$_novo_nome" = "$_nome_atual" ]; then
  log "O nome é o mesmo. Cancelando."
  return 1
 fi

 log "-------------------------------------------"
 log "Repositório remoto:"
 log "  De: $_nome_atual"
 log "  Para: $_novo_nome"
 log "Pasta local:"
 log "  De: $_nome_atual"
 log "  Para: $_novo_nome"
 log "-------------------------------------------"

 # Confirmação
 while :; do
  printf "Confirmar renomeamento? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Erro: Digite 's' ou 'n'." ;;
  esac
 done

 # Renomear no GitHub
 log "Renomeando repositório no GitHub..."
 if gh repo rename "$_novo_nome" -R "$_owner/$_nome_atual" --yes; then
  log "Sucesso! Repositório remoto renomeado."
 else
  log "Erro: Falha ao renomear repositório remoto."
  return 1
 fi

 # Atualizar remote local
 log "Atualizando remote local..."
 git remote set-url origin "https://github.com/$_owner/$_novo_nome.git"

 # Renomear pasta local
 if [ "$(basename "$(pwd)")" != "$_novo_nome" ]; then
  log "Renomeando pasta local..."
  PASTA_PAI=$(dirname "$(pwd)")
  cd ..
  mv "$_nome_atual" "$_novo_nome"

  if [ -d "$_novo_nome" ]; then
   cd "$_novo_nome"
   log "Pasta local renomeada para: $_novo_nome"
  else
   log "Erro: Falha ao renomear pasta local."
   return 1
  fi
 fi

 log "-------------------------------------------"
 log "Renomeamento concluído!"
 log "  Repositório: $_owner/$_novo_nome"
 log "  Pasta local: $(pwd)"

 return 0
}

# ============================================
# FUNÇÃO: Limpar Histórico de Versões
# ============================================
funcao_limpar_historico() {
 log "=========================================="
 log "  Limpar Histórico de Versões"
 log "=========================================="

 # Validar se está em repositório Git
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  return 1
 fi

 # Obter informações do repositório
 REPO_FULL=$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/\.git$//')
 BRANCH_ATUAL=$(git branch --show-current)
 QTD_COMMITS=$(git rev-list --count HEAD)

 log "Repositório: $REPO_FULL"
 log "Branch atual: $BRANCH_ATUAL"
 log "Total de commits: $QTD_COMMITS"
 log ""
 log "ATENÇÃO: Esta ação é IRREVERSÍVEL!"
 log "Todo o histórico será perdido. Apenas o estado atual será mantido."
 log ""

 # Confirmação 1
 while :; do
  printf "Tem certeza que deseja continuar? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Erro: Digite 's' ou 'n'." ;;
  esac
 done

 # Confirmação 2
 while :; do
  printf "Digite 'sim' para confirmar: "
  CONFIRMA=$(ler_entrada_limpa)
  case "$CONFIRMA" in
  sim) break ;;
  *)
   log "Operação cancelada."
   return 1
   ;;
  esac
 done

 log "-------------------------------------------"
 log "Iniciando limpeza do histórico..."

 # Criar branch órfão
 git checkout --orphan newBranch

 # Adicionar todos os arquivos
 git add -A

 # Commit inicial
 git commit -m "Histórico limpo - estado atual"

 # Remover branch master/main
 if [ "$BRANCH_ATUAL" = "master" ] || [ "$BRANCH_ATUAL" = "main" ]; then
  git branch -D "$BRANCH_ATUAL"
 else
  git branch -D master 2>/dev/null
  git branch -D main 2>/dev/null
 fi

 # Renomear para master
 git branch -m master

 # Forçar push
 log "Enviando para o GitHub..."
 git push -f origin master

 if [ $? -ne 0 ]; then
  log "Erro ao enviar para o GitHub."
  return 1
 fi

 # Limpeza local
 git gc --aggressive --prune=all

 log "Sucesso! Histórico limpo."
 log "O repositório agora contém apenas o estado atual."

 return 0
}

# ============================================
# FUNÇÃO: Sincronizar
# ============================================
funcao_sync() {
 # Validação de Repositório
 if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Erro: Você não está dentro de um repositório Git."
  log "Use: cd nome-da-pasta e tente novamente."
  return 1
 fi

 # Obter usuário do GitHub
 _USER=$(gh api user -q .login 2>/dev/null)
 if [ -z "$_USER" ]; then
  log "Erro: Não foi possível obter seu usuário do GitHub."
  log "Execute: gh auth login"
  return 1
 fi

 # Detectar credenciais
 EMAIL_ATUAL=$(git config user.email 2>/dev/null)
 NOME_ATUAL=$(git config user.name 2>/dev/null)

 log "=========================================="
 log "  Configuração de Credenciais Git"
 log "=========================================="

 # Loop de credenciais
 while :; do
  if [ -n "$EMAIL_ATUAL" ] && [ -n "$NOME_ATUAL" ]; then
   log "Credenciais já configuradas:"
   log "  Nome:  $NOME_ATUAL"
   log "  Email: $EMAIL_ATUAL"
   log ""
   log "Deseja usar essas credenciais ou alterar?"
   log "  1) Usar credenciais atuais"
   log "  2) Alterar credenciais"
   printf "Escolha (1/2): "
   OPCAO=$(ler_entrada_limpa)

   case "$OPCAO" in
   1) break ;;
   2) ;;
   *)
    log "Erro: Digite 1 ou 2."
    continue
    ;;
   esac
  fi

  # Solicitar novo nome
  while :; do
   printf "Digite seu nome de usuário: "
   NOVO_NOME=$(ler_entrada_limpa)
   [ -n "$NOVO_NOME" ] && break
   log "Erro: Nome não pode ser vazio."
  done

  # Sugerir email
  EMAIL_PADRAO="${NOVO_NOME}@users.noreply.github.com"
  log ""
  log "Email sugerido: $EMAIL_PADRAO"
  log "Deseja usar este email ou informar outro?"
  log "  1) Usar email sugerido"
  log "  2) Informar outro email"
  printf "Escolha (1/2): "
  OPCAO_EMAIL=$(ler_entrada_limpa)

  case "$OPCAO_EMAIL" in
  1) NOVO_EMAIL="$EMAIL_PADRAO" ;;
  2)
   while :; do
    printf "Digite seu email: "
    NOVO_EMAIL=$(ler_entrada_limpa)
    [ -n "$NOVO_EMAIL" ] && break
    log "Erro: Email não pode ser vazio."
   done
   ;;
  *) NOVO_EMAIL="$EMAIL_PADRAO" ;;
  esac

  # Aplicar configurações
  git config --global user.name "$NOVO_NOME"
  git config --global user.email "$NOVO_EMAIL"

  log "Credenciais configuradas com sucesso!"
  log "  Nome:  $NOVO_NOME"
  log "  Email: $NOVO_EMAIL"

  EMAIL_ATUAL="$NOVO_EMAIL"
  NOME_ATUAL="$NOVO_NOME"
  break
 done

 log "-------------------------------------------"

 # Configurar credenciais do GH
 log "Vinculando credenciais do GH ao Git..."
 gh auth setup-git

 # Sincronização
 REPO_FULL=$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/\.git$//')
 log "Sincronizando: $REPO_FULL"

 git add .

 if git diff-index --quiet HEAD --; then
  log "Nada para commitar."
 else
  printf "Mensagem do commit: "
  MSG=$(ler_entrada_limpa)
  [ -z "$MSG" ] && MSG="Update $(date +%H:%M:%S)"
  git commit -m "$MSG"
 fi

 log "Enviando para o GitHub..."
 git push origin "$(git branch --show-current)"

 if [ $? -eq 0 ]; then
  log "Sucesso!"
 else
  log "Erro no Push. Verifique a conexão."
  return 1
 fi

 return 0
}

# ============================================
# FUNÇÃO: Instalar
# ============================================
funcao_instalar() {
 DEST=""

 if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
  DEST="$PREFIX/bin/gh-tools"
 elif [ -n "$HOME" ] && [ -d "$HOME/.local/bin" ]; then
  DEST="$HOME/.local/bin/gh-tools"
  mkdir -p "$HOME/.local/bin"
 elif [ -d "/usr/local/bin" ]; then
  DEST="/usr/local/bin/gh-tools"
 else
  DEST="$HOME/bin/gh-tools"
  mkdir -p "$HOME/bin"
 fi

 log "=========================================="
 log "  Instalação do gh-tools"
 log "=========================================="
 log "Instalando em: $DEST"

 cp "$SCRIPT_PATH" "$DEST"
 chmod +x "$DEST"

 if [ $? -eq 0 ]; then
  log "Sucesso! Comando 'gh-tools' instalado."
 else
  log "Erro: Falha ao instalar. Verifique permissões."
  return 1
 fi

 return 0
}

# ============================================
# FUNÇÃO: Desinstalar
# ============================================
funcao_desinstalar() {
 DEST=""
 FOUND=0

 # Buscar onde está instalado
 if [ -n "$PREFIX" ] && [ -f "$PREFIX/bin/gh-tools" ]; then
  DEST="$PREFIX/bin/gh-tools"
  FOUND=1
 elif [ -f "$HOME/.local/bin/gh-tools" ]; then
  DEST="$HOME/.local/bin/gh-tools"
  FOUND=1
 elif [ -f "/usr/local/bin/gh-tools" ]; then
  DEST="/usr/local/bin/gh-tools"
  FOUND=1
 elif [ -f "$HOME/bin/gh-tools" ]; then
  DEST="$HOME/bin/gh-tools"
  FOUND=1
 fi

 if [ "$FOUND" -eq 0 ]; then
  log "Erro: gh-tools não está instalado."
  return 1
 fi

 log "=========================================="
 log "  Desinstalar gh-tools"
 log "=========================================="
 log "Encontrado em: $DEST"

 # Confirmação
 while :; do
  printf "Confirmar desinstalação? (s/n): "
  CONFIRMA=$(ler_entrada)
  case "$CONFIRMA" in
  *[sS]) break ;;
  *[nN])
   log "Operação cancelada."
   return 1
   ;;
  *) log "Erro: Digite 's' ou 'n'." ;;
  esac
 done

 rm -f "$DEST"

 if [ $? -eq 0 ]; then
  log "Sucesso! gh-tools foi removido."
 else
  log "Erro: Falha ao remover. Verifique permissões."
  return 1
 fi

 return 0
}

# ============================================
# MENU PRINCIPAL
# ============================================

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
 --help | -h)
  echo "Uso: $0 [opção]"
  echo ""
  echo "Opções:"
  echo "  --create, -c         Criar novo repositório"
  echo "  --pull, -p          Baixar e mesclar alterações do GitHub"
  echo "  --topicos, -t       Aplicar tópicos a um repositório"
  echo "  --sync, -s          Sincronizar e enviar para o GitHub"
  echo "  --rename, -r        Renomear repositório local e remoto"
  echo "  --clear-history, -ch Limpar histórico de versões"
  echo "  --install, -i        Instalar como comando global"
  echo "  --uninstall, -u     Remover comando global"
  echo "  --help, -h          Mostrar esta ajuda"
  ;;
 *) log "Opção inválida. Use: $0 --help" ;;
 esac
 exit $?
fi

while :; do
 log "=========================================="
 log "       GitHub Tools - Menu Principal"
 log "=========================================="
 log "  1) Criar novo repositório"
 log "  2) Baixar/mesclar alterações (pull)"
 log "  3) Aplicar tópicos"
 log "  4) Sincronizar repositório"
 log "  5) Renomear repositório"
 log "  6) Limpar histórico de versões"
 log "  7) Instalar como comando global"
 log "  8) Desinstalar comando global"
 log "  9) Sair"
 log "=========================================="
 printf "Escolha uma opção (1-9): "
 OPCAO=$(ler_entrada)

 case "$OPCAO" in
 1) funcao_criar ;;
 2) funcao_pull ;;
 3) funcao_topicos ;;
 4) funcao_sync ;;
 5) funcao_renomear ;;
 6) funcao_limpar_historico ;;
 7) funcao_instalar ;;
 8) funcao_desinstalar ;;
 9)
  log "Saindo..."
  exit 0
  ;;
 *) log "Erro: Opção inválida." ;;
 esac

 echo ""
done
