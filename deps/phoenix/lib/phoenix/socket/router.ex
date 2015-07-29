defmodule Phoenix.Socket.Router do
  # Routes socket requests to transports
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  @doc """
  Dispatches to the transport adapter configured in the socket handler.

  Sets the following private `%Plug.Conn{}` assigns:

    * `:phoenix_socket_handler` - the socket handler module requested by client
    * `:phoenix_transport_conf` - the list of config for the transport from the
      socket handler
  """
  def call(conn, {transport_name, socket_handler}) do
    case socket_handler.__transport__(transport_name) do
      {transport, config} ->
        conn
        |> log(config)
        |> put_private(:phoenix_socket_handler, socket_handler)
        |> put_private(:phoenix_transport_conf, config)
        |> transport.call(transport.init([]))

      :unsupported ->
        conn
        |> Plug.Logger.call(Plug.Logger.init([]))
        |> send_resp(:bad_request, "")
        |> halt()
    end
  end

  defp log(conn, config) do
    if level = config[:log] do
      Plug.Logger.call(conn, Plug.Logger.init(log: level))
    else
      conn
    end
  end
end
