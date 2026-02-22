defmodule TomatoWeb.TimerLive do
  use TomatoWeb, :live_view

  import TomatoWeb.TimerHelpers, only: [format_display: 1]

  alias Tomato.TimerServer

  @focus_seconds 25 * 60

  def mount(_params, session, socket) do
    user_id = session["user_id"]

    {seconds_remaining, status, phase, pomodoro_count} =
      if connected?(socket) do
        {:ok, _pid} = TimerServer.ensure_started(user_id, :solo)
        Phoenix.PubSub.subscribe(Tomato.PubSub, TimerServer.topic(user_id, :solo))

        case TimerServer.get_state(user_id, :solo) do
          {:ok, state} ->
            {state.seconds_remaining, state.status, state.phase, state.pomodoro_count}

          {:error, :not_found} ->
            {@focus_seconds, :stopped, :focus, 0}
        end
      else
        {@focus_seconds, :stopped, :focus, 0}
      end

    {:ok,
     assign(socket,
       page_title: "Timer",
       user_id: user_id,
       seconds_remaining: seconds_remaining,
       phase_seconds: TimerServer.phase_seconds(phase),
       status: status,
       phase: phase,
       pomodoro_count: pomodoro_count
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center justify-center min-h-[60vh]" id="timer-container">
        <div class="tabs tabs-boxed mb-4" id="phase-selector" role="tablist" aria-label="Timer phase">
          <button
            role="tab"
            aria-selected={@phase == :focus}
            class={["tab", @phase == :focus && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="focus"
          >
            Focus
          </button>
          <button
            role="tab"
            aria-selected={@phase == :short_break}
            class={["tab", @phase == :short_break && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="short_break"
          >
            Short Break
          </button>
          <button
            role="tab"
            aria-selected={@phase == :long_break}
            class={["tab", @phase == :long_break && "tab-active"]}
            phx-click="set_phase"
            phx-value-phase="long_break"
          >
            Long Break
          </button>
        </div>

        <p id="pomodoro-count" class="text-xs text-base-content/40 mb-6">
          Pomodoro {@pomodoro_count + if(@phase == :focus, do: 1, else: 0)}
        </p>

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

        <p id="timer-status" class="mt-8 text-sm text-base-content/50">
          <%= cond do %>
            <% @status == :running and @phase == :focus -> %>
              Focus time — stay on task
            <% @status == :running -> %>
              Break time — step away
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
    TimerServer.start_timer(socket.assigns.user_id, :solo)
    {:noreply, socket}
  end

  def handle_event("pause", _params, socket) do
    TimerServer.pause_timer(socket.assigns.user_id, :solo)
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    TimerServer.reset_timer(socket.assigns.user_id, :solo)
    {:noreply, socket}
  end

  def handle_event("set_phase", %{"phase" => phase_str}, socket) do
    case parse_phase(phase_str) do
      {:ok, phase} ->
        TimerServer.set_phase(socket.assigns.user_id, :solo, phase)
        {:noreply, socket}

      :error ->
        # Ignore invalid phase values to avoid crashing the LiveView
        {:noreply, socket}
    end
  end

  defp parse_phase("focus"), do: {:ok, :focus}
  defp parse_phase("short_break"), do: {:ok, :short_break}
  defp parse_phase("long_break"), do: {:ok, :long_break}
  defp parse_phase(_), do: :error

  def handle_info({:timer_update, payload}, socket) do
    {:noreply,
     assign(socket,
       seconds_remaining: payload.seconds_remaining,
       status: payload.status,
       phase: payload.phase,
       pomodoro_count: payload.pomodoro_count,
       phase_seconds: TimerServer.phase_seconds(payload.phase)
     )}
  end
end
