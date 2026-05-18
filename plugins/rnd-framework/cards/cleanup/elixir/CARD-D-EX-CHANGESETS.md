---
id: D-EX-CHANGESETS
role: cleanup
language: elixir
tags: [dead-code, duplication]
applicable_task_types: [refactor]
scope: Merge Ecto changesets that converged to identical field lists and validations into one canonical function.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```elixir
def create_changeset(user, attrs) do
  user
  |> cast(attrs, [:name, :email, :role])
  |> validate_required([:name, :email])
  |> validate_format(:email, ~r/@/)
  |> unique_constraint(:email)
end

def admin_create_changeset(user, attrs) do
  user
  |> cast(attrs, [:name, :email, :role])
  |> validate_required([:name, :email])
  |> validate_format(:email, ~r/@/)
  |> unique_constraint(:email)
end
```

**After:**
```elixir
def create_changeset(user, attrs) do
  user
  |> cast(attrs, [:name, :email, :role])
  |> validate_required([:name, :email])
  |> validate_format(:email, ~r/@/)
  |> unique_constraint(:email)
end
```

**Why after is better:** Two changesets that accept the same fields, run the same validations, and return the same constraints are a single changeset under two names. The split was likely created to handle a difference that was later reconciled or never materialized. Maintaining duplicates means any future validation change must be applied twice — and one copy will be missed. Confirm they are truly identical (diff them), update all callers to the canonical name, and delete the duplicate.
