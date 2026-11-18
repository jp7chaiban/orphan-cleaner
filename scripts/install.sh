#!/usr/bin/env bash
# macOS / Linux installer: installs the `orphan-cleaner` command and, with --skill, the agent skill.
# Re-run to update.
#
#   scripts/install.sh                 command only, into ~/.local/bin (override with BIN_DIR=...)
#   scripts/install.sh --skill         command + skill into ~/.claude/skills (override with SKILL_DIR=...)
#   scripts/install.sh --skill-only    skill only
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
bin_dir="${BIN_DIR:-$HOME/.local/bin}"
skill_dir="${SKILL_DIR:-$HOME/.claude/skills}"
want_cmd=1; want_skill=0
for arg in "$@"; do
  case "$arg" in
    --skill) want_skill=1 ;;
    --skill-only) want_skill=1; want_cmd=0 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ "$want_cmd" = 1 ]; then
  mkdir -p "$bin_dir"
  cp "$repo/skills/orphan-cleaner/scripts/orphan-cleaner.sh" "$bin_dir/orphan-cleaner"
  chmod 755 "$bin_dir/orphan-cleaner"
  echo "Installed $bin_dir/orphan-cleaner"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "Note: $bin_dir is not on your PATH. Add it, e.g.: echo 'export PATH=\"$bin_dir:\$PATH\"' >> ~/.profile" ;;
  esac
fi

if [ "$want_skill" = 1 ]; then
  dest="$skill_dir/orphan-cleaner"
  mkdir -p "$skill_dir"
  rm -rf "$dest"
  cp -R "$repo/skills/orphan-cleaner" "$dest"
  chmod 755 "$dest/scripts/orphan-cleaner.sh"
  echo "Installed the agent skill to $dest"
fi
