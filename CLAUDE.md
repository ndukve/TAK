## Required modes: caveman and ponytail

Both are mandatory in every session in this repo.

- **caveman** (`caveman:caveman` skill): keep chat replies terse. Drop filler, articles, and pleasantries; keep technical terms, code, commands, paths, and errors exact. Files, commit messages, and docs written to disk stay in normal prose.
- **ponytail** (`ponytail` skill): lazy-senior-dev mode for code. Before writing anything, climb the ladder: needed at all? already in this codebase? stdlib? native feature? installed dependency? one line? Only then write the minimum. Fix bugs at the root cause (grep every caller), not per symptom. Never lazy about understanding the problem, input validation at trust boundaries, security, or anything explicitly requested.

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Instructions for Claude

- **Never run `git commit` or `git push`.** Stage changes with `git add <exact files>` (never `git add -A`/`git add .`) and stop there. The user commits and pushes everything themselves, manually, on their own schedule.

<!-- rtk-instructions v2 -->

- Data lives under `TAK_DATA_DIR` (default `/srv/tak-data`, bind mounts), not Docker volumes (`scripts/data_dir.sh`, doc 08); `backup.sh` reads it as root. CoT retention is `TAK_RETENTION_COT_DAYS` + `TAK_RETENTION_CRON` in `takserver.env` (cron `-` means never purge).
- Update the docs (English and Lithuanian) and the agent notes in the same change as the code, every time.
- Script colour: NATO blue `#004990` is chosen by terminal capability in each host script (`_NB`: truecolor exact, 256-colour `38;5;24`, else standard blue `0;34`); the Proxmox/Linux console has no 24-bit colour and showed cyan. Do not hardcode the truecolor escape again.

# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk proxy <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
<!-- /rtk-instructions -->- WebUI design direction (2026-10-23): the console follows the layout of NetBird's dashboard in NATO blue (`#004990`): fixed top bar, collapsible grouped sidebar (`admin/ui/src/components/Layout.tsx`). NetBird's dashboard is AGPL-3.0: never copy its code, class strings, icons, logo or assets here; the layout is written independently from its structure only. Default accent (`api/branding.py`, `api/models.py`, `ui/src/store/branding.ts`) is NATO blue; an existing database keeps its stored accent.

## Project knowledge for agents

- WebUI look (2026-10-24): kept in step with EFDI-Core's admin UI (NetBird-style shell: top bar with help and user menus, info bar via `store/announcement.ts`, dense Dashboard, no corner brackets). NetBird's dashboard is AGPL-3.0: never copy its code, class strings, icons or assets; write from the structure only. The topology, device names and vulnerability panel of EFDI-Core are not ported (TAK has no router graph).
