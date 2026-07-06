#!/usr/bin/env bash
# skill-write-gate.sh — PreToolUse hook (Write|Edit) guarding ~/.claude/skills/
#
# Blocks any Write/Edit to a path under ~/.claude/skills/ unless a skill-forge
# consent marker exists in the invoking project's .skill-forge/ directory.
# Markers are created by the pipeline ONLY after an approved AskUserQuestion
# gate, and deleted when the phase ends:
#   .skill-forge/consent-phase4.ok   (Phase 3→4 first-pass approval gate)
#   .skill-forge/consent-phase6.ok   (Phase 5→6 second-pass approval gate)
#   .skill-forge/consent-phase7.ok   (Phase 6→7 structure/QA approval gate)
#
# Register in settings.json (user or project level):
#   { "hooks": { "PreToolUse": [ { "matcher": "Write|Edit",
#       "hooks": [{ "type": "command",
#                   "command": "bash <path-to>/skill-write-gate.sh" }] } ] } }
#
# Exit codes: 0 = allow, 2 = block (stderr shown to the model).
# Fail-open on malformed input: a hook bug must not brick unrelated edits.

set -u

command -v python3 &>/dev/null || exit 0

parsed=$(python3 -c '
import json, sys, os
try:
    d = json.load(sys.stdin)
except Exception:
    print("SKIP"); raise SystemExit
tool = d.get("tool_name", "")
if tool not in ("Write", "Edit"):
    print("SKIP"); raise SystemExit
fp = (d.get("tool_input") or {}).get("file_path", "") or ""
cwd = d.get("cwd", "") or os.getcwd()
print(os.path.expanduser(fp) + "\t" + cwd)
' 2>/dev/null)

[[ "$parsed" == "SKIP" || -z "$parsed" ]] && exit 0
file_path=${parsed%%$'\t'*}
cwd=${parsed#*$'\t'}

SKILLS_DIR="$HOME/.claude/skills/"
case "$file_path" in
    "$SKILLS_DIR"*) ;;
    *) exit 0 ;;   # not a skills write — allow
esac

# Consent markers live in the invoking project's .skill-forge/
for marker in consent-phase4.ok consent-phase6.ok consent-phase7.ok; do
    if [[ -f "$cwd/.skill-forge/$marker" ]]; then
        exit 0
    fi
done

echo "BLOCKED by skill-forge write gate: $file_path is under ~/.claude/skills/ and no consent marker exists in $cwd/.skill-forge/. Writes to the user's skill library require an approved AskUserQuestion gate first (which creates consent-phase4/6/7.ok). Do not bypass this; present the change block and ask." >&2
exit 2
