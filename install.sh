#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# dotfiles/install.sh — bootstrap eseguito da GitHub Codespaces
# alla creazione di OGNI codespace, su OGNI repository.
#
# Prerequisito: Codespaces secret WORKSPACE_PAT, con il repo corrente
#               abilitato nella sua lista "Repository access".
# Dipendenze:   git, npm (presenti nelle immagini devcontainer standard)
# ══════════════════════════════════════════════════════════════════
set -euo pipefail

readonly OWNER="biazzocarmelo33"
readonly REPO="carmelo-workspace"
readonly LIB="${HOME}/.${REPO}"
readonly BIN="${HOME}/.local/bin"
readonly CONF_DIR="${HOME}/.config"
readonly CREDFILE="${HOME}/.${REPO}.credentials"
readonly DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '[dotfiles] → %s\n' "$1"; }
# exit 0 volutamente: un errore qui non deve impedire la creazione
# del codespace — meglio ambiente parziale che nessun ambiente.
warn() { printf '[dotfiles] ✗ %s\n' "$1" >&2; exit 0; }

# ─── 1. Claude Code ───────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  log "Claude Code già presente"
else
  log "installo Claude Code"
  npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 || warn "npm install fallito"
fi

# ─── 2. Guard sul secret ──────────────────────────────────────────
[[ -n "${WORKSPACE_PAT:-}" ]] \
  || warn "WORKSPACE_PAT assente — questo repo è nella lista del secret?"

# ─── 3. Clone della libreria ──────────────────────────────────────
if [[ ! -d "${LIB}/.git" ]]; then
  log "clono ${REPO}"
  git clone --quiet \
    "https://x-access-token:${WORKSPACE_PAT}@github.com/${OWNER}/${REPO}.git" "$LIB" \
    || warn "clone fallito — PAT scaduto o repo fuori scope"
fi

# ─── 4. Credenziali: token fuori da .git/config ───────────────────
# Helper locale al repo: non interferisce con i repo di progetto,
# che continuano a usare il token nativo del codespace.
#
# L'helper di sistema dei Codespace (/etc/gitconfig) risponde per
# QUALSIASI repo github.com con il token ambientale, che copre solo
# il repo del codespace corrente. Git prova gli helper nell'ordine
# system → global → local e si ferma al primo che risponde con
# username+password, quindi quello di sistema intercetterebbe la
# richiesta prima che il nostro helper locale venga mai interpellato.
# Il valore vuoto azzera la catena ereditata per questo repo, cosicché
# resti attivo solo l'helper "store" impostato subito dopo.
git -C "$LIB" remote set-url origin "https://github.com/${OWNER}/${REPO}.git"
printf 'https://x-access-token:%s@github.com\n' "$WORKSPACE_PAT" > "$CREDFILE"
chmod 600 "$CREDFILE"
git -C "$LIB" config --unset-all credential.helper 2>/dev/null || true
git -C "$LIB" config --add credential.helper ""
git -C "$LIB" config --add credential.helper "store --file=${CREDFILE}"

# ─── 5. Installa skills-sync su PATH ──────────────────────────────
mkdir -p "$BIN" "$CONF_DIR"
cat > "${CONF_DIR}/skills-sync.env" <<EOF
LIB="${LIB}"
SKILLS_DEST="${HOME}/.claude/skills"
EOF
chmod +x "${DOTFILES_DIR}/skills-sync"
ln -sfn "${DOTFILES_DIR}/skills-sync" "${BIN}/skills-sync"

# Le immagini devcontainer non sempre includono ~/.local/bin nel PATH
grep -q '.local/bin' "${HOME}/.bashrc" 2>/dev/null \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
export PATH="${BIN}:${PATH}"

# ─── 6. Libreria aggiornata, nessun symlink alle skill ────────────
# Le skill arrivano dall'account claude.ai (sync di Claude Code):
# skills-sync aggiorna la libreria, toglie i vecchi link e controlla
# che la versione di Claude Code supporti la sync.
skills-sync || warn "skills-sync fallito — rilancialo a mano"
log "ambiente pronto"
