defmodule TomatoWeb.RoomLive do
  use TomatoWeb, :live_view

  import TomatoWeb.TimerHelpers, only: [format_display: 1]

  alias Tomato.TimerServer

  @focus_seconds 25 * 60

  def mount(%{"code" => code}, session, socket) do
    code = String.upcase(code)

    unless Tomato.RoomCode.valid?(code) do
      raise TomatoWeb.InvalidRoomCodeError, code: code
    end

    user_id = session["user_id"]
    user_data = Tomato.UserStore.get(user_id)
    display_name = (user_data && user_data.display_name) || "Tomato-#{String.slice(user_id, 0, 4)}"
    topic = "room:#{code}"

    {seconds_remaining, status, phase, pomodoro_count} =
      if connected?(socket) do
        {:ok, _pid} = TimerServer.ensure_started(user_id, code)
        Phoenix.PubSub.subscribe(Tomato.PubSub, topic)

        # Track in Presence with default state first
        TomatoWeb.Presence.track(self(), topic, user_id, %{
          display_name: display_name,
          status: :stopped,
          seconds_remaining: @focus_seconds,
          phase: :focus
        })

        # Then recover state from GenServer if it was already running
        case TimerServer.get_state(user_id, code) do
          {:ok, state} ->
            TomatoWeb.Presence.update(self(), topic, user_id, %{
              display_name: display_name,
              status: state.status,
              seconds_remaining: state.seconds_remaining,
              phase: state.phase
            })

            {state.seconds_remaining, state.status, state.phase, state.pomodoro_count}

          {:error, :not_found} ->
            {@focus_seconds, :stopped, :focus, 0}
        end
      else
        {@focus_seconds, :stopped, :focus, 0}
      end

    presences = TomatoWeb.Presence.list(topic)
    members = extract_members(presences)

    room_url = TomatoWeb.Endpoint.url() <> ~p"/room/#{code}"
    qr_svg = room_url |> EQRCode.encode() |> EQRCode.svg(width: 200)

    {:ok,
     assign(socket,
       page_title: "Room #{code}",
       room_code: code,
       room_url: room_url,
       qr_svg: qr_svg,
       user_id: user_id,
       display_name: display_name,
       seconds_remaining: seconds_remaining,
       phase_seconds: TimerServer.phase_seconds(phase),
       status: status,
       phase: phase,
       pomodoro_count: pomodoro_count,
       members: members,
       name_set: not connected?(socket) or user_data != nil,
       has_custom_name: (user_data && user_data.has_custom_name) || false
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center" id="room-container">
        <div class="text-center mb-6">
          <p class="text-sm text-base-content/60 mt-1">
            Room <span class="font-mono font-bold tracking-wider text-primary">{@room_code}</span>
          </p>
        </div>

        <div class="tabs tabs-boxed mb-4" id="phase-selector" role="tablist" aria-label="Timer phase">
          <button
            role="tab"
            aria-selected={if @phase == :focus, do: "true", else: "false"}
            class={["tab", @phase == :focus && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="focus"
          >
            Focus
          </button>
          <button
            role="tab"
            aria-selected={if @phase == :short_break, do: "true", else: "false"}
            class={["tab", @phase == :short_break && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="short_break"
          >
            Short Break
          </button>
          <button
            role="tab"
            aria-selected={if @phase == :long_break, do: "true", else: "false"}
            class={["tab", @phase == :long_break && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="long_break"
          >
            Long Break
          </button>
        </div>

        <p id="pomodoro-count" class="text-xs text-base-content/40 mb-4">
          Pomodoro {@pomodoro_count + if(@phase == :focus, do: 1, else: 0)}
        </p>

        <div
          id="timer-display"
          class="text-8xl sm:text-9xl font-bold tracking-widest tabular-nums select-none mb-8"
        >
          {format_display(@seconds_remaining)}
        </div>

        <div class="flex items-center gap-4 mb-8" id="timer-controls">
          <%= if @status == :running do %>
            <button
              id="pause-btn"
              phx-click="pause"
              class="btn btn-warning btn-lg min-w-32 transition-all duration-200 hover:scale-105"
            >
              <.icon name="hero-pause-solid" class="size-5 mr-1" /> Pause
            </button>
          <% else %>
            <button
              id="start-btn"
              phx-click="start"
              class="btn btn-primary btn-lg min-w-32 transition-all duration-200 hover:scale-105"
            >
              <.icon name="hero-play-solid" class="size-5 mr-1" />
              {if @status == :paused, do: "Resume", else: "Start"}
            </button>
          <% end %>

          <button
            id="reset-btn"
            phx-click="reset"
            disabled={@status == :stopped and @seconds_remaining == @phase_seconds}
            class={[
              "btn btn-lg min-w-32 transition-all duration-200",
              if(@status == :stopped and @seconds_remaining == @phase_seconds,
                do: "btn-disabled btn-ghost opacity-50",
                else: "btn-ghost hover:scale-105"
              )
            ]}
          >
            <.icon name="hero-arrow-path" class="size-5 mr-1" /> Reset
          </button>
        </div>

        <div class="w-full max-w-lg" id="room-members">
          <h2 class="text-sm font-semibold text-base-content/70 mb-3">
            <.icon name="hero-user-group" class="size-4 mr-1" /> In this room ({map_size(@members)})
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <%= for {uid, member} <- @members do %>
              <div
                class={[
                  "card bg-base-200 p-3 text-center rounded-lg",
                  uid == @user_id && "ring-2 ring-primary"
                ]}
                id={"member-#{uid}"}
              >
                <p class="text-xs font-medium truncate">
                  <%= if uid == @user_id do %>
                    <%= if @has_custom_name, do: "#{@display_name} (You)", else: "You" %>
                  <% else %>
                    {member.display_name}
                  <% end %>
                </p>
                <p class="text-2xl font-bold tabular-nums mt-1">
                  {format_display(member.seconds_remaining)}
                </p>
                <p class={[
                  "text-xs mt-1",
                  member.status == :running && member.phase == :focus && "text-success",
                  member.status == :running && member.phase != :focus && "text-info",
                  member.status == :paused && "text-warning",
                  member.status == :stopped && "text-base-content/40"
                ]}>
                  <%= cond do %>
                    <% member.status == :running and member.phase == :focus -> %>
                      Focusing
                    <% member.status == :running -> %>
                      On break
                    <% member.status == :paused -> %>
                      Paused
                    <% member.seconds_remaining == 0 -> %>
                      Done!
                    <% true -> %>
                      Idle
                  <% end %>
                </p>
              </div>
            <% end %>
          </div>
        </div>

        <div class="mt-8 flex flex-col items-center gap-4" id="share-section">
          <div class="flex items-center gap-2">
            <input
              id="room-url-input"
              type="text"
              readonly
              value={@room_url}
              class="input input-bordered input-sm font-mono text-xs w-64"
            />
            <button
              id="copy-link-btn"
              phx-click={JS.dispatch("phx:copy", to: "#room-url-input")}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-clipboard-document" class="size-4" />
            </button>
          </div>
          <div class="flex justify-center">
            {Phoenix.HTML.raw(@qr_svg)}
          </div>
        </div>

        <div class="mt-8">
          <button id="leave-room-btn" phx-click="leave_room" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4 mr-1" /> Leave Room
          </button>
        </div>
      </div>
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
    </Layouts.app>
    """
  end

  # Timer events — delegate to GenServer

  def handle_event("start", _params, socket) do
    TimerServer.start_timer(socket.assigns.user_id, socket.assigns.room_code)
    {:noreply, socket}
  end

  def handle_event("pause", _params, socket) do
    TimerServer.pause_timer(socket.assigns.user_id, socket.assigns.room_code)
    {:noreply, socket}
  end

  def handle_event("leave_room", _params, socket) do
    TimerServer.pause_timer(socket.assigns.user_id, socket.assigns.room_code)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("reset", _params, socket) do
    TimerServer.reset_timer(socket.assigns.user_id, socket.assigns.room_code)
    {:noreply, socket}
  end

  def handle_event("set_phase", %{"phase" => phase_str}, socket) do
    phase =
      try do
        String.to_existing_atom(phase_str)
      rescue
        ArgumentError ->
          # Ignore invalid phase values from the client and keep current phase
          socket.assigns.phase
      end

    TimerServer.set_phase(socket.assigns.user_id, socket.assigns.room_code, phase)
    {:noreply, assign(socket, phase: phase)}
  end

  def handle_event("set_name", %{"name" => name}, socket) do
    name = String.trim(name)
    display_name = if name != "", do: name, else: socket.assigns.display_name

    Tomato.UserStore.put(socket.assigns.user_id, display_name, name != "")

    topic = "room:#{socket.assigns.room_code}"

    TomatoWeb.Presence.update(self(), topic, socket.assigns.user_id, %{
      display_name: display_name,
      status: socket.assigns.status,
      seconds_remaining: socket.assigns.seconds_remaining,
      phase: socket.assigns.phase
    })

    {:noreply, assign(socket, display_name: display_name, name_set: true, has_custom_name: name != "")}
  end

  def handle_event("skip_name", _, socket) do
    Tomato.UserStore.put(socket.assigns.user_id, socket.assigns.display_name, false)
    {:noreply, assign(socket, name_set: true)}
  end

  # Timer update from GenServer (any user in the room, including self)
  def handle_info({:timer_update, %{user_id: uid} = payload}, socket) do
    # Ignore updates from users no longer in the room (already left via Presence)
    if uid != socket.assigns.user_id and not Map.has_key?(socket.assigns.members, uid) do
      {:noreply, socket}
    else
      member_update = %{
        display_name: get_member_display_name(socket, uid),
        status: payload.status,
        seconds_remaining: payload.seconds_remaining,
        phase: payload.phase
      }

      members = Map.put(socket.assigns.members, uid, member_update)
      socket = assign(socket, members: members)

      # If this is our own timer, also update top-level assigns + Presence
      socket =
        if uid == socket.assigns.user_id do
          update_presence(socket, payload)

          assign(socket,
            seconds_remaining: payload.seconds_remaining,
            status: payload.status,
            phase: payload.phase,
            pomodoro_count: payload.pomodoro_count,
            phase_seconds: TimerServer.phase_seconds(payload.phase)
          )
        else
          socket
        end

      {:noreply, socket}
    end
  end

  # Presence diff
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presences = TomatoWeb.Presence.list("room:#{socket.assigns.room_code}")
    {:noreply, assign(socket, members: extract_members(presences))}
  end

  # Helpers

  defp get_member_display_name(socket, uid) do
    case Map.get(socket.assigns.members, uid) do
      %{display_name: name} -> name
      nil -> "Tomato-#{String.slice(uid, 0, 4)}"
    end
  end

  defp update_presence(socket, payload) do
    topic = "room:#{socket.assigns.room_code}"

    TomatoWeb.Presence.update(self(), topic, socket.assigns.user_id, %{
      display_name: socket.assigns.display_name,
      status: payload.status,
      seconds_remaining: payload.seconds_remaining,
      phase: payload.phase
    })
  end

  defp extract_members(presences) do
    Enum.reduce(presences, %{}, fn
      {user_id, %{metas: [meta | _]}}, acc ->
        Map.put(acc, user_id, %{
          display_name: meta.display_name,
          status: meta.status,
          seconds_remaining: meta.seconds_remaining,
          phase: Map.get(meta, :phase, :focus)
        })

      {_user_id, %{metas: []}}, acc ->
        acc
    end)
  end
end
