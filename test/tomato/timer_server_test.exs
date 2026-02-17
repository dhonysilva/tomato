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

  test "start after completion resets to initial seconds", %{scope: scope, pid: pid} do
    :ok = TimerServer.start_timer(@user_id, scope)

    # Simulate reaching 1 second remaining
    :sys.replace_state(pid, fn state ->
      %{state | seconds_remaining: 1}
    end)

    # Tick to 0 — timer should stop
    send(pid, :tick)
    :sys.get_state(pid)

    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.seconds_remaining == 0
    assert state.status == :stopped

    # Starting again should reset to initial
    :ok = TimerServer.start_timer(@user_id, scope)
    {:ok, state} = TimerServer.get_state(@user_id, scope)
    assert state.seconds_remaining == @initial_seconds
    assert state.status == :running
  end
end
