# Elixir — FP Patterns

Idiomatic Elixir: data flowing through transformations, pattern matching over branching, explicit effect boundaries.

## 1. Pipe Operator Composition

Use `|>` to express a data transformation pipeline. Each step is a named function — readable, testable, reorderable.

**Do:**
```elixir
def process_order(params) do
  params
  |> validate_fields()
  |> normalize_currency()
  |> apply_discounts()
  |> build_order_struct()
end
```

**Don't:** nest as `build_order_struct(apply_discounts(normalize_currency(validate_fields(params))))` — unreadable and hard to insert a step.

## 2. Pattern Matching Over Conditionals

Match on the shape and values of data directly in function heads and `case` expressions instead of if/else chains.

**Do:**
```elixir
def handle_result({:ok, user}),    do: render_user(user)
def handle_result({:error, :not_found}), do: {:error, "User not found"}
def handle_result({:error, reason}),     do: {:error, "Unexpected: #{reason}"}
```

**Don't:**
```elixir
def handle_result(result) do
  if elem(result, 0) == :ok do
    render_user(elem(result, 1))
  else
    {:error, "failed"}
  end
end
```

## 3. `with` Blocks for Happy-Path Chaining

Use `with` to sequence operations that each return `{:ok, value}` or `{:error, reason}`, short-circuiting on the first failure.

**Do:**
```elixir
def create_account(params) do
  with {:ok, email}   <- validate_email(params.email),
       {:ok, user}    <- Repo.insert(%User{email: email}),
       {:ok, _token}  <- Mailer.send_welcome(user) do
    {:ok, user}
  end
end
```

**Don't:** nest `case` expressions or use `try/rescue` for expected failures — `with` keeps the happy path linear and the error handling in one place.

## 4. GenServer as Effect Boundary

Keep business logic in pure functions; use GenServer only to sequence effects and hold state.

**Do:**
```elixir
# Pure logic — easy to unit test
defmodule Cart do
  def add_item(%__MODULE__{} = cart, item), do: %{cart | items: [item | cart.items]}
  def total(%__MODULE__{items: items}),     do: Enum.sum_by(items, & &1.price)
end

# Effect boundary — wraps state + persistence
defmodule CartServer do
  use GenServer
  def handle_call({:add, item}, _from, cart), do: {:reply, :ok, Cart.add_item(cart, item)}
  def handle_call(:total, _from, cart),       do: {:reply, Cart.total(cart), cart}
end
```

**Don't:** put `Repo.insert/1` or HTTP calls inside the pure module — separate computation from effects so core logic is testable without starting a process.

## 5. Structs as Immutable Values

Transformations return new structs; the original is never mutated.

**Do:**
```elixir
defmodule Invoice do
  defstruct [:id, :amount, :status]
  def mark_paid(%__MODULE__{} = inv),    do: %{inv | status: :paid}
  def apply_tax(%__MODULE__{} = inv, r), do: %{inv | amount: inv.amount * (1 + r)}
end

invoice
|> Invoice.apply_tax(0.2)
|> Invoice.mark_paid()
```

**Don't:** use plain maps with string keys for structured domain data — structs catch misspelled keys at compile time and make pipelines self-documenting.

## 6. Higher-Order Functions with Enum / Stream

Prefer `Enum`/`Stream` over explicit recursion. Use `Stream` for lazy evaluation of large sequences.

**Do:**
```elixir
active_totals =
  orders
  |> Stream.filter(& &1.status == :active)
  |> Stream.map(& &1.total)
  |> Enum.sum()
```

**Don't:** accumulate manually with `Enum.reduce` when a `filter |> map |> sum` chain expresses the intent clearly.