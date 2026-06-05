# JavaScript / TypeScript — FP Patterns

JS/TS-specific patterns for the five FP rules in SKILL.md.

## 1. Array Method Chains

Express multi-step data transformations as chained array methods rather than loops with accumulated state.

**Do:**
```js
const activeUserNames = users
  .filter(u => u.active)
  .map(u => u.name)
  .sort();
```

**Don't:** accumulate with a `for` loop and a mutable `result` array — that hides transformation intent and makes each stage invisible.

## 2. Immutable Object Patterns

Produce new values instead of mutating inputs. Use spread for shallow copies; `structuredClone` for deep clones.

**Do:**
```js
const updated = { ...user, lastLogin: Date.now() };

const deepCopy = structuredClone(nestedConfig);
deepCopy.server.port = 9000;
```

**Don't:** mutate function arguments — callers cannot reason about their object after the call.

Use `Object.freeze` for module-level constants:

```js
export const DEFAULT_OPTIONS = Object.freeze({ timeout: 5000, retries: 3 });
```

## 3. TypeScript Readonly and `as const`

Encode immutability in the type system so mutations are caught at compile time.

**Do:**
```ts
function process(items: readonly string[]): readonly string[] {
  return items.map(s => s.trim());
}

type Config = Readonly<{
  host: string;
  port: number;
}>;
```

Use `as const` to narrow literal types and prevent widening:

```ts
const DIRECTIONS = ['north', 'south', 'east', 'west'] as const;
type Direction = typeof DIRECTIONS[number]; // 'north' | 'south' | 'east' | 'west'
```

**Don't:** accept `string[]` when the function only reads — use `readonly string[]` so TS enforces the contract at every call site.

## 4. Higher-Order Functions

Pass behavior as arguments to keep logic composable and independently testable.

**Do:**
```ts
const applyDiscount =
  (rate: number) =>
  (price: number): number =>
    price * (1 - rate);

const tenPercent = applyDiscount(0.1);
const prices = [100, 200, 300].map(tenPercent); // [90, 180, 270]
```

**Don't:** repeat the discount formula at every call site — a curried function is reusable and the rate is explicit in the name.

## 5. Composition Utilities

Build complex transforms from small, single-purpose functions rather than nesting calls.

**Do:**
```ts
const pipe =
  <T>(...fns: Array<(x: T) => T>) =>
  (x: T): T =>
    fns.reduce((acc, fn) => fn(acc), x);

const normalizeEmail = pipe(
  (s: string) => s.trim(),
  (s: string) => s.toLowerCase(),
  (s: string) => s.replace(/\s+/g, ''),
);
```

**Don't:** nest calls three-deep — `f(g(h(x)))` obscures application order and makes inserting steps awkward.

## 6. Command-Query Separation in Async Code

Pure data transformations are synchronous functions. Async functions contain I/O effects. Keep them separate.

**Do:**
```ts
// Query (pure, sync)
function buildPayload(order: Order): ApiPayload {
  return { id: order.id, total: order.lines.reduce((s, l) => s + l.price, 0) };
}

// Command (effectful, async)
async function submitOrder(order: Order): Promise<void> {
  const payload = buildPayload(order);  // pure step first
  await api.post('/orders', payload);
}
```

**Don't:** mix computation and I/O in a single async function — the pure transform cannot be unit-tested without mocking the network.
