defmodule TomatoWeb.TimerHelpers do
  @doc """
  Formats total seconds as a MM:SS string with zero-padding.

  ## Examples

      iex> TomatoWeb.TimerHelpers.format_display(1500)
      "25:00"

      iex> TomatoWeb.TimerHelpers.format_display(59)
      "00:59"

      iex> TomatoWeb.TimerHelpers.format_display(0)
      "00:00"
  """
  def format_display(total_seconds) do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end
end
