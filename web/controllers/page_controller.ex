defmodule Chat.PageController do
  use Chat.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", msg: Application.get_env(:chat, :api_key), msg2: "messagetwo"
  end
end
