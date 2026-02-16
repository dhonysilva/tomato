defmodule TomatoWeb.Plugs.EnsureUserId do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :user_id) do
      conn
    else
      user_id = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
      put_session(conn, :user_id, user_id)
    end
  end
end
