defmodule Tomato.TimerServerTest do
  use ExUnit.Case, async: true

  alias Tomato.TimerServer

  @user_id "test-server-user"
  @initial_seconds 25 * 60

  setup do
    scope = "ROOM#{System.unique_integer([:positive])}"
    {:ok, pid} = TimerServer.ensure_started(@user_id, scope)
    %{scope: scope, pid: pid}
  end

  test "starts with stopped status at 25:00", %{scope: scope} do
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.status == :stopped
    assert state.seconds_remaining == @initial_seconds
  end

  test "ensure_started is idempotent", %{scope: scope, pid: pid} do
    {:ok, same_pid} = TimerServer.ensure_started(@user_id, scope)
    assert same_pid == pid
  end

  test "start sets status to running", %{scope: scope} do
    :ok = TimerServer.start_timer(@user_id, scope)
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.status == :running
  end

  test "pause sets status to paused", %{scope: scope} do
    :ok = TimerServer.start_timer(@user_id, scope)
    :ok = TimerServer.pause_timer(@user_id, scope)
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.status == :paused
  end

  test "reset restores initial seconds and stopped status", %{scope: scope} do
    :ok = TimerServer.start_timer(@user_id, scope)
    :ok = TimerServer.reset_timer(@user_id, scope)
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.status == :stopped
    assert state.seconds_remaining == @initial_seconds
  end

  test "tick decrements seconds_remaining", %{scope: scope, pid: pid} do
    :ok = TimerServer.start_timer(@user_id, scope)
    send(pid, :tick)
    :sys.get_state(pid)
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.seconds_remaining == @initial_seconds - 1
    assert state.status == :running
  end

  test "broadcasts timer_update via PubSub on start", %{scope: scope} do
    topic = TimerServer.topic(@user_id, scope)
    Phoenix.PubSub.subscribe(Tomato.PubSub, topic)

    :ok = TimerServer.start_timer(@user_id, scope)

    assert_receive {:timer_update, %{user_id: @user_id, status: :running}}
  end

  test "broadcasts timer_update via PubSub on tick", %{scope: scope, pid: pid} do
    topic = TimerServer.topic(@user_id, scope)
    Phoenix.PubSub.subscribe(Tomato.PubSub, topic)

    :ok = TimerServer.start_timer(@user_id, scope)
    assert_receive {:timer_update, %{status: :running}}

    send(pid, :tick)
    :sys.get_state(pid)

    assert_receive {:timer_update, %{seconds_remaining: seconds}}
    assert seconds == @initial_seconds - 1
  end

  test "get_state returns error when server not found" do
    assert {:error, :not_found} = TimerServer.get_state("nonexistent", "NOROOM")
  end

  test "topic returns correct topic for solo and room scopes" do
    assert TimerServer.topic("user1", :solo) == "timer:user1"
    assert TimerServer.topic("user1", "ABC234") == "room:ABC234"
  end

  test "4th focus completion triggers long break with correct duration and keeps running",
       %{scope: scope, pid: pid} do
    :ok = TimerServer.start_timer(@user_id, scope)

    # Place the server at the end of the 4th focus session (3 already completed)
    :sys.replace_state(pid, fn state ->
      %{state | phase: :focus, seconds_remaining: 1, pomodoro_count: 3}
    end)

    # Tick to 0 — rem(4, 4) == 0 should select :long_break
    send(pid, :tick)
    :sys.get_state(pid)

    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.phase == :long_break
    assert state.seconds_remaining == 15 * 60
    assert state.status == :running
    assert state.pomodoro_count == 4
  end

  test "break phase completion resets to focus, stops timer, and clears timer_ref",
       %{scope: scope, pid: pid} do
    :ok = TimerServer.start_timer(@user_id, scope)

    # Force into a short break with 1 second remaining
    :sys.replace_state(pid, fn state ->
      %{state | phase: :short_break, seconds_remaining: 1, status: :running}
    end)

    # Tick to 0 — should transition back to :focus and stop
    send(pid, :tick)
    :sys.get_state(pid)

    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.phase == :focus
    assert state.seconds_remaining == 25 * 60
    assert state.status == :stopped

    # timer_ref must be nil — no next tick was scheduled
    raw = :sys.get_state(pid)
    assert raw.timer_ref == nil
  end

  test "focus phase completion auto-starts short break", %{scope: scope, pid: pid} do
    :ok = TimerServer.start_timer(@user_id, scope)

    # Simulate reaching 1 second remaining in focus phase
    :sys.replace_state(pid, fn state ->
      %{state | seconds_remaining: 1}
    end)

    # Tick to 0 — timer should auto-transition to short break
    send(pid, :tick)
    :sys.get_state(pid)

    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.phase == :short_break
    assert state.seconds_remaining == 5 * 60
    assert state.status == :running
    assert state.pomodoro_count == 1
  end
end
