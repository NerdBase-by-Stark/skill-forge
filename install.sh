#!/usr/bin/env bash
# skill-forge installer — copies the skill + slash command into ~/.claude/
# Run from a cloned repo OR via: curl -sSL <raw-url>/install.sh | bash
#
# Modes:
#   install.sh              install / upgrade (default)
#   install.sh --check      compare installed copy against this repo; exit 1 on drift
#   install.sh --uninstall  remove installed skill + command (+ backups with --yes)

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

MODE="install"
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --check)     MODE="check" ;;
        --uninstall) MODE="uninstall" ;;
        --yes|-y)    ASSUME_YES=1 ;;
        *) die "Unknown flag: $arg (expected --check | --uninstall | --yes)" ;;
    esac
done

# ---- Determine source: local checkout vs remote clone ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/skill-forge/SKILL.md" ]] && [[ -f "$SCRIPT_DIR/command/skill-forge.md" ]]; then
    SOURCE="$SCRIPT_DIR"
elif [[ "$MODE" == "install" ]]; then
    # curl-pipe-bash mode — we need to clone first
    command -v git >/dev/null || die "git is required"
    TMP=$(mktemp -d)
    trap "rm -rf '$TMP'" EXIT
    info "Cloning $REPO_URL..."
    git clone --depth 1 "$REPO_URL" "$TMP/skill-forge" >/dev/null 2>&1
    SOURCE="$TMP/skill-forge"
else
    die "--check/--uninstall must run from a cloned repo"
fi

# The file set that constitutes an install (paths relative to repo root → install target)
install_pairs() {
    echo "skill-forge/SKILL.md|$INSTALL_DIR_SKILL/SKILL.md"
    for f in "$SOURCE/skill-forge/references/"*.md; do
        echo "skill-forge/references/$(basename "$f")|$INSTALL_DIR_SKILL/references/$(basename "$f")"
    done
    for f in "$SOURCE/skill-forge/scripts/"*.sh; do
        echo "skill-forge/scripts/$(basename "$f")|$INSTALL_DIR_SKILL/scripts/$(basename "$f")"
    done
    for f in "$SOURCE/skill-forge/schemas/"*.json; do
        echo "skill-forge/schemas/$(basename "$f")|$INSTALL_DIR_SKILL/schemas/$(basename "$f")"
    done
    for f in "$SOURCE/skill-forge/hooks/"*.sh; do
        echo "skill-forge/hooks/$(basename "$f")|$INSTALL_DIR_SKILL/hooks/$(basename "$f")"
    done
    echo "command/skill-forge.md|$INSTALL_CMD"
}

# ---- --check: drift detection ----
if [[ "$MODE" == "check" ]]; then
    drift=0
    while IFS='|' read -r src dst; do
        if [[ ! -f "$dst" ]]; then
            echo "MISSING  $dst"
            drift=1
        elif ! cmp -s "$SOURCE/$src" "$dst"; then
            echo "DIFFERS  $dst"
            drift=1
        else
            echo "OK       $dst"
        fi
    done < <(install_pairs)
    if [[ "$drift" -eq 1 ]]; then
        echo "${YELLOW}Installed copy differs from this repo — re-run install.sh to sync.${NC}"
        exit 1
    fi
    echo "${GREEN}Installed copy matches this repo.${NC}"
    exit 0
fi

# ---- --uninstall ----
if [[ "$MODE" == "uninstall" ]]; then
    [[ -d "$INSTALL_DIR_SKILL" ]] && rm -rf "$INSTALL_DIR_SKILL" && info "Removed $INSTALL_DIR_SKILL"
    [[ -f "$INSTALL_CMD" ]] && rm -f "$INSTALL_CMD" && info "Removed $INSTALL_CMD"
    backups=$(ls -d "$CLAUDE_DIR/skill-forge-backups"/skill-forge.bak-* "$INSTALL_DIR_SKILL".bak-* "$INSTALL_CMD".bak-* 2>/dev/null || true)
    if [[ -n "$backups" ]]; then
        if [[ "$ASSUME_YES" -eq 1 ]]; then
            echo "$backups" | xargs rm -rf
            info "Removed old backups"
        else
            warn "Backups left in place (re-run with --yes to remove):"
            echo "$backups"
        fi
    fi
    info "skill-forge uninstalled"
    exit 0
fi

