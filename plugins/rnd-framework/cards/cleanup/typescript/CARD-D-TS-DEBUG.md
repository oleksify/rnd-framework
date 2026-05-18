---
id: D-TS-DEBUG
role: cleanup
language: typescript
tags: [dead-code, debugging]
applicable_task_types: [refactor]
scope: Delete console.log statements and debugger declarations added for temporary troubleshooting before merging to main.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```typescript
async function submitOrder(order: Order): Promise<Receipt> {
  console.log('submitOrder called', order)
  const validated = await validate(order)
  console.log('validated', validated)
  debugger
  const receipt = await paymentGateway.charge(validated)
  console.log('receipt', receipt)
  return receipt
}
```

**After:**
```typescript
async function submitOrder(order: Order): Promise<Receipt> {
  const validated = await validate(order)
  return paymentGateway.charge(validated)
}
```

**Why after is better:** `console.log` in production code leaks internal state to browser dev tools and server stdout; it has no log-level filtering and cannot be disabled without a code change. `debugger` halts execution in any attached devtools session — if a client has devtools open, the page freezes. Both are development artifacts. ESLint rules `no-console` and `no-debugger` exist precisely to block these from reaching production. Remove them unconditionally; add structured logging via the project's logger if observability is genuinely needed.
