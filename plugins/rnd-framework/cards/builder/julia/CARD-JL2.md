---
id: JL2
role: builder
language: julia
tags: [boundaries, imports]
applicable_task_types: [new-feature, refactor]
scope: Use relative `using ..Sibling` imports inside submodules, not fully-qualified parent-module paths.
---

**Good:**
```julia
module MyApp
  module Accounts
    struct User
      id::Int
      name::String
    end
  end

  module Web
    using ..Accounts          # relative — resolves through MyApp's namespace

    function greet(user_id::Int)
      # Accounts.User is visible here
      "hello from Web"
    end
  end

  include("accounts.jl")
  include("web.jl")
end
```

**Worse:**
```julia
module Web
  using MyApp.Accounts        # fully-qualified — parent may not be fully loaded yet
  ...
end
```

**Why good is better:** During `include()` evaluation the parent module `MyApp` is still being constructed — `MyApp.Accounts` may not be bound in `Main` yet. The relative `..Accounts` traverses the module hierarchy starting from the current module's parent (`MyApp`), which is always the module currently being evaluated and therefore always available. Fully-qualified names go through `Main`, whose view of `MyApp` is incomplete until the top-level `include` finishes.
