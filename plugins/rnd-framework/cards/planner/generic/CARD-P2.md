---
id: P2
role: planner
language: generic
tags: [decomposition, verifiability]
applicable_task_types: [new-feature, infra]
scope: medium
---

### Card P2: Decomposition that produces verifiable units

**Good decomposition:**
> Task 1: Add `User.export_dict()` method returning `dict[str, Any]`. Verifiable by: existing users serialize to dict with expected keys.
>
> Task 2: Add CLI command `export-user <id>`. Verifiable by: command outputs valid JSON for known user, exits non-zero for unknown user.
>
> Task 3: Add integration test. Verifiable by: test runs in CI, both success and error paths covered.

**Worse decomposition:**
> Task 1: Design the export architecture.
> Task 2: Implement core export functionality.
> Task 3: Add tests and documentation.
> Task 4: Polish and refactor.

**Why good is better:** The good decomposition produces tasks that each have a concrete verification check. The worse decomposition produces tasks where "done" is a judgment call. Judgment-call completion is where the model rationalizes past unfinished work.
