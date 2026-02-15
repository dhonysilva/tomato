defmodule TomatoWeb.PageController do
  use TomatoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
