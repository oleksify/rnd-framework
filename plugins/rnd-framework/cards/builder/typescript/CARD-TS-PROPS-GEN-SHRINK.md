---
id: TS-PROPS-GEN-SHRINK
role: builder
language: typescript
tags: [property, generators, fast-check, shrinking]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Prefer built-in fast-check generators over constantFrom or manual arrays to preserve shrinking surface.
specializes: [P-PROPS-01]
---

**Good:**
```typescript
// fc.string shrinks toward "" — the minimal failing string is always recoverable.
test("encode never returns null for any string", () => {
  fc.assert(
    fc.property(fc.string({ minLength: 0 }), (s) => encode(s) !== null)
  )
})

// fc.oneof with typed generators: each branch has its own shrinking path.
const inputGen = fc.oneof(fc.string(), fc.integer(), fc.boolean())
```
When a property fails, fast-check reduces the string to the shortest prefix that still fails.

**Worse:**
```typescript
// constantFrom has no shrinking surface — counter-example is always a full complex value.
const badGen = fc.constantFrom(
  "user@example.com",
  "hello world",
  "special!@#$%^&*()",
  "a".repeat(200),
)
```
`constantFrom` can only report one of the exact supplied values as a counter-example; it cannot shrink to a smaller failing string. A 200-character string stays 200 characters in the report even if a 3-character prefix is the real cause.

**Why good is better:** fast-check's built-in generators (`fc.string`, `fc.integer`, `fc.array`, `fc.nat`) carry shrinking trees — ordered sequences of simpler values that fast-check walks toward the minimal counter-example. `fc.constantFrom` has no shrinking tree; it can only report one of the literals you supplied. If any of those literals happen to trigger a bug, you get the full literal as the counter-example, with no information about which minimal sub-input is responsible. Reserve `constantFrom` for finite known-good sets used in positive tests, not for exploring the input space in property tests.
