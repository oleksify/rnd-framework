# Lean 4 — FP Patterns

## 1. Dependent Types for Data Integrity

Encode invariants in types so violations are compile-time errors, not runtime panics.

**Do:**
```lean
def NonEmpty (α : Type) := { xs : List α // xs ≠ [] }

def head (xs : NonEmpty α) : α :=
  match xs.val, xs.property with
  | x :: _, _ => x
  | [], h     => absurd rfl h

def BoundedNat (n : Nat) := { k : Nat // k < n }
```

**Don't:** use bare `List` and add runtime `if xs.isEmpty then panic!` — the type carries no proof, so callers can't trust safety without reading the implementation.

## 2. Structure / Inductive Types as Immutable Data

Prefer `structure` for product types, `inductive` for sum types. Both are immutable; update via `{ s with field := v }`.

**Do:**
```lean
structure Point where
  x : Float
  y : Float
  deriving Repr

def translate (p : Point) (dx dy : Float) : Point :=
  { p with x := p.x + dx, y := p.y + dy }

inductive Shape
  | circle  (center : Point) (r : Float)
  | rect    (topLeft : Point) (w h : Float)
```

**Don't:** define a class with mutable fields (`var`) for pure data — record update syntax is enough, and mutable classes break referential transparency.

## 3. Pure Functions and `where` Clauses

Keep top-level definitions pure; factor helper logic into `where` clauses to avoid polluting the module namespace.

**Do:**
```lean
def normalise (xs : List Float) : List Float :=
  if total == 0.0 then xs else xs.map (· / total)
  where total := xs.foldl (· + ·) 0.0
```

**Don't:** split a pure transformation into multiple top-level `def`s only meaningful together — `where` keeps helpers co-located and signals they are not public API.

## 4. Do Notation for Monadic Composition

Use `do`/`let`/`←` to sequence monadic steps without nesting. Reserve `IO` for actual I/O; keep business logic pure.

**Do:**
```lean
def readAndDouble (path : String) : IO Nat := do
  let contents ← IO.FS.readFile path
  let n := contents.trim.toNat!
  pure (n * 2)

def pureDouble (n : Nat) : Nat := n * 2   -- pure, unit-testable
```

**Don't:** nest `>>=` manually for multi-step IO — do-notation is idiomatic Lean 4. Don't put pure computations inside `IO` unless they genuinely perform I/O.

## 5. Pattern Matching Over Conditionals

Use exhaustive `match` instead of chains of `if/else`. The compiler enforces totality; missing cases become errors.

**Do:**
```lean
inductive Color | red | green | blue deriving BEq

def complementOf : Color → Color
  | .red   => .cyan
  | .green => .magenta
  | .blue  => .yellow

def describe : Option String → String
  | some s => s!"Value: {s}"
  | none   => "Empty"
```

**Don't:** write `if c == .red then ... else if c == .green then ...` — exhaustiveness is not checked; new constructors silently fall to the `else` branch.

## 6. IO Boundary Separation

Pure computation belongs outside `IO`. Pass values in, return values out; side effects live at the boundary.

**Do:**
```lean
-- Pure: compose, test in isolation
def buildReport (entries : List String) : String :=
  entries.map (s!"- {·}") |>.intercalate "\n"

-- Effectful: only the narrow boundary touches IO
def writeReport (path : String) (entries : List String) : IO Unit := do
  IO.FS.writeFile path (buildReport entries)
```

**Don't:** mix `IO.println` calls with business logic — it couples computation to output, making the function impossible to unit-test without capturing stdout.

## 7. Tactic Composition

Lean 4 proofs are programs. Compose tactics in `by` blocks; use `<;>` to broadcast a tactic to all remaining goals.

**Do:**
```lean
theorem add_comm_zero (n : Nat) : n + 0 = n := by
  induction n with
  | zero      => rfl
  | succ n ih => simp [Nat.succ_add, ih]
```

**Don't:** use `sorry` as a permanent placeholder — it makes theorems unsound and lets downstream proofs compile while being logically broken.
