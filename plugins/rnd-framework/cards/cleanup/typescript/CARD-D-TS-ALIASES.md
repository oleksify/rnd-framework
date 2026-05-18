---
id: D-TS-ALIASES
role: cleanup
language: typescript
tags: [dead-code, duplication]
applicable_task_types: [refactor]
scope: Consolidate duplicate type aliases that drifted to identical structural shapes into one canonical definition.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```typescript
// src/orders/types.ts
export type OrderSummary = {
  id: string
  total: number
  status: string
}

// src/reports/types.ts — created separately, evolved to same shape
export type ReportOrderItem = {
  id: string
  total: number
  status: string
}
```

**After:**
```typescript
// src/shared/types.ts
export type OrderSummary = {
  id: string
  total: number
  status: string
}
```

**Why after is better:** TypeScript uses structural subtyping — two types with identical fields are assignable to each other, but they are not the same declaration. Maintaining two identical type aliases means any future field addition must be applied in two places; one copy will be missed and the types will silently drift apart. When shapes are genuinely identical and represent the same concept, merge to a single declaration in a shared location. Update all imports; the compiler will catch any missed reference.
