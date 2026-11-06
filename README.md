# forknflush

One skill — **fork-and-flush** — packaged for five agent CLIs.

Fork-and-flush is a protocol for long-horizon optimization tasks with a deterministic scalar grader (algorithmic score maximization, cycle-count tuning, model compression) where a single agent run is likely to plateau: periodically fork K fresh-context workers from the best workspace and keep the highest verified score.

All five packages implement the same skill and follow the [Agent Skills](https://agentskills.io) open standard: a directory with a `SKILL.md` file carrying `name` and `description` frontmatter.

## Layout

| Harness | Source in this repo | Extra files |
|---|---|---|
| Claude Code | `claude-code/fork-and-flush/` | — |
| Pi | `pi/fork-and-flush/` | — |
| Codex | `codex/fork-and-flush/` | `agents/openai.yaml` (UI metadata) |
| Hermes Agent | `hermes-agent/fork-and-flush/` | hermes-flavored sections & metadata |
| OpenCode | `opencode/fork-and-flush/` | — |

## Install

Copy the variant you need into the harness's skill location (project-local or personal).

| Harness | Project-local | Personal / global | Invoke |
|---|---|---|---|
| Claude Code | `<repo>/.claude/skills/` | `~/.claude/skills/` | `/fork-and-flush` |
| Pi | `<repo>/.agents/skills/` | `~/.agents/skills/` | `/skill:fork-and-flush` |
| Codex | `<repo>/.agents/skills/` | `~/.agents/skills/` | `$fork-and-flush` or `/skills` |
| Hermes Agent | `<repo>/.hermes/skills/` | `~/.hermes/skills/` | `/fork-and-flush` |
| OpenCode | `<repo>/.opencode/skills/` | `~/.config/opencode/skills/` | automatic via the `skill` tool |

Examples:

```bash
# Claude Code, personal
cp -r claude-code/fork-and-flush ~/.claude/skills/

# Pi, project (also natively reads .agents/skills/, like Codex)
mkdir -p .agents/skills && cp -r pi/fork-and-flush .agents/skills/

# Codex, project (scans .agents/skills from the working dir up to the repo root)
mkdir -p .agents/skills && cp -r codex/fork-and-flush .agents/skills/

# Hermes Agent, personal (then run `hermes` in the project; project skills need `hermes skills trust`)
cp -r hermes-agent/fork-and-flush ~/.hermes/skills/

# OpenCode, project
mkdir -p .opencode/skills && cp -r opencode/fork-and-flush .opencode/skills/
```

Notes:

- **Pi**: alternatively register any directory via the `skills` array in `~/.pi/agent/settings.json` or project `.pi/settings.json`; `.agents/skills/` works without configuration.
- **Hermes Agent**: project-local skills (`.hermes/skills/`) are only loaded after `hermes skills trust`; personal skills under `~/.hermes/skills/` load unconditionally.
- **Codex**: the optional `agents/openai.yaml` adds display metadata; you can omit it.
- **OpenCode**: also discovers Claude-compatible `.claude/skills/` and agent-compatible `.agents/skills/` locations, so the Claude Code or Codex variants work there too.
- The skill name must match the directory name (`fork-and-flush`) — keep it when renaming.

## The skill

Each `SKILL.md` is self-contained: preconditions (`$EVAL` grader, budget B, clean git repo with `ff/base` tag), a fixed schedule (K=4 workers per round at 0%, 33%, 66% of budget, each capped at 0.06·B), a fork/select/leader protocol over `git worktree`s, the exact worker prompt, and verification rules (only your own reproduced `score=` counts).
