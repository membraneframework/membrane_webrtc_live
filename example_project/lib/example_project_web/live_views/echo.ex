defmodule ExampleProjectWeb.LiveViews.Echo do
  use ExampleProjectWeb, :live_view
  alias Boombox.Live.WebRTC.{Capture, Player}

  def mount(_params, _session, socket) do
    IO.inspect(socket, label: "MOUNT")

    socket =
      if connected?(socket) do
        ingress_signaling = Membrane.WebRTC.SignalingChannel.new()
        egress_signaling = Membrane.WebRTC.SignalingChannel.new()

        {:ok, _boombox_pid} =
          Task.start_link(fn ->
            Boombox.run(
              input: {:webrtc, ingress_signaling},
              output: {:webrtc, egress_signaling}
            )
          end)

        socket =
          socket
          |> Capture.attach(
            id: "mediaCapture",
            signaling_channel: ingress_signaling,
            audio?: false,
            video?: true
          )
          |> Player.attach(
            id: "videoPlayer",
            signaling_channel: egress_signaling
          )

        socket
        |> assign(
          capture: Capture.get_attached(socket, "mediaCapture"),
          player: Player.get_attached(socket, "videoPlayer")
        )
      else
        socket
      end

    {:ok, socket}
  end

  def render(%{capture: %Capture{}, player: %Player{}} = assigns) do
    ~H"""
    <script>
      console.log(window.liveSocket)
    </script>

    <Capture.live_render socket={@socket} capture={@capture} />
    <Player.live_render socket={@socket} player={@player} />
    """
  end

  def render(assigns) do
    ~H"""
    <script>
      console.log(window.liveSocket)
    </script>
    """
  end
end
