# JavaScript / TypeScript / CSS / HTML — KISS Rules

## JavaScript & TypeScript

- Use native APIs before reaching for packages — `fetch` over axios, `URL` over uri-parser, `structuredClone` over lodash.cloneDeep
- Don't add TypeScript generics when concrete types work — `function getUser(id: string): User` over `function get<T>(id: string): T`
- Don't create utility files for one-time helpers — inline the logic at the call site
- Don't add abstraction layers over `fetch` — a wrapper adds indirection without value until you need interceptors
- Don't add state management libraries for local component state — `useState` is enough until you measurably need shared state
- Don't create custom hooks for trivial effects — `useEffect` with a comment is clearer than `useDataFetcher`
- Use `async/await` over `.then()` chains — but don't add `try/catch` around every await unless you handle the error differently than letting it propagate
- Don't add barrel files (`index.ts` re-exports) until imports are genuinely painful
- Don't type every intermediate variable — let TypeScript infer

## CSS

- Use simple selectors — avoid BEM/SMACSS methodology unless the project already uses it
- Don't create CSS utility classes for one-off styles — inline styles or scoped classes are fine
- Use CSS custom properties for values used 3+ times, not for every color and spacing
- Don't add a CSS-in-JS library when a stylesheet works
- Flexbox and Grid solve most layouts — don't reach for layout libraries

## HTML

- Use semantic HTML elements (`nav`, `main`, `article`, `section`) over `div` soup
- Don't add ARIA attributes that duplicate native semantics — a `<button>` doesn't need `role="button"`
- Don't create component abstractions for simple markup — a `<Card>` component wrapping a `<div>` with a class adds indirection for no reuse benefit until it appears 3+ times
