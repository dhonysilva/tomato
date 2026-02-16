defmodule TomatoWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tomato,
    pubsub_server: Tomato.PubSub
end
