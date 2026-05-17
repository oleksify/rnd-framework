---
id: OBN1
role: builder
language: elixir
tags: [error-handling, defensive-programming, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Design Oban perform/1 to be idempotent — jobs may replay; lookup-then-act beats blind-insert.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by ensuring the side effect inside `perform/1` is safe to repeat — because Oban will retry or replay the job on failure, crash, or deployment restart.

**Good:**
```elixir
defmodule MyApp.Workers.SendWelcomeEmail do
  use Oban.Worker, queue: :mailers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Repo.get(User, user_id) do
      nil  -> :ok                          # already deleted — safe to discard
      user ->
        if user.welcome_sent_at do
          :ok                              # already sent — idempotent skip
        else
          :ok = Mailer.send_welcome(user)
          Repo.update!(Ecto.Changeset.change(user, welcome_sent_at: DateTime.utc_now()))
        end
    end
  end
end
```

**Worse:**
```elixir
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  user = Repo.get!(User, user_id)
  Mailer.send_welcome(user)               # sends again on every replay
  :ok
end
```

**Why good is better:** The worse version sends a duplicate email on every retry — if the job crashes after `send_welcome` but before returning `:ok`, the user receives the email twice. The good version checks a guard column before acting; replaying the job is harmless because the guard short-circuits. Always design `perform/1` assuming the job ran at least once before; the guard column is the cheapest fence. Ref: https://hexdocs.pm/oban/Oban.Worker.html
