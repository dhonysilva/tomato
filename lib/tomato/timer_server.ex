defmodule Tomato.TimerServer do
  use GenServer

  @focus_seconds       25 * 60
  @short_break_seconds  5 * 60
  @long_break_seconds  15 * 60
  @idle_timeout :timer.minutes(5)

  # Public API

  def via(user_id, scope) do
    {:via, Registry, {Tomato.TimerRegistry, {user_id, scope}}}
  end

  def topic(user_id, :solo), do: "timer:#{user_id}"
  def topic(_user_id, room_code) when is_binary(room_code), do: "room:#{room_code}"

  def ensure_started(user_id, scope) do
    case DynamicSupervisor.start_child(
           Tomato.TimerSupervisor,
           {__MODULE__, {user_id, scope}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def get_state(user_id, scope) do
    GenServer.call(via(user_id, scope), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def start_timer(user_id, scope) do
    GenServer.call(via(user_id, scope), :start)
  end

  def pause_timer(user_id, scope) do
    GenServer.call(via(user_id, scope), :pause)
  end

  def reset_timer(user_id, scope) do
    GenServer.call(via(user_id, scope), :reset)
  end

  # Child Spec

  def child_spec({user_id, scope}) do
    %{
      id: {__MODULE__, user_id, scope},
      start: {__MODULE__, :start_link, [{user_id, scope}]},
      restart: :temporary
    }
  end

  def start_link({user_id, scope}) do
    GenServer.start_link(__MODULE__, {user_id, scope}, name: via(user_id, scope))
  end

  # Callbacks

  @impl true
  def init({user_id, scope}) do
    state = %{
      user_id: user_id,
      scope: scope,
      seconds_remaining: @focus_seconds,
      status: :stopped,
      phase: :focus,
      pomodoro_count: 0,
      timer_ref: nil
    }

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      seconds_remaining: state.seconds_remaining,
      status: state.status,
      phase: state.phase,
      pomodoro_count: state.pomodoro_count,
      user_id: state.user_id,
      scope: state.scope
    }

    {:reply, {:ok, reply}, state, idle_timeout(state)}
  end

  @impl true
  def handle_call(:start, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    seconds =
      if state.seconds_remaining == 0,
        do: phase_seconds(state.phase),
        else: state.seconds_remaining

    ref = Process.send_after(self(), :tick, 1000)
    new_state = %{state | status: :running, seconds_remaining: seconds, timer_ref: ref}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    new_state = %{state | status: :paused, timer_ref: nil}
    broadcast(new_state)
    {:reply, :ok, new_state, @idle_timeout}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    new_state = %{state | seconds_remaining: phase_seconds(state.phase), status: :stopped, timer_ref: nil}
    broadcast(new_state)
    {:reply, :ok, new_state, @idle_timeout}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.status != :running do
      {:noreply, state, idle_timeout(state)}
    else
      new_seconds = state.seconds_remaining - 1

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

          _ ->
            # :short_break or :long_break — stop and return to focus
            new_state = %{state |
              seconds_remaining: @focus_seconds,
              status: :stopped,
              phase: :focus,
              timer_ref: nil
            }

            broadcast(new_state)
            {:noreply, new_state, @idle_timeout}
        end
      else
        ref = Process.send_after(self(), :tick, 1000)
        new_state = %{state | seconds_remaining: new_seconds, timer_ref: ref}
        broadcast(new_state)
        {:noreply, new_state}
      end
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # Private

  defp broadcast(state) do
    topic = topic(state.user_id, state.scope)

    payload = %{
      user_id: state.user_id,
      status: state.status,
      seconds_remaining: state.seconds_remaining,
      phase: state.phase,
      pomodoro_count: state.pomodoro_count
    }

    Phoenix.PubSub.broadcast(Tomato.PubSub, topic, {:timer_update, payload})
  end

  defp phase_seconds(:focus),       do: @focus_seconds
  defp phase_seconds(:short_break), do: @short_break_seconds
  defp phase_seconds(:long_break),  do: @long_break_seconds

  defp idle_timeout(%{status: :running}), do: :infinity
  defp idle_timeout(_state), do: @idle_timeout
end
