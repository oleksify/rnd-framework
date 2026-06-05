# Python — FP Patterns

Python-specific patterns for the five FP rules in SKILL.md. Idiomatic Python — not Haskell translated to Python.

## 1. Generators Over Eager Lists

Prefer generators and `itertools` for transformations. They compose without materializing intermediate collections.

**Do:**
```python
from itertools import islice

def active_names(users): return (u.name for u in users if u.active)
def first_ten_active(users): return list(islice(active_names(users), 10))
```

**Don't:** build an intermediate list just to take a prefix — `[u.name for u in users][:10]` allocates the full result when you only need 10.

## 2. Comprehensions as Transformations

Use list/dict/set comprehensions as data transformation expressions, not as substitutes for imperative loops with side effects.

**Do:**
```python
counts = {word: text.count(word) for word in vocabulary}
evens  = [x for x in numbers if x % 2 == 0]
unique = {x.lower() for x in tags}
```

**Don't:**
```python
# comprehension with side effects — this is a loop in disguise
[print(x) for x in items]       # Don't: use a for loop instead
[results.append(f(x)) for x in items]  # Don't: just write the for loop
```

## 3. functools — Partial Application and Caching

Use `functools.partial` to specialize functions, `reduce` for folds, and `lru_cache` to memoize pure functions.

**Do:**
```python
from functools import partial, reduce, lru_cache

add_tax = partial(round, ndigits=2)
total   = reduce(lambda acc, x: acc + x.price, cart, 0.0)
@lru_cache(maxsize=256)
def fib(n: int) -> int:
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

**Don't:** write a custom `Memoize` class or `_cache` dict when `lru_cache` handles it. Don't use `reduce` for simple sums — `sum()` is clearer.

## 4. Frozen Dataclasses as Values

Use `@dataclass(frozen=True)` for value objects. Frozen instances are hashable, safe to use as dict keys, and cannot be mutated after construction.

**Do:**
```python
from dataclasses import dataclass, replace

@dataclass(frozen=True)
class Point:
    x: float
    y: float

origin  = Point(0.0, 0.0)
shifted = replace(origin, x=1.0)   # new Point; origin unchanged
```

**Don't:** use `@dataclass` (mutable) for domain values that should be immutable — mutation bugs surface late and are hard to trace.

## 5. NamedTuple for Lightweight Records

Use `typing.NamedTuple` for simple immutable records. Cheaper than `@dataclass(frozen=True)` and supports tuple unpacking.

**Do:**
```python
from typing import NamedTuple

class Rect(NamedTuple):
    width: float
    height: float
    def area(self) -> float:
        return self.width * self.height

w, h = Rect(3.0, 4.0)   # tuple unpacking works
```

**Don't:** use plain `tuple` with positional indices — `rect[0] * rect[1]` breaks silently when the layout changes.

## 6. Type Hints for Immutability Intent

Use `Sequence`, `Mapping`, and `frozenset` in signatures to signal read-only intent. Use `Final` for module-level constants.

**Do:**
```python
from typing import Final, Sequence, Mapping

MAX_RETRIES: Final = 3
def summarize(items: Sequence[str]) -> Mapping[str, int]:
    return {item: len(item) for item in items}
```

**Don't:** annotate parameters as `list` or `dict` when the function only reads them — `Sequence`/`Mapping` signals the contract and prevents accidental mutation.

## 7. Command-Query Separation

A function either returns a value (query) or causes a side effect (command) — not both.

**Do:**
```python
def load_config(path: str) -> dict:              # query — pure read
    with open(path) as f: return json.load(f)

def save_config(path: str, cfg: dict) -> None:   # command — write only
    with open(path, "w") as f: json.dump(cfg, f)
```

**Don't:** write a function that both persists data and returns it — the caller cannot use the output without triggering the side effect.
