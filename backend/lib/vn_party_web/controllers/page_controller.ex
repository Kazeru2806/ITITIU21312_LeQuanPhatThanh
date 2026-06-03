defmodule VnPartyWeb.PageController do
  use VnPartyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
