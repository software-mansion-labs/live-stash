defmodule TestingWeb.PageController do
  use TestingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
