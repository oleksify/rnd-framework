---
id: R8
role: reality-auditor
language: typescript
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: TypeScript types are erased at runtime; tsc --noEmit passing does not prove runtime safety.
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit output:**
> The Builder claims "the type system ensures `user.role` is always `'admin' | 'viewer'`." `tsc --noEmit` passes — but the value arrives from `JSON.parse(req.body)`, which returns `any`. TypeScript accepted the assignment without a runtime check, so a malformed payload can set `user.role` to any string. The compile-time guarantee does not hold at the network boundary.

**Worse audit output:**
> TypeScript compilation succeeds with no errors. The type annotations look correct.

**Why good is better:** Specializes the push-effects-to-the-edge principle for runtime-vs-compile-time boundaries. TypeScript types are fully erased before execution; a clean `tsc` build proves only structural consistency of the source, not the shape of external data. Audit every claim of type-level safety by tracing where the value originates — if it crosses a trust boundary (HTTP body, `JSON.parse`, `localStorage`, env var) without a runtime validator, the type annotation is an assertion, not a proof.
