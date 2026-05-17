---
id: SUP1
role: builder
language: typescript
tags: [boundaries, validation, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: supabase-js select() returns { data, error } — never assume data is truthy without checking error first.
specializes: [P-IMPOSSIBLE-01, B15]
---

**Good:**
```typescript
const { data, error } = await supabase.from('posts').select('*')

if (error) {
  throw new Error(`Failed to fetch posts: ${error.message}`)
}

return data  // data: Post[] here — error ruled out
```

**Worse:**
```typescript
const { data } = await supabase.from('posts').select('*')

return data.map(post => post.title)  // TypeError if RLS denies or network fails
```

**Why good is better:** Specializes the impossible-states principle for the supabase-js result shape. Every query method returns `{ data: T | null, error: PostgrestError | null }` — both fields can be null independently, so destructuring only `data` leaves the error branch unrepresentable in your logic. Checking `error` first before using `data` mirrors the discriminated-union discipline: once the error branch is eliminated, `data` is safe to use.
