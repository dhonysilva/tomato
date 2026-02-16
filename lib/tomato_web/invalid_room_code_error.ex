defmodule TomatoWeb.InvalidRoomCodeError do
  defexception [:code, plug_status: 404]

  @impl true
  def message(%{code: code}) do
    "invalid room code: #{inspect(code)}"
  end
end
