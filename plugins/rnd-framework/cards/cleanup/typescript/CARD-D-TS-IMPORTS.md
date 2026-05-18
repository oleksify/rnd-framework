---
id: D-TS-IMPORTS
role: cleanup
language: typescript
tags: [dead-code, imports]
applicable_task_types: [refactor]
scope: Remove unused named imports while preserving re-exports and type-only imports that serve as public API surface.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```typescript
// src/orders/service.ts
import { Repository } from 'typeorm'
import { Order } from './order.entity'
import { User } from '../users/user.entity'      // not used in this file
import { formatDate } from '../utils/date'        // ts-unused-exports flags this
import { PaymentStatus } from './payment-status'  // re-exported below

export { PaymentStatus }  // public API re-export

export class OrderService {
  constructor(private repo: Repository<Order>) {}
  find(id: string) { return this.repo.findOne({ where: { id } }) }
}
```

**After:**
```typescript
// src/orders/service.ts
import { Repository } from 'typeorm'
import { Order } from './order.entity'
import { PaymentStatus } from './payment-status'

export { PaymentStatus }

export class OrderService {
  constructor(private repo: Repository<Order>) {}
  find(id: string) { return this.repo.findOne({ where: { id } }) }
}
```

**Why after is better:** TypeScript/ESLint's `no-unused-vars` rule catches imports that are neither referenced nor re-exported. Before deleting a flagged import, verify it is not a side-effect import (e.g., `import './polyfill'`) and not a re-export that a barrel file depends on. Remove `User` and `formatDate` cleanly; keep `PaymentStatus` because it appears in `export { PaymentStatus }`.
