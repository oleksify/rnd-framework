# Changelog

## 0.16.2 — 2026-06-06

### Steer exploration in rnd-start, rnd-audit, rnd-review, and rnd-debug to rnd-explorer instead of the native Explore agent

Extends the rnd-brainstorm fix across the other broad-exploration commands. rnd-start's Phase 0 note already warned against the native Explore (0 tool uses) but never offered rnd-explorer as the broad-sweep escalation; rnd-audit/rnd-review/rnd-debug had no local steering at all. Each now directs genuine codebase sweeps to the read-only rnd-explorer and away from the built-in Explore/general-purpose agents, which fail to spawn in MCP-heavy sessions. rnd-scan is excluded by design (fixed inline glob checklist).

## 0.16.1 — 2026-06-06

### Steer rnd-brainstorm codebase grounding to rnd-explorer instead of the native Explore agent

The brainstorm command had no local exploration guidance and opened with a blanket "No agents" framing, so when it needed to ground the conversation in the codebase the model inconsistently reached for the built-in Explore (or general-purpose) agent — which fails to spawn in MCP-heavy sessions. Scoped the "No agents" line to build/verify pipeline agents and added an explicit Guidelines bullet directing broad codebase sweeps to the read-only rnd-explorer.

## 0.16.0 — 2026-06-05

### Prefix the 15 remaining unprefixed skills with rnd- so every skill follows the rnd-<name> convention

Agents (13) and commands (12) were already fully rnd-prefixed; 15 skills were not: premortem, outside-view, kiss-practices, fp-practices, code-review, committing, prefer-system-tools, bash-hook-testing, bun-scripting, hook-authoring, lib-sh-patterns, plugin-architecture, plugin-versioning, writing-skills, and using-rnd-framework. Rename each skill directory and its name: frontmatter to the rnd-<name> form, and update every rnd-framework:<name> invocation and skills/<name>/ path reference across agents, commands, hooks, tests, fixtures, README, and CLAUDE.md. Non-skill files (lib/outside-view.sh, premortem.md/outside-view.md artifacts, *-emit.sh) and prose uses of common words are deliberately untouched. Skill invocations change from rnd-framework:<name> to rnd-framework:rnd-<name>; old names keep resolving only until the installed plugin cache is refreshed via /plugin update. Verified: validate.sh exit 0 (66 xrefs + 13 parity), full test suite exit 0.

## 0.15.282 — 2026-06-05

### Disambiguate the Phase 7 "code review" menu option so it runs the RND review, not native /code-review

The end-of-pipeline next-steps menu offered an unqualified "Run code review first" option with no handler, so the orchestrator resolved it to Claude Code's native /code-review skill. Qualify the label to "Run RND code review first" and add an explicit handler routing it to rnd-framework:code-review (or /rnd-framework:rnd-review), forbidding the native command.

## 0.15.281 — 2026-06-03

### Cross-link the assertion paraphraser from the Skills page

Add a one-line pointer from the docs Skills page to the wording-channel explanation of the assertion paraphraser on the Information barrier page, so the decorrelation step is discoverable from the reasoning-aids list.

## 0.15.280 — 2026-06-03

### Fix rnd-remeasure corpus boundary and fail loud on unresolvable boundaries

Replace the git-resolved M5 commit SHA with a baked epoch constant so the post-M5 corpus filter no longer silently counts the whole corpus when the SHA is unresolvable; fail loud on an unresolvable boundary; add a dogfood-scope signal to the memo and a no-active-session note to the command; document the assertion paraphraser and re-measurement on the site; and relax the outside-view wiring test to assert facts against the protocol.md fixture rather than the plain-language CHANGELOG.

## 0.15.279 — 2026-06-01

### Rename the debug pipeline's pre-registration artifact from plan.md to protocol.md

## 0.15.278 — 2026-05-31

- Builder self-assessments now record their explicit status (done / done-with-concerns / needs-context / blocked) instead of guessing pass/fail from the report's shape.
- Fixes a stat that wrongly counted every "done with concerns" build as a builder failure.

## 0.15.277 — 2026-05-31

- Hooks now recognize the current `protocol.md` plan file; the old `plan.md` is kept only for the debug pipeline.
- Saved pipeline state and calibration records now use snake_case keys, still reading older camelCase records.

## 0.15.276 — 2026-05-31

- Adds `rnd-explorer`, a read-only search agent that spawns reliably in sessions with many MCP servers — where the built-in Explore agent fails with "Prompt is too long".
- The orchestrator now uses it for searches instead of Explore.

## 0.15.275 — 2026-05-31

- The bash test suite no longer reads a live session's state, so it passes whether or not a pipeline is running.
- Clears all shellcheck warnings in production scripts.

## 0.15.274 — 2026-05-31

- Builder self-assessments now resolve to the plan's canonical task ID, fixing a join that mismatched on bare `T01`-style IDs.
- Task IDs are now snake_case everywhere (audit, verdict map, calibration), still reading older records.

## 0.15.273 — 2026-05-30

- The self-fail-vs-verdict stat now matches builds to verdicts within the same session, fixing cross-session ID collisions that paired unrelated tasks.

## 0.15.272 — 2026-05-30

- Stats that tracked the FAIL rate now count any non-PASS verdict, since the verifier no longer emits a literal "FAIL" — fixing several views that read a flat zero.

