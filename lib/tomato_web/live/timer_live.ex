defmodule TomatoWeb.TimerLive do
  use TomatoWeb, :live_view

  @initial_seconds 25 * 60

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Timer",
       seconds_remaining: @initial_seconds,
       initial_seconds: @initial_seconds,
       status: :stopped,
       timer_ref: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center justify-center min-h-[60vh]" id="timer-container">
        <h1 class="text-2xl tracking-tight mb-8">Tomato Focus</h1>

        <div
          id="timer-display"
          class="text-8xl sm:text-9xl font-bold tracking-widest tabular-nums select-none mb-12"
        >
          {format_display(@seconds_remaining)}
        </div>

        <div class="flex items-center gap-4" id="timer-controls">
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

        <p id="timer-status" class="mt-8 text-sm text-base-content/50">
          <%= cond do %>
            <% @status == :running -> %>
              Focus time — stay on task
            <% @status == :paused -> %>
              Timer paused
            <% @seconds_remaining == 0 -> %>
              Session complete!
            <% true -> %>
              Ready to focus?
          <% end %>
        </p>

        <div class="mt-12">
          <button
            id="create-room-btn"
            phx-click="create_room"
            class="btn btn-secondary btn-sm"
          >
            <.icon name="hero-user-group" class="size-4 mr-1" /> Create Room
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("create_room", _params, socket) do
    code = Tomato.RoomCode.generate()
    {:noreply, push_navigate(socket, to: ~p"/room/#{code}")}
  end

  def handle_event("start", _params, socket) do
    seconds =
      if socket.assigns.seconds_remaining == 0,
        do: @initial_seconds,
        else: socket.assigns.seconds_remaining

    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)
    ref = Process.send_after(self(), :tick, 1000)

    {:noreply,
     assign(socket,
       status: :running,
       seconds_remaining: seconds,
       timer_ref: ref
     )}
  end

  def handle_event("pause", _params, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)

    {:noreply,
     assign(socket,
       status: :paused,
       timer_ref: nil
     )}
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)

    {:noreply,
     assign(socket,
       seconds_remaining: @initial_seconds,
       status: :stopped,
       timer_ref: nil
     )}
  end

  def handle_info(:tick, socket) do
    if socket.assigns.status != :running do
      {:noreply, socket}
    else
      new_seconds = socket.assigns.seconds_remaining - 1

      if new_seconds <= 0 do
        {:noreply,
         assign(socket,
           seconds_remaining: 0,
           status: :stopped,
           timer_ref: nil
         )}
      else
        ref = Process.send_after(self(), :tick, 1000)

        {:noreply,
         assign(socket,
           seconds_remaining: new_seconds,
           timer_ref: ref
         )}
      end
    end
  end

  defp format_display(total_seconds) do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end
end
