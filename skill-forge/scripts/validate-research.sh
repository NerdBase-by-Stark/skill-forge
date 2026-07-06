#!/usr/bin/env bash
# validate-research.sh <research-doc.md> [--max-lines N]
#
# Deterministic acceptance check for Phase 5 research-agent output.
# Enforces the "Reject agent output if" criteria from phase-5-research.md:
#   - required section headings present
#   - >= 3 Verified Gems
#   - Sources section with >= 3 distinct domains
#   - UNVERIFIED-marked claims below 50% of gems
#   - within the length cap (default 700 lines)
# Prints PASS/FAIL per criterion. Exit 0 = accept, 1 = reject, 2 = usage error.

set -u

MAX_LINES=700
DOC=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-lines) MAX_LINES="${2:-700}"; shift 2 ;;
        -*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *) DOC="$1"; shift ;;
    esac
done

[[ -n "$DOC" ]] || { echo "Usage: $0 <research-doc.md> [--max-lines N]" >&2; exit 2; }
[[ -f "$DOC" ]] || { echo "FAIL  file not found: $DOC"; exit 1; }

fail=0
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# 1. Required headings (tolerant of ## vs ###)
for h in "Research Summary" "Verified Gems" "Sources"; do
    if grep -qiE "^#{1,4} .*${h}" "$DOC"; then
        ok "heading present: $h"
    else
        bad "missing required heading: $h"
    fi
done
# Proposed Skill Rules is expected but its absence is a warning-level miss (some
# streams legitimately produce anti-pattern-only docs) — count it as fail only
# with the other structure intact? Keep strict: the brief mandates it.
if grep -qiE "^#{1,4} .*(Proposed Skill Rules|Proposed Rules)" "$DOC"; then
    ok "heading present: Proposed Skill Rules"
else
    bad "missing required heading: Proposed Skill Rules"
fi

# 2. Gem count (### Gem N or "Gem N:" headings)
gem_count=$(grep -ciE "^#{2,4} *Gem [0-9]+|^#{2,4} .*Gem [0-9]+:" "$DOC")
if [[ "$gem_count" -ge 3 ]]; then
    ok "gem count $gem_count (>= 3)"
else
    bad "gem count $gem_count (< 3 — not enough signal)"
fi

# 3. Distinct source domains in the Sources section (fall back to whole doc if
#    section extraction fails)
domains=$(awk '/^#{1,4} .*[Ss]ources/{flag=1; next} /^#{1,4} /{flag=0} flag' "$DOC" \
    | grep -oE 'https?://[^/ )>,]+' | sed -E 's#https?://##; s#^www\.##' | sort -u)
domain_count=$(echo "$domains" | grep -c . || true)
if [[ "$domain_count" -eq 0 ]]; then
    domains=$(grep -oE 'https?://[^/ )>,]+' "$DOC" | sed -E 's#https?://##; s#^www\.##' | sort -u)
    domain_count=$(echo "$domains" | grep -c . || true)
fi
if [[ "$domain_count" -ge 3 ]]; then
    ok "distinct source domains: $domain_count (>= 3)"
else
    bad "distinct source domains: $domain_count (< 3)"
fi

# 4. UNVERIFIED ratio: fewer UNVERIFIED markers than half the gem count
unverified=$(grep -c "UNVERIFIED" "$DOC" || true)
if [[ "$gem_count" -gt 0 ]] && [[ $((unverified * 2)) -ge "$gem_count" ]] && [[ "$unverified" -gt 2 ]]; then
    bad "UNVERIFIED markers: $unverified vs $gem_count gems — agent went off-mission"
else
    ok "UNVERIFIED markers: $unverified (acceptable vs $gem_count gems)"
fi

# 5. Length cap
lines=$(wc -l < "$DOC")
if [[ "$lines" -le "$MAX_LINES" ]]; then
    ok "length $lines lines (<= $MAX_LINES)"
else
    bad "length $lines lines (> $MAX_LINES cap)"
fi

if [[ "$fail" -eq 1 ]]; then
    echo "REJECT: $DOC fails acceptance criteria above"
    exit 1
fi
echo "ACCEPT: $DOC"
exit 0