## 0.15.271 — 2026-05-30

- Resets the version from 5.x back to 0.x to signal the framework is still experimental and may break between releases. The patch number preserves the running count of past releases.

## 5.15.0 — 2026-05-30

- The post-SHIP review now tags each finding with a category (architecture, security, correctness, etc.).
- Stats report how often reviews surface architecture and design issues — the signal for whether a future "theory-holder" role is worth building.

## 5.14.1 — 2026-05-30

- A review finding on a file owned by several tasks now attributes to the latest one, deterministically.
- Whether the verifier passed a finding's task is now read from the verdict map rather than a caller-supplied flag.

## 5.14.0 — 2026-05-30

- Runs an automatic code review after the final SHIP and records its findings per task-shape.
- A task-shape that passes review cleanly five times in a row earns a lighter, faster build-and-verify path — but only at low/normal criticality, and verification always still runs.
- A single new review finding instantly drops the shape back to the careful path.

## 5.13.1 — 2026-05-30

- A fresh project no longer shows an "RND:" tab title; only an active pipeline sets one.

## 5.13.0 — 2026-05-30

- Idle sessions now load almost no context; full pipeline context returns automatically when a run is active or resumes.

## 5.12.0 — 2026-05-29

- Blocks the verifier from passing a task when it relied on a quality tool it couldn't actually run — it must downgrade and record the gap instead.
- The sycophancy flip-rate stat now measures only assertions that can be statically re-checked, separating out cases a re-review can't reproduce.

## 5.11.0 — 2026-05-29

- Before verification, assertions are reworded (keeping every literal value exact) so the verifier reads a different phrasing than the planner wrote, reducing anchoring.

## 5.10.0 — 2026-05-29

- Adds a stats view tracking whether iteration counts and re-plan frequency are trending up or down over recent sessions.

## 5.9.0 — 2026-05-29

- The verifier's evidence is now checked that each cited file or token actually exists in the project or session, not just that it looks like a citation.

## 5.8.1 — 2026-05-28

- Re-ran the false-PASS probe on a newer set of tasks; the raw flip rate rose but none were genuine failures, upholding the earlier "no clear false-PASSes" finding. Underpowered — re-run later.

## 5.8.0 — 2026-05-28

- Adds `/rnd-framework:rnd-remeasure`, which compares the current FAIL rate, self-fail gap, and iteration depth against the recorded baseline once enough sessions accrue.

## 5.7.3 — 2026-05-28

- Clarifies the report-surfacing rule with a concrete example so surfaced reports render as Markdown instead of showing raw `##` and `**`.

## 5.7.2 — 2026-05-28

- Tells the pipeline phases not to spawn the Explore subagent (it returned empty during rnd phases).
- Adds cross-links so previously-unreferenced skills are discoverable.

## 5.7.1 — 2026-05-28

- Adds `behaviour` as a valid planner shape (it was already in the data but rejected).
- Expands detection of leftover pipeline tags (milestone labels, task IDs) in docs and tests, across cleanup, polish, review, and debug.

## 5.7.0 — 2026-05-28

- Blocks the verifier from saving a verdict map whose evidence entries are empty or placeholder text. (Form only; substance checking added in 5.9.0.)

## 5.6.0 — 2026-05-28

- When you choose to re-plan failing tasks, the old plan is hidden from the fresh planner so the new decomposition can't anchor on the failed one.
- A diff of the old vs new plan is written for review.

## 5.5.0 — 2026-05-28

- Before planning, injects the historical FAIL rate for each task-shape as a calibration anchor, with a note that it's a reference, not a license to add more assertions.

## 5.4.4 — 2026-05-28

- Replaces the premortem fan-out's generic agent with a restricted-tool one so parallel spawns don't overflow context in MCP-heavy repos.

## 5.4.3 — 2026-05-28

- Adds a note explaining how `rnd-review` (a structured six-category report) differs from Claude Code's built-in `/code-review`.

## 5.4.2 — 2026-05-28

- `rnd-history`, `rnd-status`, and `rnd-stats` now declare themselves read-only so they can't modify state.

## 5.4.1 — 2026-05-28

- The phase-aware tab title is now set immediately on session start, not only after the first prompt.

## 5.4.0 — 2026-05-28

- Adds a probe that re-reviews past PASS assertions under the information barrier to look for false-PASSes, plus a flip-rate stat. Found no clear false-PASSes in the reviewable history.

## 5.3.0 — 2026-05-27

- Replaces a broken stats emitter (which logged zero events) with three that read identity from the artifact path, so the stats database finally collects data.

## 5.2.0 — 2026-05-27

- Before planning, the orchestrator imagines failure modes from several angles and feeds them to the planner, which must address or dismiss each one.

## 5.1.0 — 2026-05-27

- Adds the foundation for tracking planner shape and confidence through verification: a schema, a planner gate, read-only stats views, a backfill script, and the `rnd-stats` command.

## 5.0.3 — 2026-05-25

- Removes the worktree infrastructure — agents never wrote to worktrees and it failed to create real ones. The integrator now commits verified files directly.

## 5.0.2 — 2026-05-23

- Skips formatting inside linked worktrees, where the toolchain dirs are absent and the formatter would error.