# ---- Check dependencies ----
command -v python3 >/dev/null || warn "python3 not found — audit.sh needs it"
python3 -c "import yaml" 2>/dev/null || warn "python3 pyyaml not installed (pip install pyyaml) — audit.sh needs it"
command -v npx >/dev/null || warn "npx not found — Phase 3 (Find Candidates) needs it"
command -v jq >/dev/null || warn "jq not found — Phase 1 hook/MCP inventory prefers it (python3 fallback documented in phase-1)"

VERSION=$(grep -m1 '^version:' "$SOURCE/skill-forge/SKILL.md" | sed 's/^version:[[:space:]]*//' || true)
info "Installing skill-forge ${VERSION:-<no version field>} from $SOURCE"

# ---- Preserve existing install (if any) ----
if [[ -d "$INSTALL_DIR_SKILL" ]]; then
    BACKUP="$CLAUDE_DIR/skill-forge-backups/skill-forge.bak-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$CLAUDE_DIR/skill-forge-backups"
    warn "Existing skill-forge found — backing up to $BACKUP"
    mv "$INSTALL_DIR_SKILL" "$BACKUP"
fi
if [[ -f "$INSTALL_CMD" ]]; then
    BACKUP_CMD="$INSTALL_CMD.bak-$(date +%Y%m%d-%H%M%S)"
    warn "Existing command found — backing up to $BACKUP_CMD"
    mv "$INSTALL_CMD" "$BACKUP_CMD"
fi

# ---- Install ----
mkdir -p "$INSTALL_DIR_SKILL/references" "$INSTALL_DIR_SKILL/scripts" \
         "$INSTALL_DIR_SKILL/schemas" "$INSTALL_DIR_SKILL/hooks" "$(dirname "$INSTALL_CMD")"

while IFS='|' read -r src dst; do
    cp "$SOURCE/$src" "$dst"
done < <(install_pairs)
chmod +x "$INSTALL_DIR_SKILL/scripts/"*.sh "$INSTALL_DIR_SKILL/hooks/"*.sh

# ---- Provenance manifest ----
GIT_COMMIT=$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null || echo unknown)
{
    echo "version=${VERSION:-unknown}"
    echo "source_commit=$GIT_COMMIT"
    echo "source_path=$SOURCE"
    echo "installed_at=$(date -Is)"
    while IFS='|' read -r src dst; do
        echo "sha256 $(sha256sum "$dst" | awk '{print $1}')  $dst"
    done < <(install_pairs)
} > "$INSTALL_DIR_SKILL/.install-manifest"

# ---- Verify ----
test -f "$INSTALL_DIR_SKILL/SKILL.md" || die "Install failed: SKILL.md missing"
test -x "$INSTALL_DIR_SKILL/scripts/audit.sh" || die "Install failed: audit.sh not executable"
test -f "$INSTALL_CMD" || die "Install failed: slash command missing"
test -f "$INSTALL_DIR_SKILL/.install-manifest" || die "Install failed: manifest missing"

# ---- Prune old backups: keep only the most recent ----
old_backups=$(ls -dt "$CLAUDE_DIR/skill-forge-backups"/skill-forge.bak-* "$INSTALL_DIR_SKILL".bak-* 2>/dev/null | tail -n +2 || true)
if [[ -n "$old_backups" ]]; then
    echo "$old_backups" | xargs rm -rf
    info "Pruned older backups (kept most recent)"
fi
old_cmd_backups=$(ls -dt "$INSTALL_CMD".bak-* 2>/dev/null | tail -n +2 || true)
[[ -n "$old_cmd_backups" ]] && echo "$old_cmd_backups" | xargs rm -f

ref_count=$(find "$INSTALL_DIR_SKILL/references" -name "*.md" | wc -l)

# ---- Report ----
cat <<EOF

${GREEN}✓ skill-forge ${VERSION:-} installed${NC}

  Skill:          $INSTALL_DIR_SKILL/
                  (main SKILL.md + $ref_count reference files + scripts + schemas + hooks)
  Slash command:  $INSTALL_CMD
  Manifest:       $INSTALL_DIR_SKILL/.install-manifest

Optional but recommended — register the write-gate hook (blocks un-consented
writes to ~/.claude/skills/; see hooks/skill-write-gate.sh header for the
settings.json snippet).

Quick start in Claude Code:

  /skill-forge                       # full pipeline on the current project
  /skill-forge --phase=audit         # just audit existing skills
  bash $INSTALL_DIR_SKILL/scripts/audit.sh --self   # verify this install

Documentation: https://github.com/NerdBase-by-Stark/skill-forge

If skill-forge helps you, a ⭐ on the repo helps other Claude Code users find it.
EOF
