defmodule TomatoWeb.Plugs.EnsureUserIdTest do
  use TomatoWeb.ConnCase

  alias TomatoWeb.Plugs.EnsureUserId

  test "generates a user_id when missing from session", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> EnsureUserId.call(%{})
    user_id = get_session(conn, :user_id)
    assert user_id != nil
  end

  test "generated user_id is an 11-character base64url string", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> EnsureUserId.call(%{})
    user_id = get_session(conn, :user_id)
    # 8 bytes base64url-encoded without padding = 11 characters
    assert String.length(user_id) == 11
    assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, user_id)
  end

  test "preserves existing user_id in session", %{conn: conn} do
    conn = conn |> init_test_session(%{user_id: "existing123"}) |> EnsureUserId.call(%{})
    assert get_session(conn, :user_id) == "existing123"
  end

  test "generates unique user_ids", %{conn: conn} do
    ids =
      for _ <- 1..100 do
        c = conn |> init_test_session(%{}) |> EnsureUserId.call(%{})
        get_session(c, :user_id)
      end

    assert length(Enum.uniq(ids)) == 100
  end
end
