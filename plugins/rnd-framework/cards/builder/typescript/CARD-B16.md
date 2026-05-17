---
id: B16
role: builder
language: typescript
tags: [boundaries, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: as const narrows string constants to literal types, preventing invalid-value states.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```typescript
const STATUS = {
  pending:  'pending',
  active:   'active',
  archived: 'archived',
} as const

type Status = (typeof STATUS)[keyof typeof STATUS]
// => 'pending' | 'active' | 'archived'

const activate = (s: Status): Status => {
  if (s === STATUS.archived) {
    throw new Error('cannot activate archived')
  }

  return STATUS.active
}
```

**Worse:**
```typescript
const STATUS = {
  pending:  'pending',
  active:   'active',
  archived: 'archived',
}

type Status = string  // or even: typeof STATUS[keyof typeof STATUS] omitted

const activate = (s: Status): Status => {
  if (s === 'archiived') {  // typo compiles fine
    return 'active'
  }

  return 'active'
}
```

**Why good is better:** Specializes the impossible-states principle with TypeScript's `as const` + derived literal union. Without `as const`, object values widen to `string`, the union collapses, and typos in string comparisons become silent bugs. With `as const`, the type system owns the valid-value set — adding a new status to the object automatically expands the union and forces callers to handle it.
