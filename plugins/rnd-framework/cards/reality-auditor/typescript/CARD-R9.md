---
id: R9
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: JSON.parse returns any; assume the payload is malformed unless a runtime validator runs.
specializes: [P-IMPOSSIBLE-01]
---

**Good audit output:**
> `const payload = JSON.parse(raw) as ApiResponse` — the `as ApiResponse` is a cast, not a check. If `raw` is missing the `id` field or has a wrong type, TypeScript will not detect it and downstream code will silently operate on `undefined`. No Zod, Valibot, or manual guard is present. Flag: this boundary is unvalidated.

**Worse audit output:**
> The code parses the API response and assigns it to an `ApiResponse` typed variable. Looks consistent with the type definition.

**Why good is better:** Specializes the impossible-states principle for the `JSON.parse` → TypeScript boundary. `JSON.parse` has the return type `any` in the TypeScript standard library; a type assertion (`as T`) silences the compiler without adding any runtime guarantee. The good output traces the data provenance and identifies the missing validation step. Treat every `JSON.parse` call as unvalidated until a runtime schema check is confirmed.
