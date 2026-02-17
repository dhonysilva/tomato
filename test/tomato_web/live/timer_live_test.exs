defmodule TomatoWeb.TimerLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  @test_user_id "test-timer-user"

  setup %{conn: conn} do
    conn = conn |> init_test_session(%{user_id: @test_user_id})
    {:ok, conn: conn}
  end

  test "renders timer at 25:00 on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "25:00"
    assert html =~ "Tomato Focus"
  end

  test "start button begins timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#start-btn")
    view |> element("#start-btn") |> render_click()
    html = render(view)
    assert html =~ "pause-btn"
  end

  test "tick decrements timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    send_tick(@test_user_id, :solo)
    assert render(view) =~ "24:59"
  end

  test "pause button stops timer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    render(view)
    view |> element("#pause-btn") |> render_click()
    html = render(view)
    assert html =~ "start-btn"
    assert html =~ "Timer paused"
  end

  test "reset button restores 25:00", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#start-btn") |> render_click()
    send_tick(@test_user_id, :solo)
    render(view)
    view |> element("#pause-btn") |> render_click()
    render(view)
    view |> element("#reset-btn") |> render_click()
    html = render(view)
    assert html =~ "25:00"
    assert html =~ "Ready to focus?"
  end

  test "create room button navigates to room", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#create-room-btn")
    {:error, {:live_redirect, %{to: "/room/" <> code}}} =
      view |> element("#create-room-btn") |> render_click()
    assert String.length(code) == 6
  end

  defp send_tick(user_id, scope) do
    [{pid, _}] = Registry.lookup(Tomato.TimerRegistry, {user_id, scope})
    send(pid, :tick)
    :sys.get_state(pid)
  end
end
