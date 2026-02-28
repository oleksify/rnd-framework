---
description: "Show the current status of the R&D pipeline: which tasks are planned, built, verified, integrated, or stuck in iteration."
---

# R&D Framework: Status

Read `.rnd/plan.md` and scan the `.rnd/` directory to build a status report.

For each task in the plan, determine its state:

- **📋 Planned** — Pre-registration exists but no build yet
- **🔨 Built** — Builder output exists in `.rnd/builds/T<id>-manifest.md`
- **🔍 In Verification** — Verifier is working (no report yet)
- **✅ Verified** — PASS verdict in `.rnd/verifications/T<id>-verification.md`
- **🔄 Iterating** — FAIL/NEEDS ITERATION, check `.rnd/iteration-log.md` for cycle count
- **⚠️ Escalated** — Exceeded iteration budget (3 cycles)
- **🚀 Integrated** — Part of a SHIP verdict in `.rnd/integration/`

Display as a table:

```
Wave | Task ID | Name                    | Status        | Iterations
-----|---------|-------------------------|---------------|----------
  1  | T1      | Design API contracts    | ✅ Verified   | 0
  2  | T2      | OAuth callback handler  | 🔄 Iterating  | 1/3
  2  | T3      | Token storage service   | 🔨 Built      | —
  2  | T4      | Login UI component      | 📋 Planned    | —
  3  | T5      | End-to-end auth flow    | 📋 Planned    | —
```

Also show:
- Current wave being worked on
- Any blocked tasks (dependencies not yet verified)
- Iteration log summary (which tasks needed rework and why)
- Overall progress percentage
