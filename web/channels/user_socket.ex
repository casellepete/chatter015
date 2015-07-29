defmodule Chat.UserSocket do

  use Phoenix.Socket

  channel "rooms:*", Chat.RoomChannel
  channel "currenttime:*", Chat.TimeChannel

  transport :websocket, Phoenix.Transports.WebSocket
  transport :longpoll, Phoenix.Transports.LongPoll

  def connect(_params, socket) do
    {:ok, socket}
  end

  def id(_socket), do: nil

end
