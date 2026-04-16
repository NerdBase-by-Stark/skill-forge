#!/usr/bin/env bash
# skill-forge installer — copies the skill + slash command into ~/.claude/
# Run from a cloned repo OR via: curl -sSL <raw-url>/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/NerdBase-by-Stark/skill-forge.git"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
INSTALL_DIR_SKILL="$CLAUDE_DIR/skills/skill-forge"
INSTALL_CMD="$CLAUDE_DIR/commands/skill-forge.md"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

info() { echo "${GREEN}✓${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC}  $*"; }
die()  { echo "${RED}✗${NC} $*" >&2; exit 1; }

# ---- Determine source: local checkout vs remote clone ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/skill-forge/SKILL.md" ]] && [[ -f "$SCRIPT_DIR/command/skill-forge.md" ]]; then
    SOURCE="$SCRIPT_DIR"
    info "Using local checkout: $SOURCE"
else
    # curl-pipe-bash mode — we need to clone first
    command -v git >/dev/null || die "git is required"
    TMP=$(mktemp -d)
    trap "rm -rf '$TMP'" EXIT
    info "Cloning $REPO_URL..."
    git clone --depth 1 "$REPO_URL" "$TMP/skill-forge" >/dev/null 2>&1
    SOURCE="$TMP/skill-forge"
fi

# ---- Check dependencies ----
command -v python3 >/dev/null || warn "python3 not found — audit.sh needs it"
python3 -c "import yaml" 2>/dev/null || warn "python3 pyyaml not installed (pip install pyyaml) — audit.sh needs it"
command -v npx >/dev/null || warn "npx not found — Phase 3 (Find Candidates) needs it"

# ---- Preserve existing install (if any) ----
if [[ -d "$INSTALL_DIR_SKILL" ]]; then
    BACKUP="$INSTALL_DIR_SKILL.bak-$(date +%Y%m%d-%H%M%S)"
    warn "Existing skill-forge found — backing up to $BACKUP"
    mv "$INSTALL_DIR_SKILL" "$BACKUP"
fi
if [[ -f "$INSTALL_CMD" ]]; then
    BACKUP="$INSTALL_CMD.bak-$(date +%Y%m%d-%H%M%S)"
    warn "Existing command found — backing up to $BACKUP"
    mv "$INSTALL_CMD" "$BACKUP"
fi

# ---- Install ----
mkdir -p "$INSTALL_DIR_SKILL/references" "$INSTALL_DIR_SKILL/scripts" "$(dirname "$INSTALL_CMD")"

cp "$SOURCE/skill-forge/SKILL.md" "$INSTALL_DIR_SKILL/"
cp "$SOURCE/skill-forge/references/"*.md "$INSTALL_DIR_SKILL/references/"
cp "$SOURCE/skill-forge/scripts/audit.sh" "$INSTALL_DIR_SKILL/scripts/"
chmod +x "$INSTALL_DIR_SKILL/scripts/audit.sh"
cp "$SOURCE/command/skill-forge.md" "$INSTALL_CMD"

# ---- Verify ----
test -f "$INSTALL_DIR_SKILL/SKILL.md" || die "Install failed: SKILL.md missing"
test -x "$INSTALL_DIR_SKILL/scripts/audit.sh" || die "Install failed: audit.sh not executable"
test -f "$INSTALL_CMD" || die "Install failed: slash command missing"

ref_count=$(find "$INSTALL_DIR_SKILL/references" -name "*.md" | wc -l)

# ---- Report ----
cat <<EOF

${GREEN}✓ skill-forge installed${NC}

  Skill:          $INSTALL_DIR_SKILL/
                  (main SKILL.md + $ref_count reference files + audit.sh)
  Slash command:  $INSTALL_CMD

Quick start in Claude Code:

  /skill-forge                       # full pipeline on the current project
  /skill-forge --phase=audit         # just audit existing skills
  /skill-forge --help                # show all flags

Documentation: https://github.com/NerdBase-by-Stark/skill-forge

If skill-forge helps you, a ⭐ on the repo helps other Claude Code users find it.
EOF
