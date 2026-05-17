---
id: B15
role: builder
language: typescript
tags: [boundaries, validation, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Discriminated unions make invalid field combinations unrepresentable at compile time.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```typescript
type Result<T> =
  | { ok: true;  value: T }
  | { ok: false; error: string }

const divide = (a: number, b: number): Result<number> => {
  if (b === 0) {
    return { ok: false, error: 'division by zero' }
  }

  return { ok: true, value: a / b }
}

const r = divide(10, 2)

if (r.ok) {
  console.log(r.value)   // value is number here
} else {
  console.error(r.error) // error is string here
}
```

**Worse:**
```typescript
type Result<T> = {
  ok?: boolean
  value?: T
  error?: string
}

// divide body identical — only the Result type changed
const r = divide(10, 2)

console.log(r.value!)  // forced cast; compiles even when ok is false
```

**Why good is better:** Specializes the impossible-states principle for TypeScript discriminated unions. The worse form allows accessing `.value` even in the error branch — the compiler can't rule it out because both fields are optional on the same type. The good form narrows automatically: inside `if (r.ok)`, TypeScript knows `r.value` is `T`, not `T | undefined`. Zero runtime cost; all safety is structural.
