defmodule Chat.TimeChannel do

  use Phoenix.Channel
  use Timex

  def join("currenttime:" <> tz, _message, socket) do
    :timer.send_interval(1000, {:currenttime, tz})
    {:ok, socket}
  end

  def handle_info({:currenttime, tz}, socket) do
    date = Date.local
    |> Timezone.convert(Timezone.get(tz))
    %{:hour => hour, :minute => minute, :second => second} = date

    push socket, "time:update", %{hours: String.rjust(inspect(hour), 2, ?0), 
                                  mins: String.rjust(inspect(minute), 2, ?0), 
                                  secs: String.rjust(inspect(second), 2, ?0), 
                                  tz: tz}
    {:noreply, socket}
  end

  def terminate(reason, socket) do
    :ok
  end


end
