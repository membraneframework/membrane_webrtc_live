defmodule ExampleProjectWeb.LiveViews.Echo do
  use ExampleProjectWeb, :live_view
  alias Membrane.WebRTC.Live.{Capture, Player}

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        ingress_signaling = Membrane.WebRTC.Signaling.new()
        egress_signaling = Membrane.WebRTC.Signaling.new()

        {:ok, _boombox_pid} =
          Task.start_link(fn ->
            Boombox.run(
              input: {:webrtc, ingress_signaling},
              output: {:webrtc, egress_signaling}
            )
          end)

        socket
        |> Capture.attach(
          id: "mediaCapture",
          signaling: ingress_signaling,
          audio?: false,
          video?: true
        )
        |> Player.attach(
          id: "videoPlayer",
          signaling: egress_signaling
        )
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Capture.live_render socket={@socket} capture={"mediaCapture"} />
    <Player.live_render socket={@socket} player={"videoPlayer"} />
    """
  end
end
