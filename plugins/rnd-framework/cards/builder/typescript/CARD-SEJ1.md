---
id: SEJ1
role: builder
language: typescript
tags: [error-handling, boundaries, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Sentry.captureException is fire-and-forget — it does not rethrow; always rethrow or handle the error after capturing.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```typescript
const processPayment = async (order: Order): Promise<void> => {
  try {
    await stripe.charge(order)
  } catch (err) {
    Sentry.captureException(err, { extra: { orderId: order.id } })
    throw err  // rethrow so the caller knows the operation failed
  }
}
```

**Worse:**
```typescript
const processPayment = async (order: Order): Promise<void> => {
  try {
    await stripe.charge(order)
  } catch (err) {
    Sentry.captureException(err)
    // swallowed — caller receives a resolved Promise despite the failure
  }
}
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for observability side effects. `Sentry.captureException` is a reporting effect — it queues the event for delivery but does not alter the error's propagation. Swallowing the exception after capture turns a hard failure into a silent success from the caller's perspective: no retry, no circuit break, no user-facing error message. Capture first, then rethrow (or convert to an explicit error return) so both observability and control flow are correct.
