# Plan: Custom User Name on Room Entry

## Context

Currently, when a user enters a Room, their display name is auto-generated as `"Tomato-{first 4 chars of user_id}"` (e.g. `Tomato-aB3x`). The user has no way to set a custom name. This plan adds a name prompt modal that appears when the user first enters a Room, letting them type a personal name that will appear on their countdown card visible to all room members. If the user skips or submits an empty name, the auto-generated default is kept.

## Approach

Show a DaisyUI modal overlay when the user first enters the room (`name_set: false`). Once they submit a name or skip, the modal is dismissed (`name_set: true`) and the chosen name is stored in `socket.assigns.display_name` and synced to Phoenix Presence so all room members see it immediately.

## File to Modify

**`lib/tomato_web/live/room_live.ex`** — only file that needs changes.

---

## Step-by-Step Changes

### 1. Add `name_set: false` in `mount/3`

In the `assign(socket, ...)` call at lines 57–69, add:

```elixir
name_set: false
```

### 2. Add modal to `render/1`

Inside `<Layouts.app ...>`, before the closing `</Layouts.app>`, add the modal block:

```heex
<%= if not @name_set do %>
  <div class="modal modal-open">
    <div class="modal-box">
      <h3 class="font-bold text-lg">What's your name?</h3>
      <p class="py-2 text-sm text-base-content/60">
        It will appear on your countdown card in the room.
      </p>
      <form phx-submit="set_name">
        <input
          type="text"
          name="name"
          placeholder="Your name"
          class="input input-bordered w-full mt-2"
          maxlength="20"
          autofocus
        />
        <div class="modal-action">
          <button type="button" phx-click="skip_name" class="btn btn-ghost">
            Skip
          </button>
          <button type="submit" class="btn btn-primary">
            Join Room
          </button>
        </div>
      </form>
    </div>
  </div>
<% end %>
```

### 3. Add `handle_event("set_name", ...)`

```elixir
def handle_event("set_name", %{"name" => name}, socket) do
  name = String.trim(name)
  display_name = if name != "", do: name, else: socket.assigns.display_name

  topic = "room:#{socket.assigns.room_code}"
  TomatoWeb.Presence.update(self(), topic, socket.assigns.user_id, %{
    display_name: display_name,
    status: socket.assigns.status,
    seconds_remaining: socket.assigns.seconds_remaining
  })

  {:noreply, assign(socket, display_name: display_name, name_set: true)}
end
```

### 4. Add `handle_event("skip_name", ...)`

```elixir
def handle_event("skip_name", _, socket) do
  {:noreply, assign(socket, name_set: true)}
end
```

### 5. No changes needed elsewhere

- `update_presence/2` (line 266) already reads `socket.assigns.display_name`, so future timer updates will carry the correct name automatically.
- `get_member_display_name/2` (line 259) continues to work as the fallback for other members.
- `extract_members/1` reads `meta.display_name` from Presence, which will now reflect the custom name.

---

## Verification

1. Navigate to `/room/XXXXXX` → modal appears prompting for a name.
2. Enter a name → click "Join Room" → modal closes, countdown card shows the typed name.
3. Enter an empty name → click "Join Room" → modal closes, countdown card shows the default `Tomato-xxxx`.
4. Click "Skip" → modal closes, countdown card shows the default `Tomato-xxxx`.
5. Open a second browser tab on the same room URL → second user gets their own modal; after both set names, each sees the other's custom name on their countdown card in real time.
6. Run existing tests: `mix test test/tomato_web/live/room_live_test.exs` — all tests should pass since the modal is only shown on the real browser (connected? socket), and test helpers set `name_set` behavior through assigns or skip the modal by pushing events.

> **Note on tests:** Existing tests may need a `name_set: true` to be set in test setup (via `assign`) if they assert on member card content, since the modal is `modal-open` by default. Alternatively, send a `"skip_name"` event at test start to dismiss it.
