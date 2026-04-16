#!/usr/bin/env bash
# skill-forge audit — static checks across one or more skills
# Usage: audit.sh <skill-path> [<skill-path> ...]
# Each <skill-path> is a directory containing SKILL.md.

set -u

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <skill-path> [<skill-path> ...]"
    echo "Example: $0 ~/.claude/skills/pyside6-desktop ~/.claude/skills/mass-deploy-ux"
    exit 1
fi

# Check for Python (needed for YAML parsing)
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found — required for YAML validation"
    exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "ERROR: python3 pyyaml not installed — run: pip install pyyaml"
    exit 1
fi

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

declare -a SKILLS=()
for path in "$@"; do
    if [[ ! -f "$path/SKILL.md" ]]; then
        echo "${RED}✗${NC} $path: no SKILL.md found"
        continue
    fi
    SKILLS+=("$path")
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo "${RED}No valid skills found${NC}"
    exit 1
fi

errors=0
warnings=0

# ============================================================================
# Per-skill checks
# ============================================================================
for skill in "${SKILLS[@]}"; do
    name=$(basename "$skill")
    echo "=== $name ==="

    main="$skill/SKILL.md"

    # --- YAML frontmatter validation ---
    yaml_check=$(python3 << EOF
import yaml, sys
with open("$main") as f:
    content = f.read()
if not content.startswith("---"):
    print("NO_FRONTMATTER"); sys.exit()
parts = content.split("---", 2)
if len(parts) < 3:
    print("MALFORMED"); sys.exit()
try:
    fm = yaml.safe_load(parts[1])
except Exception as e:
    print(f"PARSE_ERROR: {e}"); sys.exit()
missing = [k for k in ["name", "description"] if k not in fm]
if missing:
    print(f"MISSING: {missing}"); sys.exit()

desc = str(fm.get("description", "")).replace("\n", " ").strip()
fm_name = fm.get("name", "")
file_patterns = fm.get("filePattern", []) or []
bash_patterns = fm.get("bashPattern", []) or []

print(f"OK|{fm_name}|{len(desc)}|{len(file_patterns)}|{len(bash_patterns)}")
EOF
)

    case "$yaml_check" in
        NO_FRONTMATTER)
            echo "  ${RED}✗${NC} No YAML frontmatter"; errors=$((errors+1)); continue ;;
        MALFORMED)
            echo "  ${RED}✗${NC} Frontmatter malformed"; errors=$((errors+1)); continue ;;
        PARSE_ERROR:*)
            echo "  ${RED}✗${NC} ${yaml_check}"; errors=$((errors+1)); continue ;;
        MISSING:*)
            echo "  ${RED}✗${NC} ${yaml_check}"; errors=$((errors+1)); continue ;;
        OK|*)
            IFS='|' read -r _ fm_name desc_len fp_count bp_count <<< "$yaml_check"
            echo "  ${GREEN}✓${NC} Frontmatter valid"
            ;;
    esac

    # --- Name matches directory ---
    if [[ "$fm_name" != "$name" ]]; then
        echo "  ${RED}✗${NC} frontmatter name='$fm_name' ≠ dir name='$name'"
        errors=$((errors+1))
    else
        echo "  ${GREEN}✓${NC} name == directory name"
    fi

    # --- Description length ---
    if [[ "$desc_len" -gt 300 ]]; then
        echo "  ${YELLOW}⚠${NC}  Description is $desc_len chars (target ≤ 300)"
        warnings=$((warnings+1))
    else
        echo "  ${GREEN}✓${NC} Description $desc_len chars"
    fi

    # --- Main size ---
    main_lines=$(wc -l < "$main")
    main_chars=$(wc -c < "$main")
    main_tokens=$((main_chars / 4))
    if [[ $main_tokens -gt 2500 ]]; then
        echo "  ${YELLOW}⚠${NC}  Main SKILL.md is ~$main_tokens tokens (target ≤ 2500; consider refactor)"
        warnings=$((warnings+1))
    else
        echo "  ${GREEN}✓${NC} Main ~$main_tokens tokens ($main_lines lines)"
    fi

    # --- Rule coverage (if rules exist) ---
    # Progressive disclosure: a rule may appear inline in main SKILL.md AND in references/ (intentional).
    # True duplicates = same rule number in 2+ reference files, OR twice in main.
    main_rules=$(grep -hoE "^##+ Rule [0-9]+:" "$main" 2>/dev/null | grep -oE "[0-9]+" | sort -n)
    ref_rules_raw=$(if [[ -d "$skill/references" ]]; then
        for f in "$skill/references"/*.md; do
            [[ -f "$f" ]] && grep -hoE "^##+ Rule [0-9]+:" "$f" 2>/dev/null | grep -oE "[0-9]+" | while read n; do
                echo "$(basename $f):$n"
            done
        done
    fi | sort)

    # Main duplicates (same rule inline multiple times in main — an actual error)
    main_dups=$(echo "$main_rules" | uniq -d)
    # Cross-reference duplicates (same rule in 2+ reference files — an actual error)
    ref_only_nums=$(echo "$ref_rules_raw" | awk -F: '{print $2}' | sort)
    ref_dups=$(echo "$ref_only_nums" | uniq -d)

    if [[ -n "$main_dups" ]]; then
        echo "  ${RED}✗${NC} Rule(s) appear multiple times in main SKILL.md: $(echo $main_dups | tr '\n' ' ')"
        errors=$((errors+1))
    elif [[ -n "$ref_dups" ]]; then
        echo "  ${RED}✗${NC} Rule(s) appear in multiple reference files: $(echo $ref_dups | tr '\n' ' ')"
        errors=$((errors+1))
    else
        all_unique_nums=$(echo -e "$main_rules\n$ref_only_nums" | grep -v '^$' | sort -nu)
        count=$(echo "$all_unique_nums" | grep -c .)
        if [[ "$count" -gt 0 ]]; then
            first=$(echo "$all_unique_nums" | head -1)
            last=$(echo "$all_unique_nums" | tail -1)
            inline_count=$(echo "$main_rules" | grep -c . 2>/dev/null || echo 0)
            echo "  ${GREEN}✓${NC} $count unique rule numbers ($first-$last); $inline_count inlined in main"
        fi
    fi

    # --- References directory ---
    if [[ -d "$skill/references" ]]; then
        ref_count=$(find "$skill/references" -name "*.md" | wc -l)
        echo "  ${GREEN}✓${NC} $ref_count reference files"

        # Check each reference is mentioned in main
        for ref in "$skill/references"/*.md; do
            refname=$(basename "$ref")
            if ! grep -q "references/$refname" "$main"; then
                echo "  ${YELLOW}⚠${NC}  references/$refname not mentioned in main SKILL.md (orphan?)"
                warnings=$((warnings+1))
            fi
        done

        # Check each references/X.md referenced in main actually exists
        for ref_mentioned in $(grep -oE 'references/[a-z0-9_-]+\.md' "$main" | sort -u); do
            if [[ ! -f "$skill/$ref_mentioned" ]]; then
                echo "  ${RED}✗${NC} Main references $ref_mentioned but file doesn't exist"
                errors=$((errors+1))
            fi
        done

        # Flag bad-split patterns (tight refs with only 1-2 rules = likely mis-clustered)
        for ref in "$skill/references"/*.md; do
            refname=$(basename "$ref")
            ref_rule_count=$(grep -cE "^##+ Rule [0-9]+:" "$ref" 2>/dev/null || echo 0)
            # Only flag if the reference uses numbered rules at all (ref_rule_count > 0)
            # AND has fewer than 3. This catches under-clustered references without
            # spamming for non-rule-based reference files (templates, overviews).
            if [[ "$ref_rule_count" -gt 0 ]] && [[ "$ref_rule_count" -lt 3 ]]; then
                echo "  ${YELLOW}⚠${NC}  references/$refname has only $ref_rule_count rules — likely mis-clustered or needs merging with a related topic"
                warnings=$((warnings+1))
            fi
        done

        # Sanity-check inline critical rule count in main (5-8 is the target band per phase-7)
        # Skip this check for skills without numbered rules in main at all.
        if [[ -n "$main_rules" ]]; then
            main_rule_count=$(echo "$main_rules" | grep -c .)
            if [[ "$main_rule_count" -lt 5 ]] && [[ "$ref_count" -gt 0 ]]; then
                echo "  ${YELLOW}⚠${NC}  Only $main_rule_count rule(s) inline in main — progressive disclosure target is 5-8 critical rules"
                warnings=$((warnings+1))
            elif [[ "$main_rule_count" -gt 10 ]]; then
                echo "  ${YELLOW}⚠${NC}  $main_rule_count rules inlined in main — progressive disclosure target is 5-8; consider moving less-critical ones to references"
                warnings=$((warnings+1))
            fi
        fi
    fi

    echo
done

# ============================================================================
# Cross-skill checks
# ============================================================================
if [[ ${#SKILLS[@]} -gt 1 ]]; then
    echo "=== Cross-skill checks ==="
    overlap=$(python3 << EOF
import yaml, os, sys
skills = """$(printf '%s\n' "${SKILLS[@]}")"""
patterns = {}
for path in skills.strip().split("\n"):
    main = os.path.join(path, "SKILL.md")
    with open(main) as f:
        content = f.read()
    parts = content.split("---", 2)
    fm = yaml.safe_load(parts[1])
    patterns[os.path.basename(path)] = fm.get("filePattern", []) or []

pairs_with_overlap = []
skill_names = list(patterns.keys())
for i in range(len(skill_names)):
    for j in range(i+1, len(skill_names)):
        a, b = skill_names[i], skill_names[j]
        overlap_pats = set(patterns[a]) & set(patterns[b])
        if overlap_pats:
            pairs_with_overlap.append((a, b, overlap_pats))

if pairs_with_overlap:
    for a, b, o in pairs_with_overlap:
        print(f"⚠  {a} vs {b}: shared filePattern(s) {sorted(o)}")
else:
    print("✓ No identical filePattern overlaps between skills")
EOF
)
    echo "$overlap"
    echo
fi

# ============================================================================
# Summary
# ============================================================================
echo "=== Summary ==="
echo "  Skills checked: ${#SKILLS[@]}"
if [[ $errors -eq 0 ]] && [[ $warnings -eq 0 ]]; then
    echo "  ${GREEN}✓ All checks passed${NC}"
    exit 0
elif [[ $errors -eq 0 ]]; then
    echo "  ${YELLOW}⚠ $warnings warning(s), 0 errors${NC}"
    exit 0
else
    echo "  ${RED}✗ $errors error(s), $warnings warning(s)${NC}"
    exit 1
fi
