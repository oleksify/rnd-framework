---
id: PHX3
role: builder
language: elixir
tags: [control-flow, abstraction, boundaries]
applicable_task_types: [new-feature, refactor]
scope: In LiveView, mount/2 sets up one-time state; handle_params/3 reacts to URL changes — keep them separate.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Phoenix LiveView: mount is the connection boundary (subscriptions, auth), handle_params is the URL boundary (filtering, pagination) — mixing them causes double-initialization or missed updates on live navigation.

**Good:**
```elixir
def mount(_params, session, socket) do
  # One-time setup: auth, subscriptions, static assigns
  user = Accounts.get_user!(session["user_id"])
  if connected?(socket), do: Posts.subscribe()
  {:ok, assign(socket, user: user)}
end

def handle_params(%{"page" => page}, _uri, socket) do
  # Reacts to URL changes: fetch data that depends on params
  posts = Posts.list(page: String.to_integer(page))
  {:noreply, assign(socket, posts: posts, page: page)}
end
```

**Worse:**
```elixir
def mount(%{"page" => page} = params, session, socket) do
  # Mixes one-time setup with param-dependent data
  user  = Accounts.get_user!(session["user_id"])
  posts = Posts.list(page: String.to_integer(page))
  if connected?(socket), do: Posts.subscribe()
  {:ok, assign(socket, user: user, posts: posts)}
end
```

**Why good is better:** When mount handles page-specific data, live navigation (`push_patch`) skips mount entirely and calls only handle_params — so the posts are never refreshed on page change. Separating the two callbacks matches their actual call frequencies: mount fires once per connection, handle_params fires on every URL change. The subscription in mount also correctly uses `connected?/1` to avoid double-subscribing during static render.
