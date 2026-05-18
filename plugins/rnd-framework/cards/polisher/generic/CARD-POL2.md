---
id: POL2
role: polisher
language: generic
tags: [polish, naming, drift]
applicable_task_types: [new-feature, refactor]
scope: Detect naming drift for the same concept across files touched by different tasks in a wave.
specializes: [P-EFFECTS-EDGE-01]
---

**Good polisher judgment:**
One task introduced `widget_id` (snake_case) in a backend module; another introduced `widgetId` (camelCase) in a frontend module that calls the backend. The polisher flags this as naming drift within the same domain concept. It checks whether the two names flow into a shared serialization boundary — if they do, the mismatch is a runtime bug, not just style. The polisher proposes a consistent name at the boundary and updates both sites.

**Worse polisher judgment:**
The polisher treats snake_case vs camelCase as a language-convention difference and skips it. Each module is internally consistent, so no action is taken. The mismatch causes a JSON key mismatch six months later.

**Why good is better:** Naming drift is not always a style issue. When two names for the same concept cross a serialization or API boundary, they become a correctness issue. The polisher's job is to detect cases where drift is at a seam — where the two names meet and must agree. Drift that stays fully within one module's boundary is usually fine; drift at a cross-task boundary is a latent bug.
