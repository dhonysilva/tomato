defmodule TomatoWeb.PresenceTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  @room_code "TESTROOM"

  test "user is tracked in presence when joining a room", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/room/#{@room_code}")

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    assert map_size(presences) == 1

    [{_user_id, %{metas: [meta | _]}}] = Map.to_list(presences)
    assert meta.status == :stopped
    assert meta.seconds_remaining == 25 * 60
    assert is_binary(meta.display_name)
  end

  test "presence updates when timer starts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/#{@room_code}")

    view |> element("#start-btn") |> render_click()

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    [{_user_id, %{metas: [meta | _]}}] = Map.to_list(presences)
    assert meta.status == :running
  end

  test "presence updates when timer is paused", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/#{@room_code}")

    view |> element("#start-btn") |> render_click()
    view |> element("#pause-btn") |> render_click()

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    [{_user_id, %{metas: [meta | _]}}] = Map.to_list(presences)
    assert meta.status == :paused
  end

  test "presence updates when timer is reset", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/#{@room_code}")

    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    view |> element("#pause-btn") |> render_click()
    view |> element("#reset-btn") |> render_click()

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    [{_user_id, %{metas: [meta | _]}}] = Map.to_list(presences)
    assert meta.status == :stopped
    assert meta.seconds_remaining == 25 * 60
  end

  test "presence reflects timer tick", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/#{@room_code}")

    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    # Allow the handle_info to process
    render(view)

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    [{_user_id, %{metas: [meta | _]}}] = Map.to_list(presences)
    assert meta.seconds_remaining == 25 * 60 - 1
  end

  test "multiple users in the same room are tracked", %{conn: conn} do
    {:ok, _view1, _html} = live(conn, ~p"/room/#{@room_code}")

    # Second user with a different session
    conn2 = build_conn() |> init_test_session(%{user_id: "second-user"})
    {:ok, _view2, _html} = live(conn2, ~p"/room/#{@room_code}")

    presences = TomatoWeb.Presence.list("room:#{@room_code}")
    assert map_size(presences) == 2
  end

  test "user is removed from presence when disconnecting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/#{@room_code}")

    presences_before = TomatoWeb.Presence.list("room:#{@room_code}")
    assert map_size(presences_before) == 1

    # Stop the LiveView process to simulate disconnect
    GenServer.stop(view.pid)
    # Give Presence time to process the down event
    Process.sleep(200)

    presences_after = TomatoWeb.Presence.list("room:#{@room_code}")
    assert map_size(presences_after) == 0
  end
end
