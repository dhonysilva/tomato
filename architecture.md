# Tomato Focus — Architecture

## 1. OTP Supervision Tree

The app starts ten supervised processes in a `one_for_one` strategy. If any child crashes it is restarted independently.

```mermaid
graph TD
    A[Tomato.Supervisor<br/>one_for_one] --> B[TomatoWeb.Telemetry]
    A --> C[Tomato.Repo<br/>SQLite3]
    A --> D[Ecto.Migrator]
    A --> E[DNSCluster]
    A --> F[Phoenix.PubSub<br/>Tomato.PubSub]
    A --> G[TomatoWeb.Presence]
    A --> H[Registry<br/>Tomato.TimerRegistry]
    A --> I[DynamicSupervisor<br/>Tomato.TimerSupervisor]
    A --> J[Tomato.UserStore<br/>Agent]
    A --> K[TomatoWeb.Endpoint]

    I --> L[TimerServer user_1 :solo]
    I --> M[TimerServer user_1 room:ABC234]
    I --> N[TimerServer user_2 room:ABC234]
```

**Key design choices:**
- `TimerRegistry` is a `{user_id, scope}` → `pid` lookup table. `scope` is either `:solo` or a room code string like `"ABC234"`.
- `TimerSupervisor` spawns one `TimerServer` per `{user_id, scope}` pair on demand, via `ensure_started/2` (idempotent).
- `UserStore` is a plain `Agent` holding a map of `user_id → %{display_name, has_custom_name}`. It persists for the lifetime of the app process, surviving LiveView remounts.

---

## 2. HTTP Request & LiveView Connection Lifecycle

```mermaid
sequenceDiagram
    participant Browser
    participant Endpoint
    participant EnsureUserId
    participant Router
    participant LiveView

    Browser->>Endpoint: GET /room/ABC234
    Endpoint->>EnsureUserId: plug pipeline
    Note over EnsureUserId: checks session[:user_id]<br/>generates one if missing<br/>via :crypto.strong_rand_bytes/1
    EnsureUserId->>Router: pass conn with user_id in session
    Router->>LiveView: mount/3 (connected?=false, static render)
    LiveView-->>Browser: HTML with 25:00 default state

    Browser->>Endpoint: WebSocket /live
    Endpoint->>LiveView: mount/3 (connected?=true)
    Note over LiveView: TimerServer.ensure_started<br/>PubSub.subscribe<br/>Presence.track<br/>UserStore.get
    LiveView-->>Browser: LiveView diff (real state)
```

Every browser session gets a stable `user_id` from a signed cookie. The LiveView mounts **twice** — once for the static HTTP render (no subscriptions) and once for the live WebSocket connection (full setup).

---

## 3. Timer State Machine

The `TimerServer` GenServer is the single source of truth for timer state. All LiveViews are just subscribers.

```mermaid
stateDiagram-v2
    [*] --> stopped_focus : init (25:00)

    stopped_focus --> running_focus : start
    running_focus --> paused_focus : pause
    paused_focus --> running_focus : start (resume)
    running_focus --> stopped_focus : reset

    running_focus --> running_short_break : tick reaches 0\npomodoro_count++ (1-3)
    running_focus --> running_long_break : tick reaches 0\npomodoro_count++ (4th, rem==0)

    running_short_break --> stopped_focus : tick reaches 0
    running_long_break --> stopped_focus : tick reaches 0

    note right of running_focus
        :tick every 1 000 ms
        via Process.send_after
    end note

    note right of running_short_break
        Auto-starts (5:00)
        User must manually
        start next focus
    end note
```

