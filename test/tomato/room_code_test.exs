defmodule Tomato.RoomCodeTest do
  use ExUnit.Case, async: true

  alias Tomato.RoomCode

  test "generate/0 returns a 6-character string" do
    code = RoomCode.generate()
    assert String.length(code) == 6
  end

  test "generate/0 only uses valid characters" do
    valid_chars = MapSet.new(~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    for _ <- 1..100 do
      code = RoomCode.generate()

      code
      |> String.to_charlist()
      |> Enum.each(fn char ->
        assert MapSet.member?(valid_chars, char),
               "Invalid character #{<<char>>} in code #{code}"
      end)
    end
  end

  test "generate/0 produces unique codes" do
    codes = for _ <- 1..100, do: RoomCode.generate()
    assert length(Enum.uniq(codes)) == 100
  end

  test "valid?/1 accepts valid 6-char codes" do
    assert RoomCode.valid?("ABC234")
    assert RoomCode.valid?("TMKX29")
    assert RoomCode.valid?(RoomCode.generate())
  end

  test "valid?/1 rejects invalid codes" do
    refute RoomCode.valid?("")
    refute RoomCode.valid?("ABC")
    refute RoomCode.valid?("ABC2345")
    refute RoomCode.valid?("abc234")
    refute RoomCode.valid?("ABC 34")
    refute RoomCode.valid?("ABC0I1")
    refute RoomCode.valid?("../../x")
    refute RoomCode.valid?(nil)
  end
end