## 5.0.1 — 2026-05-21

- Fixes a one-character bug that aborted every worktree-isolated agent spawn.

## 5.0.0 — 2026-05-20

- The planner now emits four focused files (scope, assertions, task manifest, agent assignments) instead of one big `plan.md`.
- Task and assertion IDs are now milestone-scoped and stable across re-plans, so audit records compare across sessions.
- Adds the per-assertion verdict map and session-local skill injection.

## 4.2.0 — 2026-05-19

- Removes the bash-gate style nudges (no `sed`/`awk`/inline interpreters/loops) and the file-revision stop condition — they caused mid-pipeline prompts without adding rigor. The information barrier and destructive-git protections stay.

## 4.1.0 — 2026-05-19

- Removes the Lean 4 proof gate and all its infrastructure; agent count drops to 9.

## 4.0.0 — 2026-05-19

- Strips out experimental machinery with no proven value (extra verdicts, multi-judge escalation, tier flags, advisory events) and keeps the validated core: pre-registration, information barrier, independent verification.
- Some pre-reg flags and verdict values are removed (breaking); in-flight 3.x sessions finish on 3.x.

## 3.29.0 — 2026-05-19

- Removes the flash-card system entirely; priming agents with generic patterns made them skip discovering what the actual project does.

## 3.28.0 — 2026-05-18

- Ships a large batch of deferred work across seven waves: audit events on every blocked git op, deeper card corpus, verification-ROI tooling, inline/final verifier dispatch, cognitive-style sections, and cross-lineage verification. (Much of this is removed again in 3.29–4.0.)

## 3.27.1 — 2026-05-18

- Clarifies that "verbatim" report surfacing means rendered Markdown, not a fenced code block, fixing reports that displayed as raw syntax.

## 3.27.0 — 2026-05-18

- Adds 20 flash cards covering Julia and Oxygen.jl idioms.

## 3.26.0 — 2026-05-18

- Adds a property-test runner for Elixir (StreamData) and TypeScript (fast-check); pre-regs can declare a `## Properties` section and the verifier runs it, pinning any counter-example.
- Fixes the information barrier wrongly blocking the orchestrator from reading briefs and self-assessments.

## 3.25.0 — 2026-05-17

- Adds ~40 Python flash cards, a corpus linter, and a "measure before optimizing" principle; fixes a barrier path that blocked cleanup cards.

## 3.24.0 — 2026-05-17

- Expands the card corpus with canon principles and per-language/library tiers for Elixir and TypeScript stacks.

## 3.23.0 — 2026-05-17

- Adds a flash-card library and deterministic retrieval; the orchestrator injects relevant good/bad examples into agent prompts at spawn time.

## 3.22.2 — 2026-05-17

- Moves shared section-parsing into one place and tightens heading matching so `## Verdict` no longer matches `## Verdicts`.

## 3.22.1 — 2026-05-17

- Adds gates enforcing reality-auditor anomalies, verifier case symmetry, cleanup bloat, and drift-report schema, plus a drift-detector agent — moving behavior enforcement from prompts to artifact gates.

## 3.22.0 — 2026-05-17

- Adds the reality-auditor existence pre-pass, verdict-flip and plan-size stop conditions, an Assumptions/Refuted-by pre-reg section, calibration telemetry, and a Coverage Gaps gate.

## 3.21.1 — 2026-05-16

- Fixes worktree-create not echoing a path, which aborted every isolated agent spawn.

## 3.21.0 — 2026-05-16

- Adds worktree isolation for agents, a destructive-git denylist, and closed-loop calibration.

## 3.20.7 — 2026-05-12

- Reverses earlier token-saving cuts: higher builder effort, full prose verification reports, sonnet (not haiku) for core roles, and a gate against premature "done" re-submissions.

## 3.20.6 — 2026-05-12

- Extends the builder/cleanup ban on leaking pipeline context (task IDs, phase labels, session paths) into project code.

## 3.20.5 — 2026-05-12

- Switches hooks to the v2.1.139 exec form, removing a class of `${CLAUDE_PLUGIN_ROOT}` quoting bugs. Raises the minimum Claude Code to 2.1.139.

## 3.20.4 — 2026-05-12

- Quotes the plugin-root placeholder in hooks to fix intermittent "No such file or directory" hook errors during cache rotation.

## 3.20.3 — 2026-05-12

- Removes literal single quotes that made every hook fail with "No such file or directory".

## 3.20.2 — 2026-05-11

- Picks the agent model per task criticality (low → haiku, normal → sonnet, high → opus), falling back to the agent default when unset.

## 3.20.1 — 2026-05-11

- Partitions session artifacts, roadmap, and facts under `branches/<branch>/`; calibration stays shared across branches.

## 3.20.0 — 2026-05-11

- High-criticality verification runs a cheap first-pass verifier and only escalates to dual-judge on a non-PASS. Trims heavy skill bodies.

## 3.19.0 — 2026-05-10

- Caches Bash output per session and advises when an identical command is re-run within ten minutes, instead of re-running it.

## 3.18.0 — 2026-05-10

- Adds an opt-in evidence-pack writer and a verifier-side gate that validates pack manifests before the verifier reads them.

## 3.17.0 — 2026-05-09