**Tick scheduling** — idiomatic Erlang self-scheduling loop. No `setInterval`. Each tick schedules exactly one next tick, making pause trivial (just don't schedule the next one):

```
start → [1s] → :tick → [1s] → :tick → ... → 0 → transition
```

---

## 4. PubSub & Presence — Multi-User Room Synchronisation

```mermaid
sequenceDiagram
    participant User1 as RoomLive (User 1)
    participant TimerSrv as TimerServer (User 1 / ABC234)
    participant PubSub as Phoenix.PubSub<br/>topic: room:ABC234
    participant Presence as TomatoWeb.Presence
    participant User2 as RoomLive (User 2)

    User1->>PubSub: subscribe("room:ABC234")
    User2->>PubSub: subscribe("room:ABC234")

    User1->>Presence: track(user_id, %{name, status, seconds, phase})
    User2->>Presence: track(user_id, %{name, status, seconds, phase})
    Presence-->>User1: presence_diff broadcast
    Presence-->>User2: presence_diff broadcast

    User1->>TimerSrv: start_timer
    TimerSrv->>PubSub: broadcast {:timer_update, payload}
    PubSub-->>User1: handle_info {:timer_update}
    PubSub-->>User2: handle_info {:timer_update}
    Note over User1,User2: Both UIs update simultaneously

    User1->>TimerSrv: tick (internal :tick message)
    TimerSrv->>PubSub: broadcast {:timer_update, payload}
    PubSub-->>User1: updates own timer + Presence.update
    PubSub-->>User2: updates User 1's member card
```

Each user has their **own independent** `TimerServer`. There is no shared global clock. What's synchronised is the *visibility* — every tick a user's server broadcasts its state to the room topic, and all subscribers (other users' LiveViews) update their copy of that member's card.

---

## 5. Module Dependency Map

```mermaid
graph LR
    subgraph Web
        TL[TimerLive]
        RL[RoomLive]
        PR[TomatoWeb.Presence]
        EU[EnsureUserId plug]
    end

    subgraph Core
        TS[TimerServer<br/>GenServer]
        US[UserStore<br/>Agent]
        RC[RoomCode]
        PB[Phoenix.PubSub]
        REG[TimerRegistry]
        SUP[TimerSupervisor]
    end

    subgraph Helpers
        TH[TimerHelpers<br/>format_display/1]
    end

    TL --> TS
    TL --> RC
    TL --> TH

    RL --> TS
    RL --> RC
    RL --> US
    RL --> PR
    RL --> TH

    TS --> PB
    TS --> REG
    TS --> SUP

    PR --> PB

    EU -- "session user_id" --> RL
    EU -- "session user_id" --> TL
```

---

## 6. Feature Evolution (from `/plan`)

The app was built incrementally. Each plan introduced a new architectural layer:

```mermaid
timeline
    title Feature Build-Up
    timer_live_plan : Solo LiveView timer
                    : Process.send_after tick loop
                    : start / pause / reset in LiveView assigns
    room_live_plan  : Extracted TimerServer GenServer
                    : PubSub broadcasts per tick
                    : Presence for member tracking
                    : EnsureUserId plug + RoomCode utility
    pomodoro_full_cicle_plan : phase + pomodoro_count state in TimerServer
                             : Auto-transition on tick reaching zero
                             : phase_seconds/1 helper
    phase_selector_plan : set_phase/3 public API on TimerServer
                        : Guard clause for invalid phases
                        : Clickable tab selector in both LiveViews
    user_name_room_plan     : Name modal on first room entry
                            : display_name in Presence metadata
    user_store_plan         : UserStore Agent added to supervision tree
                            : Persists name across LiveView remounts
```

> The **most significant architectural shift** was between `timer_live_plan` and `room_live_plan`: the tick loop moved out of the LiveView process and into a supervised `GenServer`. This decoupled the timer lifecycle from the browser connection — the timer keeps running even if the WebSocket briefly disconnects.

---

## 7. Data Flow Summary

```mermaid
flowchart TD
    Browser["Browser (WebSocket)"]

    subgraph LiveView Process
        LV["RoomLive / TimerLive\nassigns: seconds_remaining,\nphase, status, members"]
    end

    subgraph GenServer
        TS["TimerServer\nstate: seconds_remaining,\nphase, pomodoro_count,\ntimer_ref"]
    end

    subgraph Shared State
        PB["Phoenix.PubSub\nroom:CODE or timer:user_id"]
        PR["Presence\nmetadata per user"]
        US["UserStore\ndisplay_name per user_id"]
        REG["Registry\n{user_id, scope} → pid"]
    end

    Browser -- "phx-click events" --> LV
    LV -- "GenServer.call" --> TS
    TS -- "broadcast" --> PB
    PB -- "handle_info :timer_update" --> LV
    LV -- "Presence.update" --> PR
    PR -- "presence_diff broadcast" --> LV
    LV -- "read on mount" --> US
    LV -- "write on set_name/skip" --> US
    LV -- "ensure_started" --> REG
    REG -- "pid lookup" --> TS
    LV -- "assigns → render" --> Browser
```

The **browser never talks to the timer directly** — it sends click events to the LiveView, which delegates to the GenServer via `GenServer.call`. The GenServer is the authority and pushes updates back to all subscribers via PubSub. The LiveView is purely a view layer that reacts to those updates.
