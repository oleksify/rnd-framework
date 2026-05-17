---
id: B17
role: builder
language: typescript
tags: [control-flow, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: A never-typed exhaustiveness check in switch turns a missing variant into a compile error.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```typescript
type Shape =
  | { kind: 'circle'; radius: number }
  | { kind: 'rect';   width: number; height: number }
  | { kind: 'tri';    base: number;  height: number }

const area = (s: Shape): number => {
  switch (s.kind) {
    case 'circle': return Math.PI * s.radius ** 2
    case 'rect':   return s.width * s.height
    case 'tri':    return 0.5 * s.base * s.height
    default: {
      const _exhaustive: never = s
      throw new Error(`unhandled shape: ${JSON.stringify(_exhaustive)}`)
    }
  }
}
```

**Worse:**
```typescript
const area = (s: Shape): number => {
  if (s.kind === 'circle') {
    return Math.PI * s.radius ** 2
  }

  if (s.kind === 'rect') {
    return s.width * s.height
  }

  return 0  // tri silently returns 0; adding new variants is also silent
}
```

**Why good is better:** Specializes the impossible-states principle with TypeScript's `never` exhaustiveness pattern. When a new variant is added to `Shape`, the `default` branch receives a `never` — which the assignment `const _exhaustive: never = s` rejects at compile time. The worse version falls through to `return 0`, which silently produces wrong answers for any unhandled variant, now and in the future.
