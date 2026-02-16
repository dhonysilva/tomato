defmodule Tomato.RoomCode do
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  def generate do
    Enum.map_join(1..@code_length, fn _ ->
      <<Enum.random(@alphabet)>>
    end)
  end
end
