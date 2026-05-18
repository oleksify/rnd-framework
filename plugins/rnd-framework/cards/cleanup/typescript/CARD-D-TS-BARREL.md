---
id: D-TS-BARREL
role: cleanup
language: typescript
tags: [dead-code, orphan-exports]
applicable_task_types: [refactor]
scope: Remove exports from barrel index files when no external module imports the exported name.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```typescript
// src/payments/index.ts
export { PaymentService } from './payment.service'
export { PaymentDto } from './payment.dto'
export { LegacyPaymentAdapter } from './legacy-adapter'   // adapter was removed from all call sites
export type { ChargeResult } from './types'
export type { LegacyChargeParams } from './legacy-types'  // only used by LegacyPaymentAdapter
```

**After:**
```typescript
// src/payments/index.ts
export { PaymentService } from './payment.service'
export { PaymentDto } from './payment.dto'
export type { ChargeResult } from './types'
```

**Why after is better:** A barrel re-export that no consumer imports is dead re-export — it increases the public API surface, slows tree-shaking, and misleads readers into thinking the name is in active use. Use `ts-unused-exports` or `grep -r "LegacyPaymentAdapter" src --include="*.ts" | grep -v "index.ts"` to confirm zero external consumers before removing. Also remove the source file if it has no other callers; a dead re-export often points at an orphan file.
