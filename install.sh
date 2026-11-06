#!/usr/bin/env bash
# forknflush installer (macOS / Linux)
#
# Usage:
#   ./install.sh                          Prompt for platform
#   ./install.sh <platform>...            Install for one or more platforms (or "all")
#   ./install.sh --update                 Pull latest changes
#   ./install.sh --uninstall <plat>...    Remove links for platform(s) (or "all")
#   ./install.sh --help
#
# Curl-pipe usage:
#   curl -fsSL https://raw.githubusercontent.com/etomoscow/forknflush/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/etomoscow/forknflush/main/install.sh | bash -s codex
#   curl -fsSL https://raw.githubusercontent.com/etomoscow/forknflush/main/install.sh | bash -s all
#
# Environment:
#   FF_REPO_URL  Override clone URL (default: official GitHub repo)
#   FF_DIR       Override clone destination (default: $HOME/.forknflush/repo)

set -euo pipefail

REPO_URL="${FF_REPO_URL:-https://github.com/etomoscow/forknflush.git}"
REPO_DIR="${FF_DIR:-$HOME/.forknflush/repo}"

# Platform table — id|skills-target-dir|style
# style "per-skill": one symlink per skill into the target dir
# style "folder":    one symlink for the whole skills/ dir into the target,
#                    named "forknflush"
platforms_table() {
  cat <<EOF
claude|$HOME/.claude/skills|per-skill
pi|$HOME/.agents/skills|per-skill
codex|$HOME/.agents/skills|per-skill
opencode|$HOME/.agents/skills|per-skill
hermes|$HOME/.hermes/skills|folder
EOF
}

platform_ids() { platforms_table | cut -d'|' -f1; }

resolve_platform() {
  local id="$1"
  local row
  row="$(platforms_table | awk -F'|' -v id="$id" '$1==id {print; exit}')"
  if [[ -z "$row" ]]; then
    printf 'Unknown platform: %s\n' "$id" >&2
    printf 'Supported: %s all\n' "$(platform_ids | tr '\n' ' ')" >&2
    exit 1
  fi
  printf '%s\n' "$row"
}

expand_platforms() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "all" ]]; then
      platform_ids
    else
      printf '%s\n' "$arg"
    fi
  done
}

prompt_platform() {
  local ids=()
  while IFS= read -r id; do ids+=("$id"); done < <(platform_ids)
  ids+=("all")

  printf 'Which platform are you installing for?\n' >&2
  local i=1
  for id in "${ids[@]}"; do
    printf '  %d) %s\n' "$i" "$id" >&2
    i=$((i+1))
  done
  printf 'Choose [1-%d]: ' "${#ids[@]}" >&2

  local choice=""
  if { exec 3</dev/tty; } 2>/dev/null; then
    read -r choice <&3 || true
    exec 3<&-
  else
    read -r choice || true
  fi
  if [[ -z "$choice" ]]; then
    printf '\nNo input received. Pass the platform as an argument instead, e.g.:\n' >&2
    printf '  install.sh codex\n' >&2
    exit 1
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ids[@]} )); then
    printf 'Invalid choice: %s\n' "$choice" >&2
    exit 1
  fi
  printf '%s\n' "${ids[$((choice-1))]}"
}

clone_or_update() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    printf -- '→ Updating existing checkout at %s\n' "$REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
  else
    printf -- '→ Cloning %s → %s\n' "$REPO_URL" "$REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  fi
}

skills_root() { printf '%s\n' "$REPO_DIR/forknflush-plugin/skills"; }

