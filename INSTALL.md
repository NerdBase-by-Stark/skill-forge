# Install

## One-line (recommended)

```bash
curl -sSL https://raw.githubusercontent.com/NerdBase-by-Stark/skill-forge/main/install.sh | bash
```

The script:
1. Creates `~/.claude/skills/skill-forge/` and `~/.claude/commands/` if they don't exist
2. Downloads the skill + slash command + audit script
3. Sets executable permissions on `audit.sh`
4. Prints usage hint

It does NOT touch any other files under `~/.claude/`.

## Manual

```bash
# Clone
git clone https://github.com/NerdBase-by-Stark/skill-forge.git
cd skill-forge

# Install into user-level Claude Code config
./install.sh

# Or manually:
mkdir -p ~/.claude/skills ~/.claude/commands
cp -r skill-forge ~/.claude/skills/
chmod +x ~/.claude/skills/skill-forge/scripts/audit.sh
cp command/skill-forge.md ~/.claude/commands/
```

## Per-project (not recommended)

You can install `skill-forge` as a project-level command + skill if you want it scoped to one repo:

```bash
# From inside your target project's root:
mkdir -p .claude/skills .claude/commands
cp -r /path/to/skill-forge-repo/skill-forge .claude/skills/
chmod +x .claude/skills/skill-forge/scripts/audit.sh
cp /path/to/skill-forge-repo/command/skill-forge.md .claude/commands/
```

User-level install is preferred because `/skill-forge` is meant to operate on arbitrary projects.

## Dependencies

- Claude Code (any recent version with skill + slash-command support)
- `bash` + `python3` with `pyyaml` (for `audit.sh`)
- `git` (for Phase 3 cloning)
- `npx` (for Phase 3 `npx skills find`)

Install missing Python dep: `pip install pyyaml` (or `pip3 install pyyaml`).

## Verify the install

In Claude Code, run:

```
/skill-forge --phase=audit
```

You should see an audit report printed for the current project's skills (or a message that no relevant skills were found, which is also fine).

## Uninstall

```bash
rm -rf ~/.claude/skills/skill-forge
rm ~/.claude/commands/skill-forge.md
```

Skills you created with skill-forge's help are unaffected — only the tool itself is removed.
