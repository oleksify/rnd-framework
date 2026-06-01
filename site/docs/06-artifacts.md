## Artifacts

Every pipeline run writes its working files — the plan, build manifests, verification reports, the audit log — to a directory **outside** the project tree. Because they live outside the repo, there is nothing to add to `.gitignore`. Each project gets its own isolated slug; each run gets a unique session id.

The path is computed by `lib/rnd-dir.sh`. The layout:

```
~/.claude/.rnd/<dirname>-<hash>/          project slug
├── calibration.jsonl                     verdict-accuracy log (project-wide)
├── post-review.jsonl                     post-ship review ledger
└── branches/<branch>/
    ├── project-facts.md                  persistent project scan
    ├── roadmap.md                        multi-session roadmap
    └── sessions/<YYYYMMDD-HHMMSS-XXXX>/   one per run  ($RND_DIR)
        ├── premortem.md                  imagined failure modes
        ├── outside-view.md               historical-failure calibration block
        ├── protocol.md                   scope and goals
        ├── validation-contract.md        one assertion per heading
        ├── features.json                 task manifest (ids, deps, criticality)
        ├── AGENTS.md                      per-agent work assignments
        ├── builds/                        manifests + self-assessments
        ├── verifications/                 verdict maps, reports, evidence
        ├── cleanup/  ·  polish/           cleanup and polish reports
        ├── integration/                   results, SHIP / NO-SHIP
        ├── briefs/                        barrier-protected builder notes
        ├── audit.jsonl                    shared audit log
        └── iteration-log.md               build-verify cycle tracking
```

### Inside features.json

`features.json` is the only machine-readable artifact — the task manifest the orchestrator reads to schedule waves. A two-task example:

```json
{
  "tasks": [
    {
      "id": "M1.T01.parse-config-file",
      "slug": "parse-config-file",
      "milestone": "M1",
      "uuid": "af995933",
      "dependsOn": [],
      "assertionIds": ["M1.cfg.valid-yaml-parses", "M1.cfg.missing-file-errors"],
      "criticality": "HIGH",
      "status": "pending"
    },
    {
      "id": "M1.T02.apply-config-to-runtime",
      "slug": "apply-config-to-runtime",
      "milestone": "M1",
      "uuid": "076e0b8b",
      "dependsOn": ["M1.T01.parse-config-file"],
      "assertionIds": ["M1.rt.overrides-take-effect"],
      "criticality": "NORMAL",
      "status": "pending"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | `M<milestone>.T<NN>.<slug>` — the join key across every artifact. `slug` and `uuid` exist for readability and collision-proof manifest filenames. |
| `dependsOn` | Task ids that must finish first; this is what schedules execution waves (T02 waits for T01). |
| `assertionIds` | Headings in `validation-contract.md` this task is accountable for; the verifier slices its checks by these. |
| `criticality` | `LOW` / `NORMAL` / `HIGH` — drives the model and effort the orchestrator dispatches. |
| `status` | Progresses from `pending` through `completed`. |

### Inside audit.jsonl

`audit.jsonl` is the session's append-only event log — one JSON object per line, written by the hooks (file-write auditing, subagent lifecycle, the quality gates) and the lib emitters. Nothing edits it after the fact; it is the raw substrate the `rnd-stats` and calibration views query. A few representative lines:

```json
{"ts":"2026-01-01T10:00:00Z","tool":"Write","file":".../builds/M1-T01-af995933-manifest.md"}
{"event":"SubagentStart","agent_id":"a2e82da53","agent_type":"rnd-framework:rnd-builder","timestamp":"2026-01-01T10:00:01Z"}
{"event":"assertion_shape","task_id":"M1.T01.parse-config-file","assertion_id":"M1.cfg.valid-yaml-parses","shape":"behaviour","confidence":"high","timestamp":"2026-01-01T10:01:00Z"}
{"event":"builder_self_assessment","session_id":"20260101-100000-abcd","task_id":"T01","self_verdict":"PASS","timestamp":"2026-01-01T10:05:00Z"}
{"event":"gate_fired","task_id":"M1.cfg.valid-yaml-parses","tool":"evidence_locking_gate","timestamp":"2026-01-01T10:06:00Z"}
```

Lines come in two shapes — a **tool-audit** line (a `tool` + `file`, no `event` key; one per Write/Edit applied during the run) and a **named event** (carries an `event` key). The common events:

| `event` | Emitted when |
|---|---|
| *(none)* | A file was written or edited — `{ts, tool, file}`. The bulk of the log. |
| `SubagentStart` / `SubagentStop` | A pipeline agent spawned or returned (`agent_type`, `agent_id`). |
| `task_created` | The orchestrator registered a task. |
| `assertion_shape` | The planner classified an assertion (`shape`, `confidence`) — feeds the per-shape stats. |
| `builder_self_assessment` | A builder recorded its own `self_verdict` — later compared against the verifier's. |
| `gate_fired` | A quality gate blocked an agent (the `tool` names which gate). |
| `premortem_generated` · `paraphrase_injected` · `outside_view_injected` | Phase-specific lifecycle markers. |

(Tool-audit lines stamp `ts`; named events stamp `timestamp` — a historical split the stats views tolerate.)

### rnd-dir.sh flags

| Flag | Returns |
|---|---|
| `-c` | Create and print a new session dir |
| `--finish` | Clear the active session |
| `--base` | The branch-scoped project base |
| `--roadmap` / `--facts` | Paths that lazily inherit from the default branch |
| `--calibration` | The slug-root calibration log path |

The branch is resolved from `HEAD` on each call: a detached head becomes `detached-<sha7>`, and outside a git repo it becomes `no-git`.
