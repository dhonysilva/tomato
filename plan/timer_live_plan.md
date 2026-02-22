# Pomodoro Timer Screen

## Context

Tomato Focus is a Pomodoro app but currently only has the default Phoenix landing page. This plan adds the core feature: a 25-minute countdown timer as the home page, implemented as a LiveView.

## Files to Create

### 1. `lib/tomato_web/live/timer_live.ex` (new)

A single LiveView module with inline template containing:

**State:**
- `seconds_remaining` (integer, starts at 1500 = 25*60)
- `status` (`:stopped` | `:running` | `:paused`)
- `timer_ref` (reference from `Process.send_after` or nil)

**Events:**
- `"start"` — schedules first `:tick` in 1000ms, sets status to `:running`. Also handles resume from `:paused`. If timer is at 0, resets to 25:00 first.
- `"pause"` — cancels pending timer via `Process.cancel_timer/1`, sets status to `:paused`
- `"reset"` — cancels pending timer, resets to 25:00 stopped

**Tick logic (`handle_info(:tick, ...)`):**
- Guards against stale ticks (only processes if `:running`)
- Decrements by 1 second
- At 0: sets status to `:stopped`, no more ticks
- Otherwise: chains next tick with `Process.send_after(self(), :tick, 1000)`

**Template:**
- Wrapped in `<Layouts.app flash={@flash}>`
- Large centered timer display (`text-8xl tabular-nums`) showing MM:SS
- Start/Resume button (shown when stopped/paused), Pause button (shown when running), Reset button (disabled when already at 25:00 stopped)
- Status text: "Ready to focus?" / "Focus time" / "Timer paused" / "Session complete!"
- Uses daisyUI `btn` classes and heroicon icons (`hero-play-solid`, `hero-pause-solid`, `hero-arrow-path`)

## Files to Modify

### 2. `lib/tomato_web/router.ex`

Replace line 20:
```diff
-    get "/", PageController, :home
+    live "/", TimerLive
```

## Files to Delete

### 3. Old page controller files (no longer needed)
- `lib/tomato_web/controllers/page_controller.ex`
- `lib/tomato_web/controllers/page_html.ex`
- `lib/tomato_web/controllers/page_html/home.html.heex`
- `test/tomato_web/controllers/page_controller_test.exs`

I asked to not delete the old page controller files. I might need them later to create a call to action page.

## Verification

1. Run `mix phx.server` — should compile and start without errors
2. Visit http://localhost:4000 — should show "25:00" timer with Start button
3. Click Start — timer counts down, button changes to Pause
4. Click Pause — timer stops, button changes to Resume
5. Click Reset — timer returns to 25:00
6. Run `mix test` — all tests pass

## How `Process.send_after(self(), :tick, 1000)` Works

`Process.send_after(self(), :tick, 1000)` is the mechanism that drives the countdown.

**What it does:**
- Sends the message `:tick` to `self()` (the current LiveView process) after `1000` milliseconds (1 second)
- Returns a timer reference that can be used to cancel it later with `Process.cancel_timer/1`

**Why this approach:**

LiveView runs as a GenServer process on the server. There's no `setInterval` like in JavaScript. Instead, the idiomatic Elixir pattern is a self-scheduling loop:

1. User clicks **Start** → `handle_event("start", ...)` schedules the first `:tick` in 1 second
2. After 1 second, the process receives the `:tick` message → `handle_info(:tick, ...)` runs
3. Inside `handle_info`, it decrements `seconds_remaining`, updates the socket (which pushes the new value to the browser), and schedules the **next** `:tick` in 1 second
4. This chain repeats until the timer hits 0 or the user pauses

```
Start clicked → [1s] → :tick → [1s] → :tick → [1s] → :tick → ... → 0
```

**Why not `:timer.send_interval`?**

`Process.send_after` is preferred because:
- Each tick is scheduled individually, so **pausing** is simple — just don't schedule the next one (and cancel the pending one with the stored `timer_ref`)
- No need to track and cancel a recurring timer
- If the process crashes and restarts, there's no orphaned interval still firing

**The `timer_ref`:**

When the user clicks Pause, the code calls `Process.cancel_timer(socket.assigns.timer_ref)` to cancel the pending tick that was already scheduled. Without this, a stale `:tick` message could arrive after pausing. The `handle_info` also has a guard (`if status != :running`) as a safety net against any race condition.