- Adds `rnd-polisher`, which runs once per wave after cleanup to fix cross-task duplication, naming drift, and misplaced helpers, rolling back if re-verification breaks.

## 3.16.0 — 2026-05-09

- All output styles now require the orchestrator to print report artifacts verbatim before asking for next steps.

## 3.15.0 — 2026-05-09

- Blocks the builder from dismissing issues as "pre-existing" or "out of scope"; the only legal escape is a logged, escalated ledger entry.

## 3.14.0 — 2026-05-08

- Adds an AMEND_REQUIRED verdict and an arbiter agent for amending a pre-registration mid-flight. (Removed in 4.0.0.)

## 3.13.7 — 2026-05-07

- Trims question prompts that offered 5–7 options down to the tool's 4-option limit, fixing validation errors.

## 3.13.6 — 2026-05-03

- Fixes bash-gate over-matching on compound commands, aligns the barrier with the Lean proof, and adds a parity check between the two plugin-dir-base copies.

## 3.13.5 — 2026-05-02

- Removes ~550 lines duplicated between agent files and their preloaded skills, and reconciles the docs to the current pipeline.

## 3.13.4 — 2026-04-30

- Removes unused list helpers, hardens an env-prefix bypass, and reconciles settings.json with documented defaults.

## 3.13.3 — 2026-04-30

- Fixes JSON-only phase detection, cleanup-path barrier consistency, and four minor hook and tooling bugs.

## 3.13.2 — 2026-04-26

- The verifier now runs once per wave and returns a per-task verdict map; the planner is capped at four tasks per wave; iteration is wave-level.

## 3.13.1 — 2026-04-26

- Cuts the planner turn limit and verifier overhead, adds mid-run progress briefs, and dedups the verifier doc — eliminating multi-minute hangs.

## 3.13.0 — 2026-04-23

- Adds `rnd-cleanup`, which sweeps dead code after each PASS and rolls back if it breaks re-verification. Adopts Claude Code v2.1.118 features.

## 3.12.2 — 2026-04-22