list_skills() {
  local root
  root="$(skills_root)"
  if [[ ! -d "$root" ]]; then
    printf 'Skills directory not found: %s\n' "$root" >&2
    exit 1
  fi
  local d
  for d in "$root"/*/; do
    [[ -d "$d" ]] || continue
    basename "$d"
  done
}

link_skills() {
  local target="$1" style="$2"
  local root
  root="$(skills_root)"
  mkdir -p "$target"
  case "$style" in
    per-skill)
      local skill
      while IFS= read -r skill; do
        ln -sfn "$root/$skill" "$target/$skill"
        printf '  ✓ %s → %s\n' "$target/$skill" "$root/$skill"
      done < <(list_skills)
      ;;
    folder)
      ln -sfn "$root" "$target/forknflush"
      printf '  ✓ %s → %s\n' "$target/forknflush" "$root"
      ;;
    *)
      printf 'Unknown style: %s\n' "$style" >&2
      exit 1
      ;;
  esac
}

unlink_skills() {
  local target="$1" style="$2"
  [[ -d "$target" ]] || return 0
  case "$style" in
    per-skill)
      if [[ -d "$(skills_root)" ]]; then
        local skill
        while IFS= read -r skill; do
          if [[ -L "$target/$skill" ]]; then
            rm -f "$target/$skill"
          fi
        done < <(list_skills)
      else
        local link resolved
        for link in "$target"/*; do
          [[ -L "$link" ]] || continue
          resolved="$(readlink "$link" 2>/dev/null || true)"
          [[ "$resolved" == *"/forknflush-plugin/skills/"* ]] || continue
          rm -f "$link"
        done
      fi
      ;;
    folder)
      if [[ -L "$target/forknflush" ]]; then
        rm -f "$target/forknflush"
      fi
      ;;
  esac
}

install_one() {
  local id="$1"
  local row target style
  row="$(resolve_platform "$id")"
  target="$(printf '%s\n' "$row" | cut -d'|' -f2)"
  style="$(printf '%s\n' "$row" | cut -d'|' -f3)"

  printf -- '→ Linking skills for %s (%s → %s)\n' "$id" "$style" "$target"
  link_skills "$target" "$style"

  if [[ "$id" == "claude" ]]; then
    printf '  Tip (Claude Code): you can also install via `/plugin marketplace add etomoscow/forknflush` then `/plugin install forknflush`.\n'
  elif [[ "$id" == "codex" ]]; then
    printf '  Tip (Codex): invoke with $fork-and-flush (not /fork-and-flush).\n'
  elif [[ "$id" == "pi" ]]; then
    printf '  Tip (Pi): invoke with /skill:fork-and-flush.\n'
  elif [[ "$id" == "hermes" ]]; then
    printf '  Tip (Hermes): ~/.hermes/skills loads automatically; project-local skills need `hermes skills trust`.\n'
  fi
}

cmd_install() {
  local platforms=()
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    resolve_platform "$p" >/dev/null
    platforms+=("$p")
  done < <(expand_platforms "$@")

  clone_or_update
  local id
  for id in "${platforms[@]}"; do
    install_one "$id"
  done
  printf '\n✓ Installed forknflush (%s). Restart your CLI to pick up the skill.\n' "${platforms[*]}"
}

cmd_uninstall() {
  local platforms=()
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    resolve_platform "$p" >/dev/null
    platforms+=("$p")
  done < <(expand_platforms "$@")

  local id row target style
  for id in "${platforms[@]}"; do
    row="$(resolve_platform "$id")"
    target="$(printf '%s\n' "$row" | cut -d'|' -f2)"
    style="$(printf '%s\n' "$row" | cut -d'|' -f3)"
    printf -- '→ Removing skill links for %s\n' "$id"
    unlink_skills "$target" "$style"
  done

  if [[ -d "$REPO_DIR" ]]; then
    printf '\nThe checkout at %s was kept (other platforms may still use it).\n' "$REPO_DIR"
    printf 'To remove it: rm -rf "%s"\n' "$REPO_DIR"
  fi
}

cmd_update() {
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    printf 'No installation found at %s. Run install first.\n' "$REPO_DIR" >&2
    exit 1
  fi
  git -C "$REPO_DIR" pull --ff-only
  printf '✓ Updated.\n'
}

usage() {
  cat <<USAGE
forknflush installer

Usage:
  install.sh [<platform>...]            Install for platform(s) or "all" (prompts if omitted)
  install.sh --update                   Pull latest changes (skills update through symlinks)
  install.sh --uninstall <platform>...  Remove links for platform(s) or "all"
  install.sh --help

Supported platforms:
$(platform_ids | sed 's/^/  - /')
  - all

Environment:
  FF_REPO_URL  Override clone URL (default: official repo)
  FF_DIR       Override clone destination (default: \$HOME/.forknflush/repo)
USAGE
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    --update)
      cmd_update
      ;;
    --uninstall)
      shift
      if [[ $# -eq 0 ]]; then
        printf '%s\n' '--uninstall requires at least one platform argument (or "all")' >&2
        usage >&2
        exit 1
      fi
      cmd_uninstall "$@"
      ;;
    "")
      local id
      id="$(prompt_platform)"
      cmd_install "$id"
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      cmd_install "$@"
      ;;
  esac
}

main "$@"
