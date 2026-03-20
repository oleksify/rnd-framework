---
description: "Plan and manage multi-session roadmaps for large tasks that span multiple days."
argument-hint: "<broad task description for new roadmap | empty to manage existing>"
effort: high
---

# R&D Framework: Roadmap

Plan and manage a multi-session roadmap. If no roadmap exists for this project, create one by decomposing a broad goal into milestones. If a roadmap exists, show progress and let you continue, park, or extend it.

## Setup

```bash
ROADMAP=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap)
```

## Branch: Existing vs New Roadmap

Check whether the roadmap file exists:

```bash
test -f "$ROADMAP" && echo "exists" || echo "missing"
```

- If `missing`: proceed to **Scenario 1: Create New Roadmap**.
- If `exists`: proceed to **Scenario 2: Manage Existing Roadmap**.

## Scenario 1: Create New Roadmap

### 1. Get the broad task description

If `$ARGUMENTS` is non-empty, use it as the goal. If empty, use `AskUserQuestion`:

> "What multi-session goal do you want to map out?"

Options:
- "Describe the goal" — user types a free-form description
- "I'll start from scratch with guidance" — proceed with an open-ended decomposition

### 2. Spawn the Planner in roadmap mode

Spawn an agent with `subagent_type: "rnd-framework:rnd-planner"`. Pass this prompt:

> **Roadmap mode.** Decompose the following broad goal into 3–7 milestones following
> the `rnd-framework:rnd-roadmapping` skill format. Each milestone must be
> independently valuable, scoped to roughly one pipeline session, and described in
> enough detail that its Description can be pasted into `/rnd-framework:start`.
> Write the completed roadmap.md to: `$ROADMAP`
> Goal: `$ARGUMENTS` (or the user's stated goal if $ARGUMENTS was empty)

After the Planner finishes, read `$ROADMAP` and display its full contents.

### 3. Post-creation options

Use `AskUserQuestion`:

Options:
- "Start first milestone (Recommended)" — find the first `NOT_STARTED` milestone, confirm
  its description, then invoke `/rnd-framework:start` with that milestone's Description
- "Review milestones" — re-display the roadmap and re-present this menu
- "Finish — start later" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish`
  and tell the user the roadmap is saved at `$ROADMAP`

## Scenario 2: Manage Existing Roadmap

### 1. Read and display status

Read `$ROADMAP`. Parse out the milestones and render a progress table:

| # | Milestone | Status | Session |
|---|-----------|--------|---------|
| M1 | [title] | NOT_STARTED / IN_PROGRESS / DONE / SKIPPED | [session or —] |

Print the table and an overall summary, e.g. "2 of 5 milestones complete."

### 2. Management options

Use `AskUserQuestion`. Recommend "Continue next milestone" if a `NOT_STARTED`
milestone exists; recommend "View milestone details" if all are `DONE`.

Options:
- "Continue next milestone (Recommended)" — find first `NOT_STARTED` milestone
- "Park current work" — record progress on an `IN_PROGRESS` milestone
- "Add milestones" — append new milestones to the roadmap
- "View milestone details" — show full descriptions of all milestones

### Continue next milestone

1. Find the first milestone with status `NOT_STARTED`.
2. Display its title and description.
3. Confirm with `AskUserQuestion`: "Start this milestone now?" — "Yes, start now" / "Cancel".
4. On confirm: update `$ROADMAP` — set status to `IN_PROGRESS`, write current session ID
   (from `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`) to its Session field. Then invoke
   `/rnd-framework:start` with the milestone's Description as the task.

### Park current work

1. Find the first `IN_PROGRESS` milestone. If none, inform the user and re-present options.
2. Use `AskUserQuestion` to collect progress details:
   - "What has been completed so far?"
   - "What remains to reach SHIP?"
3. Write `**Progress:**` and `**Remaining:**` fields to the milestone in `$ROADMAP`.
   Keep status as `IN_PROGRESS`. Update `Last updated` to today's date.
4. Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish`. Confirm roadmap is saved.

### Add milestones

Ask the user to describe the new milestone(s) via `AskUserQuestion`. Append them to
`$ROADMAP` following the `rnd-framework:rnd-roadmapping` skill format, with status
`NOT_STARTED`. Update `Last updated`. Re-display the status table and re-present options.

### View milestone details

Display each milestone's full section from `$ROADMAP` (title, status, description,
session, and delivered/progress/remaining fields if present). Then re-present the
management options via `AskUserQuestion`.
