defmodule FillTheSkyWeb.PageController do
  use FillTheSkyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
