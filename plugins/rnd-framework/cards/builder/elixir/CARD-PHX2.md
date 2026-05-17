---
id: PHX2
role: builder
language: elixir
tags: [boundaries, control-flow, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Templates receive data only through assigns; never read process dictionary or call side-effecting functions from a template.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Phoenix rendering: assigns are the only render input, keeping templates as pure projections with no hidden I/O or side effects.

**Good:**
```elixir
# Controller computes everything, passes it as assigns
def show(conn, %{"id" => id}) do
  user  = Accounts.get_user!(id)
  posts = Posts.list_by_user(user.id)
  render(conn, :show, user: user, posts: posts)
end
```

```heex
<%!-- Template is a pure projection of assigns — no DB calls, no functions called here --%>
<h1><%= @user.name %></h1>
<%= for post <- @posts do %>
  <p><%= post.title %></p>
<% end %>
```

**Worse:**
```heex
<%!-- Template reaches out to fetch its own data --%>
<h1><%= @user.name %></h1>
<%= for post <- MyApp.Posts.list_by_user(@user.id) do %>
  <p><%= post.title %></p>
<% end %>
```

**Why good is better:** Templates that call context functions embed invisible queries — every render triggers a DB hit that has no test coverage, no telemetry, and no lifecycle control. Assigns put the controller in charge: it calls, measures, and assembles; the template only displays. A template with no side effects can be tested with a simple assign map, no connection or database required.
