defmodule TomatoWeb.RoomLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "mounts with room code and timer at 25:00", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC123")
    assert html =~ "ABC123"
    assert html =~ "25:00"
    assert html =~ "Tomato Focus"
  end

  test "room code is uppercased", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/abc123")
    assert html =~ "ABC123"
  end

  test "shows share URL", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC123")
    assert html =~ "/room/ABC123"
  end

  test "shows QR code section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC123")
    assert html =~ "Show QR Code"
  end

  test "shows member count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/room/ABC123")
    assert html =~ "In this room"
  end

  test "start button begins timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC123")
    assert has_element?(view, "#start-btn")
    view |> element("#start-btn") |> render_click()
    assert has_element?(view, "#pause-btn")
    assert render(view) =~ "Focusing"
  end

  test "pause button stops timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC123")
    view |> element("#start-btn") |> render_click()
    view |> element("#pause-btn") |> render_click()
    assert has_element?(view, "#start-btn")
    assert render(view) =~ "Paused"
  end

  test "reset button restores 25:00", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC123")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    view |> element("#pause-btn") |> render_click()
    view |> element("#reset-btn") |> render_click()
    assert render(view) =~ "25:00"
  end

  test "tick decrements timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/ABC123")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    assert render(view) =~ "24:59"
  end
end
