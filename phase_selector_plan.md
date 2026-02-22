# Plan: Phase Selector (Manual Phase Switching)

## Context

The current phase display is a plain read-only text label (`<p id="phase-label">`). The user wants to manually jump to any phase (Focus, Short Break, Long Break) by clicking on a visual step/tab selector. Selecting a phase stops the running timer and resets it to that phase's full duration, without affecting `pomodoro_count`.

---

## Files to Modify

1. `lib/tomato/timer_server.ex` — new `set_phase` public API + handler
2. `lib/tomato_web/live/timer_live.ex` — replace label with clickable tabs + event handler
3. `lib/tomato_web/live/room_live.ex` — same UI + event handler

---

## 1. `lib/tomato/timer_server.ex`

### New public function (after `reset_timer/2`)

```elixir
def set_phase(user_id, scope, phase) do
  GenServer.call(via(user_id, scope), {:set_phase, phase})
end
```

### New `handle_call` clause (after `:reset` handler)

```elixir
@impl true
def handle_call({:set_phase, phase}, _from, state) do
  if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

  new_state = %{state |
    phase: phase,
    seconds_remaining: phase_seconds(phase),
    status: :stopped,
    timer_ref: nil
  }

  broadcast(new_state)
  {:reply, :ok, new_state, @idle_timeout}
end
```

> `pomodoro_count` is intentionally left unchanged — the user is picking a phase manually, not completing one.

---

## 2. `lib/tomato_web/live/timer_live.ex`

### Replace `<p id="phase-label">` block (lines 45–57) with a tabs selector

```heex
<div class="tabs tabs-boxed mb-4" id="phase-selector">
  <button
    class={["tab", @phase == :focus && "tab-active"]}
    phx-click="set_phase"
    phx-value-phase="focus"
  >
    Focus
  </button>
  <button
    class={["tab", @phase == :short_break && "tab-active"]}
    phx-click="set_phase"
    phx-value-phase="short_break"
  >
    Short Break
  </button>
  <button
    class={["tab", @phase == :long_break && "tab-active"]}
    phx-click="set_phase"
    phx-value-phase="long_break"
  >
    Long Break
  </button>
</div>
```

### Add event handler (after `handle_event("reset", ...)`)

```elixir
def handle_event("set_phase", %{"phase" => phase_str}, socket) do
  phase = String.to_existing_atom(phase_str)
  TimerServer.set_phase(socket.assigns.user_id, :solo, phase)
  {:noreply, socket}
end
```

> `String.to_existing_atom/1` is safe — `:focus`, `:short_break`, `:long_break` are all pre-existing atoms. The broadcast from `TimerServer` drives all assign updates via the existing `handle_info({:timer_update, ...})`.

---

## 3. `lib/tomato_web/live/room_live.ex`

### Replace `<p id="phase-label">` block with the same tabs selector

Identical markup to `timer_live.ex` above — `@phase` assign already exists in the socket.

### Add event handler (after `handle_event("reset", ...)`)

```elixir
def handle_event("set_phase", %{"phase" => phase_str}, socket) do
  phase = String.to_existing_atom(phase_str)
  TimerServer.set_phase(socket.assigns.user_id, socket.assigns.room_code, phase)
  {:noreply, socket}
end
```

No further changes needed — the existing `handle_info({:timer_update, ...})` already syncs `phase`, `phase_seconds`, `seconds_remaining`, and `status` from the broadcast, and `update_presence/2` already propagates the new phase to Presence so other room members see it.

---

## Verification

1. **Solo** — Open `/`. Click "Short Break" tab → timer resets to 5:00 and stops. Click "Long Break" → 15:00, stopped. Click "Focus" → 25:00, stopped. Start button works from each phase.
2. **Mid-run switch** — Start the focus timer, then click "Short Break" → running timer is cancelled, resets to 5:00, stopped. `pomodoro_count` unchanged.
3. **Room** — Both users see each other's phase change reflected on the member card immediately (via Presence broadcast).
4. **Auto-transition still works** — Let focus run to 0; it still auto-starts the short break as before. The selector then shows "Short Break" as active.
5. **Tests** — Run `mix test`. All existing tests should pass. A new `TimerServer` test can verify `set_phase` stops the timer and resets to the correct duration without changing `pomodoro_count`.
