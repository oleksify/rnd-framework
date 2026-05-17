---
id: BND2
role: builder
language: elixir
tags: [control-flow, abstraction, boundaries]
applicable_task_types: [new-feature, refactor]
scope: Use Plug.Conn.send_chunked/2 + chunk/2 for large or streaming responses; buffering the full body before send_resp/3 holds the response in memory.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Bandit/Plug response handling: the I/O effect (sending bytes to the client) should happen incrementally as data is produced, not after the full payload is assembled in memory.

**Good:**
```elixir
def stream_export(conn, %{"id" => id}) do
  conn = send_chunked(conn, 200)

  Export.stream_rows(id)
  |> Enum.reduce_while(conn, fn row, conn ->
    case chunk(conn, Export.encode_row(row)) do
      {:ok, conn}    -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end)
end
```

**Worse:**
```elixir
def stream_export(conn, %{"id" => id}) do
  # Builds entire CSV in memory before sending a single byte
  body = Export.stream_rows(id) |> Enum.map(&Export.encode_row/1) |> Enum.join()
  send_resp(conn, 200, body)
end
```

**Why good is better:** Buffering the full body in memory before `send_resp/3` means memory usage scales linearly with response size — a 500 MB export holds 500 MB in the process heap. `send_chunked/2` + `chunk/2` sends bytes to the client as they are produced: the process heap stays small, the client starts receiving data immediately, and a closed connection is detected early via `{:error, :closed}` rather than after the full assembly. Use `reduce_while` to stop producing rows when the client disconnects.
