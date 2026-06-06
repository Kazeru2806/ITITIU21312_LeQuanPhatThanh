defmodule VnPartyWeb.PageControllerTest do
  use VnPartyWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert conn.status == 404
  end
end