- Raises the minimum Claude Code to 2.1.117 for the Opus 1M-context fix; corrects stale docs claiming cat/grep/find are blocked (they aren't).

## 3.12.1 — 2026-04-21

- Adds a tool-discipline section to the orchestrator's session context so it follows the gate rules proactively.

## 3.12.0 — 2026-04-20

- Adds Prototype / Standard / High-stakes tiers at the start of a run. (Removed in 4.0.0.)

## 3.11.0 — 2026-04-20

- The planner now self-reviews its plan (coverage, placeholders, traceability) before handing off.

## 3.10.0 — 2026-04-20

- Adds a cross-phase decisions log and barrier-protected user-facing briefs relayed to chat during agent work.
- Brainstorming now diverges from the obvious answer before converging.

## 3.9.0 — 2026-04-20

- Downgrades planner/verifier/debugger from opus to sonnet (~75% cheaper) and makes multi-judge opt-in.
- Proof gate and reality audit now run only when the task declares them.

## 3.8.0 — 2026-04-18

- Stops blocking `cat`/`head`/`grep`/`find` — those gates fought training habits and added noise. Write-side and interpreter blocks stay.

## 3.7.0 — 2026-04-17

- Raises effort on the three opus agents, adds a network exfil denylist, and trims the session bootstrap.

## 3.6.0 — 2026-04-17

- Switches agent spawns to `acceptEdits` mode after `auto` denied builder edits on 2.1.112.

## 3.5.1 — 2026-04-17

- Closes a command-injection vector in format-on-save and dedups barrier/phase logic across hooks.

## 3.5.0 — 2026-04-17

- Brainstorm must end with selectable options, never a "plan saved, run X" message.

## 3.4.2 — 2026-04-16

- Re-adds two doc sentences so the structure validator passes again.

## 3.4.1 — 2026-04-16

- Switches agent spawns from `bypassPermissions` to `auto` after the former wasn't honored for team-spawned subagents.

## 3.4.0 — 2026-04-16

- Adds effort frontmatter, trims skill preloads, and adds a model/effort routing matrix by criticality.

## 3.3.2 — 2026-04-12

- Tasks now show pipeline IDs (`T5`) instead of internal IDs (`#21`) in blocked-by references.

## 3.3.1 — 2026-04-12

- Closes the Grep/Glob and Bash bypass routes around the self-assessment information barrier.

## 3.3.0 — 2026-04-11

- The reality auditor now runs on every task, cross-checking the builder's declared external references and diff-scanning for undeclared ones.

## 3.2.1 — 2026-04-10

- Adds the required description to all agent-spawn templates.

## 3.2.0 — 2026-04-10

- Replaces inline build/verify/integrate steps with explicit agent spawns; derives task status from artifact files instead of a state JSON.

## 3.1.0 — 2026-04-10

- Moves nine commands into skills and fixes the UserPromptSubmit hook schema.

## 3.0.18 — 2026-04-09

- Drops single-flow execution; the information barrier only holds when build and verify run in separate contexts.

## 3.0.17 — 2026-04-09

- Stops an advisory title hook from blocking prompt submission on transient errors.

## 3.0.16 — 2026-04-09

- Re-adds a Write/Edit hook to auto-allow `.rnd/` paths, since the sandbox rule didn't match reliably in subagents.

## 3.0.15 — 2026-04-09

- Adds statusline refresh and the prompt-submit title hook; raises the minimum version to 2.1.97.

## 3.0.14 — 2026-04-04

- Blocks `for`/`while`/`until` loops (they hang the Bash tool); allows stdin grep filters; fixes stale docs.

## 3.0.13 — 2026-04-04

- Replaces bash 4+ features so hooks work on macOS stock bash.

## 3.0.12 — 2026-04-04

- Adds per-assertion evidence files to the verification pipeline.

## 3.0.11 — 2026-04-04

- Adds structured preconditions to pre-registration and build verification.

## 3.0.10 — 2026-04-04

- Adds `/rnd-scan` and a project-facts layer with Phase 0 staleness detection.

## 3.0.9 — 2026-04-04

- Adds pipeline-state.json and aligns with v2.1.92.

## 3.0.8 — 2026-04-02

- Adds the format-on-save hook and aligns with v2.1.90.

## 3.0.6 — 2026-04-01

- Adds explicit commit-prep tool discipline to the committing skill.

## 3.0.5 — 2026-04-01

- Never chain git/gh commands when creating PRs; use a separate call each.

## 3.0.4 — 2026-04-01

- Adds uv and ruff as preferred Python tools across the relevant skills and agents.

## 3.0.3 — 2026-04-01

- Adds the PermissionDenied hook, a defer helper, a version check, and an env-prefix fix.

## 3.0.2 — 2026-03-31

- Removes a PermissionDenied hook entry Claude Code's schema rejected, fixing plugin load failure.

## 3.0.1 — 2026-03-31

- Removes the redundant write-gate, adds absolute-path guards, and upgrades post-compact to a higher-visibility message.

## 3.0.0 — 2026-03-31

- Focuses exclusively on Claude Code, removing all multi-platform (Factory Droid, OpenCode) infrastructure and the quick-mode command.

## 2.1.0 — 2026-03-30

- The plan now adds environment discovery, a numbered validation contract, a testing strategy, worker guidelines, and task↔assertion traceability.

## 2.0.1 — 2026-03-30

- Removes a model override and condenses the quick command to avoid rate-limit errors.

## 2.0.0 — 2026-03-29

- Restores the eight specialized agents, Lean 4 proofs, and dual-mode (single-flow + multi-agent) orchestration, keeping the post-1.0 improvements.

## 1.0.5 — 2026-03-28

- Removes the proofs directory, the Lean skill, and the proof gate from the pipeline.

## 1.0.4 — 2026-03-28

- Dedups config-dir resolution and splits cross-reference validation into its own file.

## 1.0.3 — 2026-03-28

- Replaces leftover multi-agent terminology with single-flow language across docs and skills.

## 1.0.2 — 2026-03-28

- Adds skills for hook authoring, plugin architecture, hook testing, versioning, and lib.sh patterns.

## 1.0.1 — 2026-03-28

- Repairs validation failures and command hangs caused by the agent removal and cross-platform naming.

## 1.0.0 — 2026-03-28

- Removes all agents; pipeline phases run sequentially in one session via skills. Merges several hooks to cut process spawns.

## 0.14.14 — 2026-03-28

- Adds a hook blocking destructive database operations, and OpenCode as a third supported platform.

## 0.14.13 — 2026-03-27

- Increases session-ID entropy, standardizes stdin parsing, and removes unused code.

## 0.14.12 — 2026-03-27

- Removes a contradictory verifier rule and hardens session validation.

## 0.14.11 — 2026-03-27

- Renames all command files with an `rnd-` prefix so they don't collide with other plugins in Factory Droid.

## 0.14.10 — 2026-03-27

- Caches the session base-dir path and collapses repeated jq calls, cutting per-cycle hook overhead from 183ms to 102ms.

## 0.14.9 — 2026-03-26

- Adds a Factory Droid platform shim (config-dir detection, path matching, matcher expansion).

## 0.14.8 — 2026-03-26

- Auto-allows Glob and Grep on `.rnd/` paths and tightens the bash auto-allow regexes.

## 0.14.7 — 2026-03-26

- Removes dead code, standardizes hooks, and raises the verifier turn limit for full-codebase audits.

## 0.14.6 — 2026-03-26

- Generalizes plugin-artifact auto-allow and removes Team Mode from the pipeline.

## 0.14.5 — 2026-03-26

- Adds local copies so plugin-dir-base.sh isn't missing from the plugin cache.

## 0.14.4 — 2026-03-26

- Adopts v2.1.84 features: agent effort levels, builder worktree isolation, and the TaskCreated hook.

## 0.14.3 — 2026-03-26

- Auto-allows reads of the learnings directory.

## 0.14.2 — 2026-03-25

- Fixes an inert cwd-changed hook, a bad command reference, the statusline extension, and extracts a shared plugin-dir-base.

## 0.14.1 — 2026-03-25

- Tightens command and skill prose by 35% with no behavior change.

## 0.14.0 — 2026-03-25

- Wraps builder spawning in session-scoped teams. (Removed in 0.8.0.)

## 0.13.8 — 2026-03-25

- Adds a Criticality field; low/normal tasks get a single verifier, high tasks get multi-judge. Iteration budgets scale with criticality.

## 0.13.7 — 2026-03-25

- Trims preloaded skills and folds the failure-mode catalog into the verification skill.

## 0.13.6 — 2026-03-25

- Refactors hooks with a functional toolkit and expands the clean-code skills.

## 0.13.5 — 2026-03-25

- Adds CwdChanged and FileChanged hooks and fixes the SessionStart JSON format.

## 0.13.4 — 2026-03-25

- Removes leftover slop-gate references that broke the debug and quick pipelines at setup.

## 0.13.3 — 2026-03-24

- Allows head/tail as stdin pipe filters.

## 0.13.2 — 2026-03-24

- Prevents pipeline task IDs from leaking into project code.

## 0.13.1 — 2026-03-24

- Blocks `python -c`/`node -e`-style inline execution and `/tmp` writes, while allowing file execution.

## 0.13.0 — 2026-03-23

- Rewrites all hooks from TypeScript to plain bash and removes the regex verification systems.

## 0.12.6 — 2026-03-23

- Adds the reality-auditor agent for external-service verification.

## 0.12.5 — 2026-03-23

- Adds collection, code-file, style, locale, and redirect management tools for full Framer API coverage.

## 0.12.4 — 2026-03-23

- Adds Framer image/svg/text, page-cloning, breakpoint, and component-variable tools.

## 0.12.3 — 2026-03-23

- Adds 10 Framer node/canvas tools and upgrades the MCP protocol to 2025-11-25.

## 0.12.2 — 2026-03-23

- Adds Framer component, style-lookup, and attribute-resolution tools.

## 0.12.1 — 2026-03-23

- Rewrites all 11 Framer skills with methodology, patterns, anti-patterns, and references.

## 0.12.0 — 2026-03-22

- Moves to a private repo under a proprietary license.

## 0.11.33 — 2026-03-22

- Fixes observation-mask test isolation and an injection-scanner stdout fallback.

## 0.11.32 — 2026-03-22

- Adds formatting and version-bump options to the debug pipeline's ship flow.

## 0.11.31 — 2026-03-22

- Adds SendMessage communication sections to the agent files.

## 0.11.30 — 2026-03-22

- Auto-allows plugin lib/ script invocations to stop repetitive prompts.

## 0.11.29 — 2026-03-22

- Renames the marketplace to oleksify-plugins.

## 0.11.28 — 2026-03-22

- Fixes Lean 4 proof-gate activation and detection.

## 0.11.27 — 2026-03-22

- Closes a bash-hook bypass via compound shell commands.

## 0.11.26 — 2026-03-22

- Blocks `git push` to protected branches and adds an advisory prompt-injection scanner on tool output.

## 0.11.25 — 2026-03-22

- Fixes a directory-path existence check and a test-killing module-level exit.

## 0.11.24 — 2026-03-22

- Moves hook filesystem I/O to Bun-native APIs where alternatives exist.

## 0.11.23 — 2026-03-22

- Expands the failure-mode catalog from 11 to 18 patterns drawn from LLM-reliability research.

## 0.11.22 — 2026-03-22

- Fixes roadmap milestones completing inline without verification, caused by recursive invocation.

## 0.11.21 — 2026-03-22

- Adds release automation, attention re-anchoring, property-test guidance, post-compaction recall checks, and output masking.

## 0.11.20 — 2026-03-22

- Merges three PostToolUse hooks into one and adds a write-gate to auto-allow `.rnd/` paths.

## 0.11.19 — 2026-03-20

- Removes the 30-line chunking gate and workflow.

## 0.11.18 — 2026-03-20

- Quick mode verifies inline instead of spawning a verifier, cutting API calls to avoid rate limits.

## 0.11.17 — 2026-03-20

- Makes slop-gate pattern extraction deterministic and adds multiline detection.

## 0.11.16 — 2026-03-20

- Adds the `rnd-formatting` skill that detects and runs the project's formatter before doc-polish.

## 0.11.15 — 2026-03-20

- Auto-captures non-obvious gotchas from failed-then-fixed builds into the Learning Library and feeds them back to builders.

## 0.11.14 — 2026-03-20

- Adds the roadmap command and skill for decomposing a broad goal into milestones run as separate sessions.

## 0.11.13 — 2026-03-20

- Adds effort frontmatter to all skills and commands, plus a statusline showing rate-limit usage and pipeline phase.

## 0.11.11 — 2026-03-19

- Adds a SessionEnd hook that clears the active session on close or `/resume`.

## 0.11.10 — 2026-03-18

- Adopts Claude Code v2.1.78 features.

## 0.11.9 — 2026-03-18

- Fixes Lean detection in the proof gate for the subagent PATH.

## 0.11.8 — 2026-03-18

- Hardens hook security and reduces startup overhead.

## 0.11.7 — 2026-03-18

- Adds Koka KISS practices and expands the Lean rules.

## 0.11.6 — 2026-03-18

- Updates the Svelte KISS practices to the Svelte 5 runes API.

## 0.11.5 — 2026-03-18

- Removes the non-functional wellbeing-check hook.

## 0.11.4 — 2026-03-18

- Adds lib/ to tsconfig, standardizes hook error wrapping, and simplifies stdin reading.

## 0.11.3 — 2026-03-18

- Tightens the `.rnd/` auto-allow and fixes a chunk-gate line count.

## 0.11.2 — 2026-03-17

- Surfaces slop-gate findings as advisory context.

## 0.11.1 — 2026-03-17

- Audits and hardens the hooks and rewrites the validator as TypeScript.

## 0.11.0 — 2026-03-17

- Adds Lean 4 formal-verification integration.

## 0.10.10 — 2026-03-17

- Auto-allows plugin-cache reads and updates v2.1.77 compatibility.

## 0.10.9 — 2026-03-16

- Adds experiment-based verification and calibration.

## 0.10.8 — 2026-03-16

- Fixes bump.sh failing when invoked from the plugin cache path.

## 0.10.7 — 2026-03-16

- Ports all hooks to TypeScript on a shared typed lib.

## 0.10.6 — 2026-03-16

- Restores chunk-gate enforcement, anti-deflection rules, the wellbeing timer, and doc-polish enforcement.

## 0.10.5 — 2026-03-15

- Requires builders to cite file:line evidence for external contracts before coding, and verifiers to check it.

## 0.10.4 — 2026-03-15

- Fixes slop-gate double-counting, a cd-strip regex, and a read-gate matcher.

## 0.10.3 — 2026-03-15

- Adds PreCompact/PostCompact/InstructionsLoaded/Setup hooks and per-agent permission modes.

## 0.10.2 — 2026-03-15

- Fixes test path resolution and session-ID casing.

## 0.10.1 — 2026-03-15

- Stops hooks from blocking the builder's self-assessment writes to `.rnd/` paths.

## 0.10.0 — 2026-03-15

- Adds a gate forcing small reviewable chunks, with the builder explaining each before writing. (Removed in 0.11.19.)

## 0.9.28 — 2026-03-14

- Adds break suggestions and explained incremental coding. (Removed later.)

## 0.9.27 — 2026-03-14

- Adds a command that generates a prose development narrative from any session's artifacts.

## 0.9.26 — 2026-03-14

- Requires builders to fix errors rather than deflect them as "pre-existing".

## 0.9.25 — 2026-03-14

- Adds a "show development narrative" option to the completion menu.

## 0.9.24 — 2026-03-14

- Adds the brainstorm command — a conversational funnel from vague idea to focused plan.

## 0.9.23 — 2026-03-14

- Adds a functional-programming practices skill with five principles and do/don't examples.

## 0.9.22 — 2026-03-14

- Adds Bash and Markdown to the kiss-practices README description.

## 0.9.21 — 2026-03-14

- Adds KISS practice files for Markdown and Bash.

## 0.9.20 — 2026-03-14

- Outputs the full design recommendation as text before the choice prompt, so it isn't truncated.

## 0.9.19 — 2026-03-14

- Adds the doc-polish skill that updates docs and stale comments after SHIP, before committing.

## 0.9.18 — 2026-03-14

- Auto-extracts coding rules from CLAUDE.md into slop patterns enforced during the build. (Later removed with the slop gate.)

## 0.9.17 — 2026-03-14

- Updates stale command and skill counts and structure trees in the docs.

## 0.9.16 — 2026-03-14

- Adds the audit command, which checks every tracked file against project standards.

## 0.9.15 — 2026-03-14

- Suggests a code review before committing at pipeline completion.

## 0.9.14 — 2026-03-14

- Adds the review command and a code-review skill (six categories, four severities, three verdicts).

## 0.9.13 — 2026-03-14

- Adds Tailwind KISS rules.

## 0.9.12 — 2026-03-14

- Adds Svelte and DuckDB KISS rules.

## 0.9.11 — 2026-03-14

- Adds the kiss-practices skill with general and per-language rules loaded by the detected stack.

## 0.9.10 — 2026-03-14

- Consolidates duplicated patterns across the bash hooks into a shared lib.sh.

## 0.9.9 — 2026-03-14

- Removes hardcoded component counts from the docs.

## 0.9.8 — 2026-03-14

- Adds distinct agent colors, frontmatter skill preloading, and read-only enforcement on the verifier.

## 0.9.7 — 2026-03-14

- Adds persistent memory to all agents, with a guided memory section each; the verifier's preserves the barrier.

## 0.9.6 — 2026-03-13

- Fixes stale skill counts in the docs.

## 0.9.5 — 2026-03-13

- Adds an anti-pattern slop gate and fixes excessive confirmation prompts by auto-allowing safe bash. (Slop gate later removed.)

## 0.9.4 — 2026-03-13

- Adds the resume command, which reconstructs pipeline state from artifacts and continues from where it left off.

## 0.9.3 — 2026-03-12

- Adds a design-exploration phase, a failure-mode catalog, builder status codes, and two-tier verification.

## 0.9.2 — 2026-03-12

- Adds optional git tagging to the bump command.

## 0.9.1 — 2026-03-12

- Makes the verifier fully read-only; it returns reports and the orchestrator saves them.

## 0.9.0 — 2026-03-11

- Adds two-verifier consensus with a tiebreaker, and auto-discovery of the project's own `.claude/` agents and skills for the planner.

## 0.8.5 — 2026-03-11

- Removes the worktree-isolation skill.

## 0.8.4 — 2026-03-11

- Fixes stale version and skill counts and standardizes "information-barrier" terminology.

## 0.8.3 — 2026-03-11

- Adds a verify-time pre-flight scan and a verifier startup self-check for leaked builder reasoning.

## 0.8.2 — 2026-03-11

- Hardens three hooks against missing dependencies, malformed JSON, and false positives.

## 0.8.1 — 2026-03-05

- Fixes 30 issues across hooks, scripts, commands, agents, and skills.

## 0.8.0 — 2026-03-05

- Replaces team/swarm coordination with plain blocking Agent calls, eliminating cross-session message leaks.

## 0.7.25 — 2026-03-05

- Adds the bump command and script that increments the patch version and prepends a changelog entry.

## 0.7.24 — 2026-03-05

- Uses explicit `subagent_type` syntax so the namespace prefix isn't stripped during spawns.

## 0.7.23 — 2026-03-05

- Adds a PostToolUse hook recording every file write/edit to the session audit log.

## 0.7.22 — 2026-03-05

- Adds the doctor command, which checks live runtime readiness (CLI tools, hooks, RND_DIR, version sync).

## 0.7.21 — 2026-03-04

- Adds DuckDB as a first-class alternative to Julia for SQL-shaped data tasks.

## 0.7.20 — 2026-03-04

- Adds the on-demand data-scientist agent and data-science skill, using Julia for computation.

## 0.7.19 — 2026-03-04

- Adds checks that key skill content also appears in the matching agent.

## 0.7.18 — 2026-03-04

- Adds first-class external-dependency handling across planner, builder, and verifier so wrong-schema assumptions get caught.

## 0.7.17 — 2026-03-04

- FAIL now routes to re-planning and pauses for a decision, instead of being treated like a simple iteration.

## 0.7.16 — 2026-03-04

- Adds a per-category summary table and a `--quiet` flag to the validator.

## 0.7.15 — 2026-03-04

- Defines how to skip a failing task: status mapping, dependency warnings, and integrator notice.

## 0.7.14 — 2026-03-04

- Widens the project-slug hash from 6 to 8 hex chars to avoid silent directory collisions.

## 0.7.13 — 2026-03-04

- Adds 12 more recognized agent tools so orchestration and team tools don't fail validation.

## 0.7.12 — 2026-03-04

- Replaces concrete artifact-path examples with generic templates.

## 0.7.11 — 2026-03-04

- Checks that commands using `$ARGUMENTS` declare an `argument-hint`, and vice versa.

## 0.7.10 — 2026-03-04

- Adds the validate command to the docs tables and corrects the slug-format example.

## 0.7.9 — 2026-03-04

- Adds 33 cross-reference checks for skill and agent references.

## 0.7.8 — 2026-03-04

- The session-start hook now warns when the cached plugin version differs from the source repo.

## 0.7.7 — 2026-03-04

- Three layers prevent the planner from modifying project files during the planning phase.

## 0.7.6 — 2026-03-04

- Adds the validate command, which checks plugin structure without starting a session.

## 0.7.5 — 2026-03-04

- Extracts inline hooks into external scripts and replaces fragile JSON escaping with jq.

## 0.7.4 — 2026-03-03

- Uses the full `plugin:agent` namespace everywhere so spawns stop failing with "agent type not found".

## 0.7.3 — 2026-03-03

- Deletes an unused skill-discovery module; the native plugin system handles discovery.

## 0.7.2 — 2026-03-03

- Documents marketplace install and updates, replacing the old `--dir` flag.

## 0.7.1 — 2026-03-03

- Switches allow decisions to `hookSpecificOutput` and blocks to `exit 2`, fixing silent auto-allow failures.

## 0.7.0 — 2026-03-03

- All hooks now read tool input from stdin (not a never-populated env var), fixing every auto-allow rule.

## 0.6.1 — 2026-03-03

- The framework now ends every request with structured options, not a plain "Done."

## 0.6.0 — 2026-03-03

- No-argument `start`/`quick`/`plan` now scan the codebase and offer task suggestions instead of plain text.

## 0.5.3 — 2026-03-01

- The bash hook now matches commands prefixed with `cd /path &&`.

## 0.5.2 — 2026-03-01

- Auto-allows `ls`.

## 0.5.1 — 2026-03-01

- Auto-allows Bash commands running `rnd-dir.sh`.

## 0.5.0 — 2026-03-01

- Each run gets a unique session ID and its own artifact directory, preserving history; adds the history command.

## 0.4.1 — 2026-03-01

- Spawns pipeline agents with `bypassPermissions` to remove prompts during execution.

## 0.4.0 — 2026-03-01

- The verifier reports all issues in one pass and the builder fixes them all in one iteration, ending whack-a-mole.
- Adds an opt-in auto-continue mode and a Phase 0 discovery step.

## 0.3.1 — 2026-03-01

- Honors `CLAUDE_CONFIG_DIR` before falling back to `~/.claude`, so custom profiles place artifacts correctly.

## 0.3.0 — 2026-03-01

- Moves pipeline artifacts out of the project into a central directory, so no `.gitignore` entry is needed.
- Adds decision gates, agent SendMessage contracts, the three output styles, and the information barrier.

## 0.2.0 — 2026-02-28

- Initial release: four agents, seven commands, fifteen skills, pre-registration, dependency-based waves, and the builder/verifier information barrier.