---
id: P-IMPOSSIBLE-01
role: builder
language: generic
tags: [boundaries, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: medium
---

### Card P-IMPOSSIBLE-01: Make impossible states unrepresentable

**Good:**
```typescript
type Shape =
  | { kind: 'circle'; radius: number }
  | { kind: 'rect'; width: number; height: number }

const area = (s: Shape): number => {
  switch (s.kind) {
    case 'circle': return Math.PI * s.radius ** 2
    case 'rect':   return s.width * s.height
  }
}
```

**Worse:**
```typescript
interface Shape {
  kind: string
  radius?: number
  width?: number
  height?: number
}

const area = (s: Shape): number => {
  if (s.kind === 'circle') {
    return Math.PI * (s.radius ?? 0) ** 2
  }

  if (s.kind === 'rect') {
    return (s.width ?? 0) * (s.height ?? 0)
  }

  return 0
}
```

**Why good is better:** The worse version encodes invalid states — a `circle` with no `radius`, a `rect` with missing dimensions — as runtime `?? 0` fallbacks that silently produce wrong answers. The discriminated union makes those states unrepresentable at the type level: missing fields simply don't exist on the wrong variant. Use the type system as the first line of validation, not a safety net of runtime checks.
