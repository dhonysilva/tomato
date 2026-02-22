# Plan: Full Pomodoro Technique Cycle

## Context

The app currently runs a single 25-minute countdown that stops at zero and waits for the user to act. The Pomodoro Technique requires an automatic cycle: **25 min focus → 5 min short break**, repeating 4 times, then a **15 min long break**, then the whole cycle starts again. This plan adds phase tracking and auto-transition logic throughout the stack — TimerServer, TimerLive (solo), and RoomLive (collaborative).

---

## Files to Modify

1. `lib/tomato/timer_server.ex` — core cycle logic
2. `lib/tomato_web/live/timer_live.ex` — solo timer UI
3. `lib/tomato_web/live/room_live.ex` — room timer UI + Presence

---

## 1. `lib/tomato/timer_server.ex`

### New module constants

Replace `@initial_seconds 25 * 60` with:

```elixir
@focus_seconds       25 * 60   # 1500
@short_break_seconds  5 * 60   #  300
@long_break_seconds  15 * 60   #  900
```

### New state fields (in `init/1`)

```elixir
state = %{
  user_id: user_id,
  scope: scope,
  seconds_remaining: @focus_seconds,
  status: :stopped,
  phase: :focus,          # NEW: :focus | :short_break | :long_break
  pomodoro_count: 0,      # NEW: completed focus sessions
  timer_ref: nil
}
```

### `handle_call(:get_state, ...)` — include new fields in reply

```elixir
reply = %{
  seconds_remaining: state.seconds_remaining,
  status: state.status,
  phase: state.phase,
  pomodoro_count: state.pomodoro_count,
  user_id: state.user_id,
  scope: state.scope
}
```

### `handle_call(:start, ...)` — use phase-aware fallback

```elixir
seconds =
  if state.seconds_remaining == 0,
    do: phase_seconds(state.phase),
    else: state.seconds_remaining
```

### `handle_call(:reset, ...)` — reset to current phase's full duration

```elixir
new_state = %{state |
  seconds_remaining: phase_seconds(state.phase),
  status: :stopped,
  timer_ref: nil
}
```

### `handle_info(:tick, ...)` — auto-transition on reaching zero

Replace the `new_seconds <= 0` branch with:

```elixir
if new_seconds <= 0 do
  case state.phase do
    :focus ->
      new_count = state.pomodoro_count + 1
      {next_phase, next_seconds} =
        if rem(new_count, 4) == 0,
          do: {:long_break, @long_break_seconds},
          else: {:short_break, @short_break_seconds}
      ref = Process.send_after(self(), :tick, 1000)
      new_state = %{state |
        seconds_remaining: next_seconds,
        status: :running,
        phase: next_phase,
        pomodoro_count: new_count,
        timer_ref: ref
      }
      broadcast(new_state)
      {:noreply, new_state}

    _ ->  # :short_break or :long_break
      new_state = %{state |
        seconds_remaining: @focus_seconds,
        status: :stopped,
        phase: :focus,
        timer_ref: nil
      }
      broadcast(new_state)
      {:noreply, new_state, @idle_timeout}
  end
end
```

> **Key UX decision**: Breaks auto-start when focus ends. Focus does NOT auto-start when a break ends — the user consciously begins each pomodoro.

### `broadcast/1` — include new fields in payload

```elixir
payload = %{
  user_id: state.user_id,
  status: state.status,
  seconds_remaining: state.seconds_remaining,
  phase: state.phase,
  pomodoro_count: state.pomodoro_count
}
```

### New private helper

```elixir
defp phase_seconds(:focus),       do: @focus_seconds
defp phase_seconds(:short_break), do: @short_break_seconds
defp phase_seconds(:long_break),  do: @long_break_seconds
```

---

## 2. `lib/tomato_web/live/timer_live.ex`

### `mount/3` — add new assigns

Add `phase`, `pomodoro_count`, and derived `phase_seconds` to the assign block:

```elixir
{seconds_remaining, status, phase, pomodoro_count} =
  if connected?(socket) do
    ...
    case TimerServer.get_state(user_id, :solo) do
      {:ok, state} -> {state.seconds_remaining, state.status, state.phase, state.pomodoro_count}
      {:error, :not_found} -> {@focus_seconds, :stopped, :focus, 0}
    end
  else
    {@focus_seconds, :stopped, :focus, 0}
  end

assign(socket,
  ...
  phase: phase,
  pomodoro_count: pomodoro_count,
  phase_seconds: phase_seconds(phase)   # pre-computed for template
)
```

