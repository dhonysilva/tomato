# Plan: Persist Room Name Across LiveView Remounts

## Context

The name modal reappears every time `RoomLive` mounts (page navigation, LiveView reconnect). The cause is `name_set: not connected?(socket)`, which is evaluated fresh on every mount — socket assigns are ephemeral and not carried across remounts. The fix is to persist the user's display name and custom-name flag server-side, keyed by `user_id` (which already persists in the session), so that subsequent mounts can find the stored data and skip the modal.

---

## Files to Create / Modify

1. `lib/tomato/user_store.ex` — new Agent-based per-user name store
2. `lib/tomato/application.ex` — add `Tomato.UserStore` to the supervision tree
3. `lib/tomato_web/live/room_live.ex` — read from store on mount; write to store in `set_name` / `skip_name`

---

## 1. `lib/tomato/user_store.ex` (new file)

```elixir
defmodule Tomato.UserStore do
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def get(user_id), do: Agent.get(__MODULE__, &Map.get(&1, user_id))

  def put(user_id, display_name, has_custom_name) do
    Agent.update(__MODULE__, &Map.put(&1, user_id, %{
      display_name: display_name,
      has_custom_name: has_custom_name
    }))
  end
end
```

---

## 2. `lib/tomato/application.ex`

Add `Tomato.UserStore` to the children list (before `TomatoWeb.Endpoint`):

```elixir
Tomato.UserStore,
```

---

## 3. `lib/tomato_web/live/room_live.ex`

### `mount/3` — derive name state from the store instead of always showing the modal

Replace the two lines that set `display_name` and derive it from `user_id` at the top of `mount/3`:

```elixir
user_id = session["user_id"]
user_data = Tomato.UserStore.get(user_id)
display_name = (user_data && user_data.display_name) || "Tomato-#{String.slice(user_id, 0, 4)}"
```

And in the `assign` block replace the three name-related assigns:

```elixir
display_name: display_name,
name_set: not connected?(socket) or user_data != nil,
has_custom_name: (user_data && user_data.has_custom_name) || false,
```

### `handle_event("set_name", ...)` — persist to store

Add one line after computing `display_name`, before updating Presence:

```elixir
Tomato.UserStore.put(socket.assigns.user_id, display_name, name != "")
```

### `handle_event("skip_name", ...)` — persist to store

```elixir
def handle_event("skip_name", _, socket) do
  Tomato.UserStore.put(socket.assigns.user_id, socket.assigns.display_name, false)
  {:noreply, assign(socket, name_set: true)}
end
```

---

## Verification

1. Open `/room/ABC234`. Modal appears. Enter "Alice" → card shows "Alice (You)". Navigate away to `/` then back to `/room/ABC234` → **modal does not appear**, card shows "Alice (You)".
2. Open a fresh room. Modal appears. Click "Skip". Navigate away and back → **modal does not appear**, card shows "You".
3. Run `mix test` — all existing tests pass. (Tests create a new `user_id` per setup, so the store is always empty for them and the modal-skipping logic stays inert.)
