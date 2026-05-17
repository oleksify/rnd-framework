---
id: SUP-RA2
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: storage.from().getPublicUrl() always returns a URL — it does NOT check whether the bucket is public or the object exists.
specializes: [P-IMPOSSIBLE-01, R9]
---

**Good audit output:**
> `supabase.storage.from('avatars').getPublicUrl(path)` is called and the URL is used directly in an `<img>` tag. The `avatars` bucket must be verified as public in the Supabase dashboard — `getPublicUrl` returns a URL regardless of bucket visibility or object existence. If the bucket is private, every request to that URL will return 400. Flag: confirm bucket policy matches usage.

**Worse audit output:**
> `getPublicUrl` is called and the result is used in the image source. The Supabase storage API is used correctly.

**Why good is better:** Specializes the impossible-states principle for Supabase Storage. Unlike `createSignedUrl`, `getPublicUrl` is a pure URL construction — it performs no network call, no existence check, and no access control check. The returned URL is structurally valid but will 400 at request time if the bucket is private or the object does not exist. Audit that the bucket is explicitly set to public in project settings, and that the call site handles load errors rather than assuming the URL resolves.
