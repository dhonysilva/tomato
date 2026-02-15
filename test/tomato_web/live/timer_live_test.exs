defmodule TomatoWeb.TimerLiveTest do
  use TomatoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "25:00"
    assert html =~ "Tomato Focus"
  end
end