Remove `initial_seconds` assign (no longer needed) and replace its use in the reset disabled check.

### `handle_info({:timer_update, payload}, ...)` — sync new fields

```elixir
def handle_info({:timer_update, payload}, socket) do
  {:noreply,
   assign(socket,
     seconds_remaining: payload.seconds_remaining,
     status: payload.status,
     phase: payload.phase,
     pomodoro_count: payload.pomodoro_count,
     phase_seconds: phase_seconds(payload.phase)
   )}
end
```

### `render/1` — show phase label, pomodoro counter, updated status text

Add above the timer display:
```heex
<p class="text-sm font-semibold uppercase tracking-widest text-base-content/50 mb-2">
  <%= case @phase do %>
    <% :focus -> %>Focus<% :short_break -> %>Short Break<% :long_break -> %>Long Break
  <% end %>
</p>
<p class="text-xs text-base-content/40 mb-6">
  Pomodoro {@pomodoro_count + if(@phase == :focus, do: 1, else: 0)}
</p>
```

Update reset button disabled condition:
```
disabled={@status == :stopped and @seconds_remaining == @phase_seconds}
```

Update status text:
```heex
<% @status == :running and @phase == :focus -> %> Focus time — stay on task
<% @status == :running -> %>                     Break time — step away
<% @status == :paused -> %>                      Timer paused
<% @seconds_remaining == 0 -> %>                 Session complete!
<% true -> %>                                    Ready to focus?
```

### Add private helper

```elixir
defp phase_seconds(:focus),       do: 25 * 60
defp phase_seconds(:short_break), do: 5 * 60
defp phase_seconds(:long_break),  do: 15 * 60
```

---

## 3. `lib/tomato_web/live/room_live.ex`

### `mount/3` — add `phase` and `pomodoro_count`

- Add `phase: :focus` and `pomodoro_count: 0` to socket assigns (fallback values).
- Update state recovery from `TimerServer.get_state` to read `state.phase` and `state.pomodoro_count`.
- Update initial `Presence.track` call to include `phase: :focus` in the metadata map.
- Update the `Presence.update` call (state recovery branch) to include `phase`.

### `update_presence/2` — include `phase`

```elixir
TomatoWeb.Presence.update(self(), topic, socket.assigns.user_id, %{
  display_name: socket.assigns.display_name,
  status: payload.status,
  seconds_remaining: payload.seconds_remaining,
  phase: payload.phase
})
```

### `extract_members/1` — include `phase`

```elixir
Map.put(acc, user_id, %{
  display_name: meta.display_name,
  status: meta.status,
  seconds_remaining: meta.seconds_remaining,
  phase: meta.phase
})
```

### `handle_info({:timer_update, ...})` — sync `phase` and `pomodoro_count`

Update the own-user branch to also assign `phase` and `pomodoro_count`.
Update `member_update` map to carry `phase` from `payload`.

### Member card in `render/1` — show break phase label

Below the member name (`member.display_name`), update the status text to distinguish break from focus:
```heex
<% member.status == :running and member.phase == :focus -> %> Focusing
<% member.status == :running -> %>                            On break
<% member.status == :paused -> %>                            Paused
<% member.seconds_remaining == 0 -> %>                       Done!
<% true -> %>                                                Idle
```

---

## Verification

1. **Solo timer**: Start the timer → runs 25:00 → at 00:00 automatically transitions to "Short Break" and counts down 5:00 → when break ends, stops at 25:00 in "Focus" phase. User clicks Start for next pomodoro.
2. **Long break**: After completing 4 focus sessions, the 4th break is 15:00 instead of 5:00. Pomodoro counter shows session 5 after the long break ends.
3. **Reset**: During a break, clicking Reset returns to the full break duration (e.g., 5:00). Pomodoro count unchanged.
4. **Room**: Multiple users in a room each have independent phase cycles. Member cards show "On break" vs "Focusing" correctly.
5. **Reconnect**: Navigating away and back recovers `phase` and `pomodoro_count` from `TimerServer.get_state`.
6. **Tests**: Run `mix test` — existing tests should pass. New tests can be added for phase transitions by calling `send_tick` until `seconds_remaining` reaches 0 and asserting the resulting phase.
