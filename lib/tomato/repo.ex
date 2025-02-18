defmodule Tomato.Repo do
  use Ecto.Repo,
    otp_app: :tomato,
    adapter: Ecto.Adapters.SQLite3
end
