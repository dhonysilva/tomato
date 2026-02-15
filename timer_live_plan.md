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
- Large centered timer display (`font-mono text-8xl tabular-nums`) showing MM:SS
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

## Verification

1. Run `mix phx.server` — should compile and start without errors
2. Visit http://localhost:4000 — should show "25:00" timer with Start button
3. Click Start — timer counts down, button changes to Pause
4. Click Pause — timer stops, button changes to Resume
5. Click Reset — timer returns to 25:00
6. Run `mix test` — all tests pass
