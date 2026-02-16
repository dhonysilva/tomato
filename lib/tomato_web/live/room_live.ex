defmodule TomatoWeb.RoomLive do
  use TomatoWeb, :live_view

  import TomatoWeb.TimerHelpers, only: [format_display: 1]

  @initial_seconds 25 * 60

  def mount(%{"code" => code}, session, socket) do
    code = String.upcase(code)
    user_id = session["user_id"]
    display_name = "Tomato-#{String.slice(user_id, 0, 4)}"
    topic = "room:#{code}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tomato.PubSub, topic)

      TomatoWeb.Presence.track(self(), topic, user_id, %{
        display_name: display_name,
        status: :stopped,
        seconds_remaining: @initial_seconds
      })
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
       seconds_remaining: @initial_seconds,
       initial_seconds: @initial_seconds,
       status: :stopped,
       timer_ref: nil,
       members: members
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center" id="room-container">
        <div class="text-center mb-6">
          <h1 class="text-2xl tracking-tight">Tomato Focus</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Room <span class="font-mono font-bold tracking-wider text-primary">{@room_code}</span>
          </p>
        </div>

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
            disabled={@status == :stopped and @seconds_remaining == @initial_seconds}
            class={[
              "btn btn-lg min-w-32 transition-all duration-200",
              if(@status == :stopped and @seconds_remaining == @initial_seconds,
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
                <p class="text-xs font-medium truncate">{member.display_name}</p>
                <p class="text-2xl font-bold tabular-nums mt-1">
                  {format_display(member.seconds_remaining)}
                </p>
                <p class={[
                  "text-xs mt-1",
                  member.status == :running && "text-success",
                  member.status == :paused && "text-warning",
                  member.status == :stopped && "text-base-content/40"
                ]}>
                  <%= cond do %>
                    <% member.status == :running -> %>
                      Focusing
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
      </div>
    </Layouts.app>
    """
  end

  # Timer events

  def handle_event("start", _params, socket) do
    seconds =
      if socket.assigns.seconds_remaining == 0,
        do: @initial_seconds,
        else: socket.assigns.seconds_remaining

    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)
    ref = Process.send_after(self(), :tick, 1000)

    socket =
      assign(socket,
        status: :running,
        seconds_remaining: seconds,
        timer_ref: ref
      )

    broadcast_timer_state(socket)
    {:noreply, socket}
  end

  def handle_event("pause", _params, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)

    socket =
      assign(socket,
        status: :paused,
        timer_ref: nil
      )

    broadcast_timer_state(socket)
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)

    socket =
      assign(socket,
        seconds_remaining: @initial_seconds,
        status: :stopped,
        timer_ref: nil
      )

    broadcast_timer_state(socket)
    {:noreply, socket}
  end

  # Tick

  def handle_info(:tick, socket) do
    if socket.assigns.status != :running do
      {:noreply, socket}
    else
      new_seconds = socket.assigns.seconds_remaining - 1

      if new_seconds <= 0 do
        socket =
          assign(socket,
            seconds_remaining: 0,
            status: :stopped,
            timer_ref: nil
          )

        broadcast_timer_state(socket)
        {:noreply, socket}
      else
        ref = Process.send_after(self(), :tick, 1000)

        socket =
          assign(socket,
            seconds_remaining: new_seconds,
            timer_ref: ref
          )

        broadcast_timer_state(socket)
        {:noreply, socket}
      end
    end
  end

  # Timer update from another user
  def handle_info({:timer_update, %{user_id: uid} = payload}, socket) do
    if uid == socket.assigns.user_id do
      {:noreply, socket}
    else
      members = Map.put(socket.assigns.members, uid, payload)
      {:noreply, assign(socket, members: members)}
    end
  end

  # Presence diff
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presences = TomatoWeb.Presence.list("room:#{socket.assigns.room_code}")
    {:noreply, assign(socket, members: extract_members(presences))}
  end

  # Helpers

  defp broadcast_timer_state(socket) do
    topic = "room:#{socket.assigns.room_code}"

    payload = %{
      user_id: socket.assigns.user_id,
      display_name: socket.assigns.display_name,
      status: socket.assigns.status,
      seconds_remaining: socket.assigns.seconds_remaining
    }

    Phoenix.PubSub.broadcast(Tomato.PubSub, topic, {:timer_update, payload})

    TomatoWeb.Presence.update(self(), topic, socket.assigns.user_id, %{
      display_name: socket.assigns.display_name,
      status: socket.assigns.status,
      seconds_remaining: socket.assigns.seconds_remaining
    })
  end

  defp extract_members(presences) do
    Enum.reduce(presences, %{}, fn
      {user_id, %{metas: [meta | _]}}, acc ->
        Map.put(acc, user_id, %{
          display_name: meta.display_name,
          status: meta.status,
          seconds_remaining: meta.seconds_remaining
        })

      {_user_id, %{metas: []}}, acc ->
        acc
    end)
  end

end
