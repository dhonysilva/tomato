defmodule TomatoWeb.RoomLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user_id = "room-#{System.unique_integer([:positive])}"
    conn = conn |> init_test_session(%{user_id: user_id})
    {:ok, conn: conn, user_id: user_id}
  end

  test "mounts with room code and timer at 25:00", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC234")
    assert html =~ "ABC234"
    assert html =~ "25:00"
    assert html =~ "Tomato Focus"
  end

  test "room code is uppercased", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/abc234")
    assert html =~ "ABC234"
  end

  test "shows share URL", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC234")
    assert html =~ "/room/ABC234"
  end

  test "shows QR code", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC234")
    assert html =~ "<svg"
  end

  test "shows member count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC234")
    assert html =~ "In this room"
  end

  test "start button begins timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    assert has_element?(view, "#start-btn")
    view |> element("#start-btn") |> render_click()
    html = render(view)
    assert html =~ "pause-btn"
    assert html =~ "Focusing"
  end

  test "pause button stops timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    render(view)
    view |> element("#pause-btn") |> render_click()
    html = render(view)
    assert html =~ "start-btn"
    assert html =~ "Paused"
  end

  test "reset button restores 25:00", %{conn: conn, user_id: user_id} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    send_tick(user_id, "ABC234")
    render(view)
    view |> element("#pause-btn") |> render_click()
    render(view)
    view |> element("#reset-btn") |> render_click()
    assert render(view) =~ "25:00"
  end

  test "tick decrements timer", %{conn: conn, user_id: user_id} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    send_tick(user_id, "ABC234")
    assert render(view) =~ "24:59"
  end

  test "timer updates are broadcast between clients in the same room", %{
    conn: conn,
    user_id: user_id
  } do
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")

    {:ok, view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{user_id: "second-#{System.unique_integer([:positive])}"})
      |> live(~p"/room/ABC234")

    view1 |> element("#start-btn") |> render_click()
    assert render(view1) =~ "Focusing"
    assert render(view2) =~ "Focusing"
    send_tick(user_id, "ABC234")
    assert render(view1) =~ "24:59"
    assert render(view2) =~ "24:59"
  end

  test "member list and count update when additional users join", %{conn: conn} do
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")
    initial_html = render(view1)
    assert initial_html =~ "In this room"

    {:ok, _view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{user_id: "second-#{System.unique_integer([:positive])}"})
      |> live(~p"/room/ABC234")

    updated_html = render(view1)
    assert updated_html =~ "In this room"
    refute initial_html == updated_html
  end

  test "leave room button navigates back to solo timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    assert has_element?(view, "#leave-room-btn")


  test "leaving user is removed from member list and their timer updates are ignored", %{
         conn: conn,
         user_id: user_id
       } do
    # First user joins the room
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")

    # Second user joins the same room
    second_user_id = "second-#{System.unique_integer([:positive])}"

    {:ok, view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{user_id: second_user_id})
      |> live(~p"/room/ABC234")

    # Start the timer as the first user and ensure both see it focusing
    view1 |> element("#start-btn") |> render_click()
    assert render(view1) =~ "Focusing"
    assert render(view2) =~ "Focusing"

    # Capture the member list / room state as seen by the remaining user while both are present
    html_with_both = render(view2)
    assert html_with_both =~ "In this room"

    # First user leaves the room (navigates away)
    {:ok, _redirected_view, _solo_html} =
      view1
      |> element("#leave-room-btn")
      |> render_click()
      |> follow_redirect(conn)

    # Remaining user's member list / room state should update to reflect the departure
    html_after_leave = render(view2)
    assert html_after_leave =~ "In this room"
    refute html_after_leave == html_with_both

    # Capture the remaining user's state before a tick from the user who left
    html_before_tick_from_leaver = render(view2)

    # Simulate a timer tick for the user who left the room
    send_tick(user_id, "ABC234")

    # The remaining user's view should not change in response to the leaving user's ticks
    html_after_tick_from_leaver = render(view2)
    assert html_after_tick_from_leaver == html_before_tick_from_leaver
  end
      view |> element("#leave-room-btn") |> render_click() |> follow_redirect(conn)

    assert html =~ "Tomato Focus"
    refute html =~ "ABC234"
  end

  test "leaving user is removed from member list and their timer updates are ignored", %{
    conn: conn,
    user_id: user_id
  } do
    # First user joins the room
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")
    # Second user joins the same room
    second_user_id = "second-#{System.unique_integer([:positive])}"

    {:ok, view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{user_id: second_user_id})
      |> live(~p"/room/ABC234")

    # Start the timer as the first user and ensure both see it focusing
    view1 |> element("#start-btn") |> render_click()
    assert render(view1) =~ "Focusing"
    assert render(view2) =~ "Focusing"
    # Capture the member list / room state as seen by the remaining user while both are present
    html_with_both = render(view2)
    assert html_with_both =~ "In this room"
    # First user leaves the room (navigates away)
    {:ok, _redirected_view, _solo_html} =
      view1
      |> element("#leave-room-btn")
      |> render_click()
      |> follow_redirect(conn)

    # Remaining user's member list / room state should update to reflect the departure
    html_after_leave = render(view2)
    assert html_after_leave =~ "In this room"
    refute html_after_leave == html_with_both
    # Capture the remaining user's state before a tick from the user who left
    html_before_tick_from_leaver = render(view2)
    # Simulate a timer tick for the user who left the room
    send_tick(user_id, "ABC234")
    # The remaining user's view should not change in response to the leaving user's ticks
    html_after_tick_from_leaver = render(view2)
    assert html_after_tick_from_leaver == html_before_tick_from_leaver
  end

  test "rejects invalid room codes", %{conn: conn} do
    assert_raise TomatoWeb.InvalidRoomCodeError, fn ->
      live(conn, ~p"/room/AB")
    end

    assert_raise TomatoWeb.InvalidRoomCodeError, fn ->
      live(conn, ~p"/room/ABC1234567")
    end

    assert_raise TomatoWeb.InvalidRoomCodeError, fn ->
      live(conn, ~p"/room/abc011")
    end
  end

  defp send_tick(user_id, room_code) do
    [{pid, _}] = Registry.lookup(Tomato.TimerRegistry, {user_id, room_code})
    send(pid, :tick)
    :sys.get_state(pid)
  end
end
