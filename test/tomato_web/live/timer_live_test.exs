defmodule TomatoWeb.TimerLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders timer at 25:00 on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "25:00"
    assert html =~ "Tomato Focus"
  end

  test "start button begins timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#start-btn")
    view |> element("#start-btn") |> render_click()
    assert has_element?(view, "#pause-btn")
  end

  test "tick decrements timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    assert render(view) =~ "24:59"
  end

  test "pause button stops timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    view |> element("#pause-btn") |> render_click()
    assert has_element?(view, "#start-btn")
    assert render(view) =~ "Timer paused"
  end

  test "reset button restores 25:00", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :tick)
    view |> element("#pause-btn") |> render_click()
    view |> element("#reset-btn") |> render_click()
    assert render(view) =~ "25:00"
    assert render(view) =~ "Ready to focus?"
  end

  test "create room button navigates to room", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#create-room-btn")
    {:error, {:live_redirect, %{to: "/room/" <> code}}} =
      view |> element("#create-room-btn") |> render_click()
    assert String.length(code) == 6
  end
end
