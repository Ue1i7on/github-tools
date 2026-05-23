# 🔧 Git Tools

Ferramentas POSIX sh para gerenciar repositórios Git em Forgejo e GitHub. Compatível com Dash/Bourne Shell.

---

## 📋 Índice

- [🔧 Forgejo Tools](#-forgejo-tools)
- [🐙 GitHub Tools](#-github-tools)
- [🔍 OpenCode Integration](#-opencode-integration)

---

## 🔧 Forgejo Tools

Gerenciamento via API REST com token.

**Configuração:**
```sh
./forgejo.sh --config   # interativo
# ou crie ~/.config/git-forge.conf manualmente
```

**Uso:** `./forgejo.sh` (menu) ou:
```sh
./forgejo.sh --create    # Criar repo
./forgejo.sh --sync      # Commit + push
./forgejo.sh --pull      # Pull com rebase
./forgejo.sh --topicos   # Aplicar tópicos
./forgejo.sh --rename    # Renomear repo
./forgejo.sh --clear-history  # Limpar histórico
```

---

## 🐙 GitHub Tools

Automação via `gh` CLI.

**Pré-requisitos:** `pkg install gh` + `gh auth login`

**Uso:** `./github-tools.sh` (menu) ou:
```sh
./github-tools.sh --create         # Criar repo
./github-tools.sh --sync           # Configurar git + push
./github-tools.sh --pull           # Pull com rebase
./github-tools.sh --topicos        # Gerenciar tópicos
./github-tools.sh --rename         # Renomear repo
./github-tools.sh --clear-history  # Resetar histórico
```

---

## 🔍 OpenCode Integration

Substitui `/review` nativo para commit + push com histórico limpo (single commit).

**Instalação:** Já vem configurado em `~/.config/opencode/commands/review.md`.

**Uso:**
```
/review                    # Commit + force push (histórico único)
```

**Comportamento:**
1. Detecta tipos de arquivos modificados (.sh → "Update", .md → "Docs")
2. Commita com mensagem automática
3. Limpa histórico (como forgejo.sh opção 6):
   - `git checkout --orphan newBranch`
   - `git commit` único
   - `git branch -D` + `git branch -m main`
   - `git push -f origin main`

**Pré-requisitos:** Repositório git com remote configurado.

---

## 🗂️ Estrutura

```
github-tools/
├── forgejo.sh              # Ferramenta Forgejo
├── github-tools.sh         # Ferramenta GitHub
├── review-disroot.md      # Documentação /review
├── LICENSE
└── README.md
```

**Nota:** O comando `/review` do OpenCode está em `~/.config/opencode/commands/review.md`.

---

## 📝 Notas

- Scripts usam `dd` (POSIX). Forgejo: nome repo = nome pasta.
- GitHub: requer `gh` CLI. OpenCode: comando em `~/.config/opencode/commands/`.
