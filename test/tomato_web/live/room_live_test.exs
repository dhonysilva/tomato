defmodule TomatoWeb.RoomLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

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
    assert has_element?(view, "#pause-btn")
    assert render(view) =~ "Focusing"
  end

  test "pause button stops timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    view |> element("#pause-btn") |> render_click()
    assert has_element?(view, "#start-btn")
    assert render(view) =~ "Paused"
  end

  test "reset button restores 25:00", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    view |> element("#pause-btn") |> render_click()
    view |> element("#reset-btn") |> render_click()
    assert render(view) =~ "25:00"
  end

  test "tick decrements timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC234")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    assert render(view) =~ "24:59"
  end

  test "timer updates are broadcast between clients in the same room", %{conn: conn} do
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")

    {:ok, view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> live(~p"/room/ABC234")

    view1 |> element("#start-btn") |> render_click()
    assert render(view1) =~ "Focusing"
    assert render(view2) =~ "Focusing"
    send(view1.pid, :tick)
    assert render(view1) =~ "24:59"
    assert render(view2) =~ "24:59"
  end

  test "member list and count update when additional users join", %{conn: conn} do
    {:ok, view1, _html1} = live(conn, ~p"/room/ABC234")
    initial_html = render(view1)
    assert initial_html =~ "In this room"

    {:ok, _view2, _html2} =
      Phoenix.ConnTest.build_conn()
      |> live(~p"/room/ABC234")

    updated_html = render(view1)
    assert updated_html =~ "In this room"
    refute initial_html == updated_html
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
end
