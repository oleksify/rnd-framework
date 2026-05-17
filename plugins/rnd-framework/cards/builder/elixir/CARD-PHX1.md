---
id: PHX1
role: builder
language: elixir
tags: [boundaries, abstraction, decomposition]
applicable_task_types: [new-feature, refactor]
scope: Expose domain operations through a Context module; never let controllers call Repo directly.
specializes: [P-SMALL-MODULES-01]
---

Specializes the small-modules principle by mapping each Phoenix Context to one bounded domain with a stable public API — controllers depend on the Context, not on Repo or internal schemas.

**Good:**
```elixir
# lib/my_app/accounts.ex — the Context boundary
defmodule MyApp.Accounts do
  alias MyApp.Accounts.User

  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  def get_user!(id), do: Repo.get!(User, id)
end

# lib/my_app_web/controllers/user_controller.ex
def create(conn, params) do
  with {:ok, user} <- Accounts.create_user(params) do
    json(conn, %{id: user.id})
  end
end
```

**Worse:**
```elixir
# Controller reaches into Repo and schema directly
def create(conn, params) do
  changeset = MyApp.Accounts.User.changeset(%User{}, params)
  case Repo.insert(changeset) do
    {:ok, user} -> json(conn, %{id: user.id})
    {:error, cs} -> send_resp(conn, 422, "invalid")
  end
end
```

**Why good is better:** When controllers bypass the Context, every caller duplicates the insertion logic — and every business rule (audit logging, email dispatch, quota checks) must be re-added per caller. The Context is the single place that knows how a User is created; the controller only knows how to map HTTP to that operation. Stable boundary: the controller depends on `Accounts.create_user/1`, which can evolve internally without changing the caller.
