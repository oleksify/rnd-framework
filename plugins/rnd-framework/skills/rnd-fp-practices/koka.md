# Koka — FP Patterns

Koka-specific patterns. Leverages algebraic effects, Perceus reference counting, and FBIP-aware functional style.

## 1. Algebraic Effects as Composition Primitives

Declare effects explicitly; compose operations through effect types rather than hidden state.

**Do:**
```koka
effect log
  fun emit(msg: string): ()

effect storage
  fun get(key: string): maybe<string>
  fun put(key: string, value: string): ()

fun process(key: string): <log,storage> string
  emit("processing " ++ key)
  match get(key)
    Just(v) -> v
    Nothing -> { put(key, "default"); "default" }
```

**Don't:** use mutable globals or hidden IO to thread context — `<log,storage>` makes dependencies explicit and composable.

## 2. Effect Handlers as Dependency Injection

Swap implementations by swapping handlers — no interface objects needed.

**Do:**
```koka
fun with-mock-storage(action: () -> <storage|e> a): e a
  var store := []
  with handler
    fun get(k) = store.lookup(k)
    fun put(k, v) = store := store ++ [(k, v)]
  action()

fun with-file-storage(path: string, action: () -> <storage|e> a): <io|e> a
  with handler
    fun get(k) = file-read(path ++ "/" ++ k).ok
    fun put(k, v) = file-write(path ++ "/" ++ k, v)
  action()
```

**Don't:** pass `StorageImpl` objects as arguments and match on variants — handlers achieve the same substitution with less boilerplate.

## 3. Value Types and Immutability (Perceus)

Prefer values over references; Perceus makes in-place mutation safe for uniquely owned values.

**Do:**
```koka
struct config
  host: string
  port: int
  timeout: int

fun with-timeout(c: config, t: int): config
  Config(c.host, c.port, t)   // Perceus reuses storage when c is unique
```

**Don't:** thread `ref<config>` through the call stack — use `ref` only when mutation is the explicit intent.

## 4. FBIP-Aware Functional Style

Recursive algorithms over unique structures reuse memory automatically (Functional But In-Place).

**Do:**
```koka
fun map-list(xs: list<a>, f: a -> e b): e list<b>
  match xs
    Nil        -> Nil
    Cons(h, t) -> Cons(f(h), map-list(t, f))
// Perceus reuses the Cons cell when xs is unique — zero allocation.
```

**Don't:** introduce an explicit accumulator when the input is consumed — let the compiler exploit uniqueness for zero-copy reuse.

## 5. Higher-Order Functions with Effect Types

Effect polymorphism lets HOFs compose without wrapping or lifting.

**Do:**
```koka
fun filter(xs: list<a>, pred: a -> <e> bool): <e> list<a>
  match xs
    Nil        -> Nil
    Cons(h, t) ->
      val rest = filter(t, pred)
      if pred(h) then Cons(h, rest) else rest

fun pipeline(items: list<string>): <log,storage> list<string>
  items.filter(fn(s) { emit(s); s.length > 3 })
```

**Don't:** monomorphise HOF signatures to `io` when the actual effects are narrower — use effect variables so callers compose freely.

## 6. Effect-Based Command-Query Separation

Separate queries (pure or read-only effects) from commands (write effects).

**Do:**
```koka
// Query: read-only effect
fun current-user(): <auth> user
  auth/whoami()

// Command: write effects
fun grant-role(u: user, role: string): <storage,log> ()
  storage/put("roles/" ++ u.name, role)
  log/emit("granted " ++ role ++ " to " ++ u.name)

// Composition keeps concerns separate
fun promote(name: string): <auth,storage,log> ()
  grant-role(current-user(), "admin")
```

**Don't:** mix read and write operations in one function — keep them separate so queries are usable in pure contexts.
