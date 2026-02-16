defmodule Tomato.RoomCode do
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  def generate do
    Enum.map_join(1..@code_length, fn _ ->
      <<Enum.random(@alphabet)>>
    end)
  end

  def valid?(code) when is_binary(code) do
    Regex.match?(~r/^[A-Z2-9]{6}$/, code)
  end

  def valid?(_), do: false
end
