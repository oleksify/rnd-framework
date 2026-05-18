---
id: D-EX-IMPORTS
role: cleanup
language: elixir
tags: [dead-code, imports]
applicable_task_types: [refactor]
scope: Distinguish genuinely unused alias/import/require from directives needed by macros before removing them.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```elixir
defmodule Accounts.UserService do
  alias Accounts.Repo
  alias Accounts.User
  alias Accounts.Audit       # never referenced in this module
  import Ecto.Query
  require Logger             # Logger.debug removed in prior cleanup pass

  def get_user(id), do: Repo.get(User, id)
end
```

**After:**
```elixir
defmodule Accounts.UserService do
  alias Accounts.Repo
  alias Accounts.User
  import Ecto.Query

  def get_user(id), do: Repo.get(User, id)
end
```

**Why after is better:** Unused `alias` and `import` directives inflate the module's apparent surface and mislead readers about which collaborators the module actually depends on. `require` for `Logger` is especially deceptive: it must precede any `Logger.debug/info/error` call, so its presence implies logging exists somewhere. Verify with `grep -n "Audit\|Logger" lib/accounts/user_service.ex` before deleting; if macros from the directive appear nowhere in the file, remove it.
