# Room Feature for Tomato Focus

## Context

Tomato Focus currently has a solo timer at `/`. This plan adds collaborative Rooms where users can focus together — each running their own 25-minute timer, visible to all room members in real time via PubSub and Presence.

## Key Decisions

- **Ephemeral rooms** — no database. Rooms exist while someone is present, vanish when empty. No migrations needed.
- **No auth** — anonymous users get a random `user_id` stored in the session cookie.
- **Room codes** — 6-char alphanumeric (e.g. `TM7K2X`), easy to share verbally.
- **Each user runs their OWN timer** — not a shared global timer. Others see it in real time.
- **QR code** via `eqrcode` — pure Elixir, outputs inline SVG.

## Implementation Steps

### Step 1: Add dependency

**`mix.exs`** — add `{:eqrcode, "~> 0.2.0"}` to deps, then `mix deps.get`.

### Step 2: Presence module

**Create `lib/tomato_web/presence.ex`:**
```elixir
defmodule TomatoWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tomato,
    pubsub_server: Tomato.PubSub
end
```

**Edit `lib/tomato/application.ex`** — add `TomatoWeb.Presence` to children after PubSub, before Endpoint.

### Step 3: User identity plug

**Create `lib/tomato_web/plugs/ensure_user_id.ex`:**
- Checks session for `user_id`, generates a random one if missing via `:crypto.strong_rand_bytes/1`.

**Edit `lib/tomato_web/router.ex`** — add `plug TomatoWeb.Plugs.EnsureUserId` to `:browser` pipeline.

### Step 4: Room code utility

**Create `lib/tomato/room_code.ex`:**
- `generate/0` returns a 6-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (excludes ambiguous 0/O/1/I).

### Step 5: RoomLive (core feature)

**Create `lib/tomato_web/live/room_live.ex`:**

**Mount:**
- Extract `code` from params, `user_id` from session
- Generate display name: `"Tomato-#{String.slice(user_id, 0, 4)}"`
- Subscribe to PubSub topic `"room:#{code}"`
- Track via `TomatoWeb.Presence.track/4` with initial timer state
- Generate room URL and QR SVG via `EQRCode`
- List current presences to populate members map

**State (assigns):**
- `room_code`, `room_url`, `qr_svg`, `user_id`, `display_name`
- Personal timer: `seconds_remaining`, `status`, `timer_ref`, `initial_seconds`
- `members` — map of `user_id => %{display_name, status, seconds_remaining}`

**Timer events** (`start`, `pause`, `reset`):
- Same logic as TimerLive, plus after each change:
  - Broadcast `{:timer_update, payload}` via PubSub
  - Update Presence metas

**handle_info callbacks:**
- `:tick` — decrement + broadcast (same self-scheduling loop as TimerLive)
- `{:timer_update, payload}` — update `members` map (ignore own broadcasts)
- `%Phoenix.Socket.Broadcast{event: "presence_diff"}` — re-list presences, update members

**Template:**
- Room code display at top
- Personal timer (large MM:SS) with Start/Pause/Reset buttons
- Members grid: cards showing each user's name, timer value, and status (Focusing/Paused/Idle/Done)
- Current user's card highlighted with a ring
- Share section: copyable URL input + QR code in a collapsible `<details>`

### Step 6: Update TimerLive

**Edit `lib/tomato_web/live/timer_live.ex`:**
- Add "Create Room" button below timer controls
- Add `handle_event("create_room", ...)` that generates a code and does `push_navigate(socket, to: ~p"/room/#{code}")`

### Step 7: Router

**Edit `lib/tomato_web/router.ex`:**
- Add `live "/room/:code", RoomLive` inside the existing scope

## Files Summary

| Action | File |
|--------|------|
| EDIT | `mix.exs` — add eqrcode dep |
| CREATE | `lib/tomato_web/presence.ex` |
| EDIT | `lib/tomato/application.ex` — add Presence to supervision tree |
| CREATE | `lib/tomato_web/plugs/ensure_user_id.ex` |
| CREATE | `lib/tomato/room_code.ex` |
| CREATE | `lib/tomato_web/live/room_live.ex` |
| EDIT | `lib/tomato_web/live/timer_live.ex` — add Create Room button |
| EDIT | `lib/tomato_web/router.ex` — add plug + route |

## Verification

1. `mix compile` — no errors
2. `mix test` — all tests pass
3. Visit `/` — timer works, "Create Room" button visible
4. Click "Create Room" — redirected to `/room/XXXXXX`
5. Room shows personal timer, room code, share link, QR code
6. Open the same `/room/XXXXXX` in another browser tab — both users appear in member list
7. Start timer in one tab — other tab sees it counting down in real time
8. Close one tab — member disappears from the other tab's list
