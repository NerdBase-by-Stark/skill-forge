#!/usr/bin/env bash
# validate-profile.sh <profile.json> — validate a Phase 1 profile against
# schemas/profile.schema.json. Exit 0 = valid, 1 = invalid (reasons on stdout),
# 2 = usage/dependency error.
#
# Uses python3 stdlib json; uses the jsonschema package if importable, else
# falls back to hand-rolled required-key/type checks covering the same
# required fields. Zero mandatory dependencies beyond python3.

set -u

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <profile.json>" >&2
    exit 2
fi

PROFILE="$1"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCHEMA="$(dirname "$SCRIPT_DIR")/schemas/profile.schema.json"

if [[ ! -f "$PROFILE" ]]; then
    echo "FAIL: profile not found: $PROFILE"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found" >&2
    exit 2
fi

python3 - "$PROFILE" "$SCHEMA" << 'EOF'
import json, sys

profile_path, schema_path = sys.argv[1], sys.argv[2]

try:
    with open(profile_path) as f:
        profile = json.load(f)
except json.JSONDecodeError as e:
    print(f"FAIL: profile is not valid JSON: {e}")
    sys.exit(1)

if not isinstance(profile, dict):
    print("FAIL: profile top level must be a JSON object")
    sys.exit(1)

# Preferred path: real jsonschema validation
try:
    import jsonschema  # type: ignore
    with open(schema_path) as f:
        schema = json.load(f)
    errors = sorted(jsonschema.Draft7Validator(schema).iter_errors(profile), key=lambda e: list(e.path))
    if errors:
        for e in errors:
            loc = "/".join(str(p) for p in e.path) or "(root)"
            print(f"FAIL: {loc}: {e.message}")
        sys.exit(1)
    print("PASS: profile valid (jsonschema)")
    sys.exit(0)
except ImportError:
    pass

# Fallback: hand-rolled checks mirroring the schema's required fields + types
fails = []
def need(key, typ, typname):
    if key not in profile:
        fails.append(f"missing required field: {key}")
    elif not isinstance(profile[key], typ):
        fails.append(f"{key} must be {typname}, got {type(profile[key]).__name__}")

need("profile_schema_version", int, "integer")
need("project_root", str, "string")
need("project_name", str, "string")
need("languages", list, "array")
need("tech_stack_tags", list, "array")
need("relevant_skills", list, "array")

for i, s in enumerate(profile.get("relevant_skills", []) if isinstance(profile.get("relevant_skills"), list) else []):
    if not isinstance(s, dict):
        fails.append(f"relevant_skills[{i}] must be an object")
        continue
    for k in ("name", "match_reason"):
        if not isinstance(s.get(k), str) or not s.get(k):
            fails.append(f"relevant_skills[{i}].{k} missing or not a non-empty string")

for k in ("project_local_skills", "active_hooks", "available_mcp_servers",
          "local_knowledge_bases", "sub_projects", "memory_files"):
    if k in profile and not isinstance(profile[k], list):
        fails.append(f"{k} must be an array, got {type(profile[k]).__name__}")

if "usage_telemetry" in profile and profile["usage_telemetry"] is not None and not isinstance(profile["usage_telemetry"], dict):
    fails.append(f"usage_telemetry must be an object or null, got {type(profile['usage_telemetry']).__name__}")

if fails:
    for f_ in fails:
        print(f"FAIL: {f_}")
    sys.exit(1)

print("PASS: profile valid (fallback checks; install python3-jsonschema for full validation)")
sys.exit(0)
EOF
