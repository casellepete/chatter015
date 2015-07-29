defmodule Phoenix.Transports.WebSocket do
  @moduledoc """
  Handles WebSocket clients for the Channel Transport layer.

  ## Configuration

  By default, JSON encoding is used to broker messages to and from clients and
  Websockets, by default, do not timeout if the connection is lost. The
  maximum timeout duration and serializer can be configured in your Socket's
  transport configuration:

      transport :websocket, Phoenix.Transports.WebSocket,
        serializer: MySerializer
        timeout: 60000

  The `serializer` module needs only to implement the `encode!/1` and
  `decode!/2` functions defined by the `Phoenix.Transports.Serializer` behaviour.
  """
  use Plug.Builder

  @behaviour Phoenix.Channel.Transport

  import Phoenix.Controller, only: [endpoint_module: 1]

  alias Phoenix.Socket.Broadcast
  alias Phoenix.Channel.Transport

  plug :fetch_query_params
  plug :check_origin
  plug :upgrade


  @doc """
  Provides the deault transport configuration to sockets.

  * `:serializer` - The `Phoenix.Socket.Message` serializer
  * `:log` - The log level, for example `:info`. Disabled by default
  * `:timeout` - The connection timeout in milliseconds, defaults to `:infinity`
  """
  def default_config() do
    [serializer: Phoenix.Transports.WebSocketSerializer,
     timeout: :infinity,
     log: false]
  end

  def upgrade(%Plug.Conn{method: "GET", params: params} = conn, _) do
    handler  = conn.private.phoenix_socket_handler

    case Transport.socket_connect(Phoenix.Transports.WebSocket, handler, params) do
      {:ok, socket} ->
        conn
        |> put_private(:phoenix_upgrade, {:websocket, __MODULE__})
        |> put_private(:phoenix_socket, socket)
        |> halt()
      :error ->
        conn |> send_resp(403, "") |> halt()
    end
  end
  def upgrade(conn, _) do
    conn |> send_resp(:bad_request, "") |> halt()
  end

  @doc """
  Handles initalization of the websocket.
  """
  def ws_init(conn) do
    Process.flag(:trap_exit, true)
    socket_handler = conn.private.phoenix_socket_handler
    config         = conn.private.phoenix_transport_conf
    endpoint       = endpoint_module(conn)
    serializer     = Keyword.fetch!(config, :serializer)
    timeout        = Keyword.fetch!(config, :timeout)
    socket         = conn.private.phoenix_socket

    if socket.id, do: endpoint.subscribe(self, socket.id, link: true)

    {:ok, %{socket_handler: socket_handler,
            socket: socket,
            endpoint: endpoint,
            sockets: HashDict.new,
            sockets_inverse: HashDict.new,
            serializer: serializer}, timeout}
  end

  @doc """
  Receives JSON encoded `%Phoenix.Socket.Message{}` from client and dispatches
  to Transport layer.
  """
  def ws_handle(opcode, payload, state) do
    msg = state.serializer.decode!(payload, opcode: opcode)

    case Transport.dispatch(msg, state.sockets, self, state.socket_handler, state.socket, state.endpoint, __MODULE__) do
      {:ok, socket_pid, reply_msg} ->
        format_reply(state.serializer.encode!(reply_msg), put(state, msg.topic, socket_pid))
      {:ok, reply_msg} ->
        format_reply(state.serializer.encode!(reply_msg), state)
      :ok ->
        {:ok, state}
      {:error, _reason, error_reply_msg} ->
        # We are assuming the error was already logged elsewhere.
        format_reply(state.serializer.encode!(error_reply_msg), state)
    end
  end

  def ws_info({:EXIT, socket_pid, reason}, state) do
    case HashDict.get(state.sockets_inverse, socket_pid) do
      nil   -> {:ok, state}
      topic ->
        new_state = delete(state, topic, socket_pid)

        case reason do
          :normal ->
            format_reply(state.serializer.encode!(Transport.chan_close_message(topic)), new_state)
          :shutdown ->
            format_reply(state.serializer.encode!(Transport.chan_close_message(topic)), new_state)
          {:shutdown, _} ->
            format_reply(state.serializer.encode!(Transport.chan_close_message(topic)), new_state)
          _other ->
            format_reply(state.serializer.encode!(Transport.chan_error_message(topic)), new_state)
        end
    end
  end

  @doc """
  Detects disconnect broadcasts and shuts down
  """
  def ws_info(%Broadcast{event: "disconnect"}, state) do
    {:shutdown, state}
  end

  def ws_info({:socket_push, :text, _encoded_payload} = msg, state) do
    format_reply(msg, state)
  end

  def ws_info(_, state) do
    {:ok, state}
  end

  def ws_terminate(_reason, _state) do
    :ok
  end

  def ws_close(state) do
    for {pid, _} <- state.sockets_inverse do
      Phoenix.Channel.Server.close(pid)
    end
  end

  defp check_origin(conn, _opts) do
    Transport.check_origin(conn, conn.private.phoenix_transport_conf[:origins])
  end

  defp put(state, topic, socket_pid) do
    %{state | sockets: HashDict.put(state.sockets, topic, socket_pid),
              sockets_inverse: HashDict.put(state.sockets_inverse, socket_pid, topic)}
  end

  defp delete(state, topic, socket_pid) do
    %{state | sockets: HashDict.delete(state.sockets, topic),
              sockets_inverse: HashDict.delete(state.sockets_inverse, socket_pid)}
  end

  defp format_reply({:socket_push, :text, encoded_payload}, state) do
    {:reply, {:text, encoded_payload}, state}
  end
end
