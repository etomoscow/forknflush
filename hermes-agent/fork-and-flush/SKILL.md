---
name: fork-and-flush
description: Long-horizon optimization with a deterministic scalar grader (algorithmic score maximization, cycle-count tuning, model compression) where a single run is likely to plateau. Forks K fresh-context workers from the best workspace and keeps the highest verified score. Not for bug fixes, features, or tasks without a numeric metric.
version: 1.0.0
metadata:
  hermes:
    tags: [optimization, search, agents, git]
    category: coding
---

# Fork-and-Flush

Single long runs get stuck refining one early approach. Fix: periodically fork K workers from the best workspace, each with an EMPTY chat context, run each briefly, keep the best. Both halves are needed: fork alone or flush alone gives less than both together.

## When to Use

- The task is long-horizon optimization with a deterministic scalar grader: algorithmic score maximization, cycle-count tuning, model compression.
- A single run is likely to plateau.
- Do NOT use for bug fixes, features, or tasks without a numeric metric.

## Procedure

### Preconditions

- `$EVAL`: one command printing one scalar, deterministic, higher is better. Record the baseline score. Optional: a target score for early stop.
- Budget B in one unit: number of `$EVAL` calls or worker-minutes (summed over parallel workers). Wrap `$EVAL` in `.ff/eval.sh`, which appends one line per call to a usage log at an absolute path.
- Clean git repo, base commit tagged `ff/base`. Copy the grader and its data to `.ff/grader/` outside any worktree.
- Workers share no mutable state outside their worktree (ports, GPU, caches, output dirs).

### Schedule

K=4 workers per round, each capped at 0.06·B (paper defaults). Rounds at t=0 (from `ff/base`), then when total usage, rejected branches included, reaches 33% and 66% of B. Between rounds one leader worker runs until the next trigger. Fixed schedule, no plateau detection. If 0.06·B is too small for a few edit-evaluate cycles, use fewer rounds. Your own verification runs are not charged to B.

### Protocol

You are a thin orchestrator: spawn, score, select. Don't do research yourself.

1. Fork: for k in 1..K run `git worktree add -b ff/r<round>-b<k> .ff/r<round>-b<k> <start>`, where start is `ff/base` in round 0, else the leader's best verified commit. Launch the K workers in parallel (subagents or headless CLI, e.g. `hermes` in print mode), each with a fresh context and the prompt below. Enforce the cap externally (timeout / max turns). If a worker halts early, resume it with "Continue improving the score" until the cap.
2. Select: for each branch take the commit with the highest claimed `score=`, check it out clean, restore `.ff/grader/`, run `$EVAL`. Use only your own score; if the claim doesn't reproduce, try the next claimed commit. A branch with no commits scores as its start commit.
3. Winner = best verified score among the K branches and, from round 1 on, the leader's pre-fork best. Ties go to the leader. The winner's worktree becomes the leader's: reset it to the winning commit, remove the other worktrees (keep branches). Append `round, branch, commit, score` to `.ff/ledger.tsv`.
4. Leader phase: resume the winner's session if possible, otherwise start a fresh worker in the leader worktree. Run until the next trigger, then verify its best commit as in step 2 before forking again.
5. Stop at B or when the target is reached. Verify the leader the same way. Report the best verified commit across all branches ever created and its score vs baseline.

### Worker prompt

```
<original task prompt, verbatim>
Workspace: <path>. Score with: <EVAL>. Current best: <number>.
Do not modify grader files or data. Commit each improvement as "score=<x>: <change>".
Stop after <b> <unit>.
```

## Pitfalls

- Branches get only the best score as a number: no history, summaries, or hints.
- Only committed state counts; uncommitted changes are discarded.
- Stay a thin orchestrator: spawn, score, select — don't do the research yourself.
- Workers must share no mutable state outside their worktree (ports, GPU, caches, output dirs).

## Verification

- Never trust a worker's reported number: check out the claimed commit clean, restore `.ff/grader/`, and run `$EVAL` yourself.
- If the claim doesn't reproduce, fall through to the next claimed commit; a branch with no commits scores as its start commit.
- Before each fork, verify the leader's best commit the same way; at stop, verify the leader and report the best verified commit across all branches ever created versus the baseline.
