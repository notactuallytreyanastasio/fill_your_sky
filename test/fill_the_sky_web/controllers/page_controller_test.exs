defmodule FillTheSkyWeb.PageControllerTest do
  use FillTheSkyWeb.ConnCase

  test "GET /welcome", %{conn: conn} do
    conn = get(conn, ~p"/welcome")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET / renders map live view", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Fill The Sky"
  end
end
