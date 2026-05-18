---
id: TS-PROPS-GEN-RECORD
role: builder
language: typescript
tags: [property, generators, fast-check, records]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use fc.record with dependent generators to encode mutual field constraints rather than post-hoc filter chains.
specializes: [P-PROPS-01]
---

**Good:**
```typescript
// User record: email always contains '@', age always non-negative — built in.
const userGen = fc.record({
  email: fc.emailAddress(),          // always contains '@'
  age:   fc.nat(),                   // always >= 0
  name:  fc.string({ minLength: 1 }),
})

test("user validation accepts all generated users", () => {
  fc.assert(
    fc.property(userGen, (user) => validateUser(user) === "ok")
  )
})
```
All constraints live inside the generator; shrinking finds the minimal failing email+age+name triple.

**Worse:**
```typescript
// Independent generators chained with filter — high discard rate, broken shrinking.
const badUserGen = fc.record({
  email: fc.string(),
  age:   fc.integer(),
  name:  fc.string(),
}).filter(u => u.email.includes("@") && u.age >= 0 && u.name.length > 0)
```
`fc.string()` rarely produces a valid email; the filter rejects nearly every value. fast-check warns about the discard rate and shrinks to values that no longer satisfy the filter, producing confusing counter-examples.

**Why good is better:** `fc.record` composes per-field generators; when each field uses a semantically-correct generator (`fc.emailAddress()`, `fc.nat()`), constraints hold by construction and no filtering is needed. Shrinking operates on each field independently while preserving the type guarantees. Chained `.filter()` calls multiply the discard probability across fields and produce shrunken inputs that violate the constraint, making the counter-example unreadable. Encode constraints in the generator, not the predicate.
