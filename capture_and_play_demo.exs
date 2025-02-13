Application.put_env(:sample, Example.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 5001],
  server: true,
  live_view: [signing_salt: "aaaaaaaa"],
  secret_key_base: String.duplicate("a", 64)
)

# Mix.install([
#   {:plug_cowboy, "~> 2.5"},
#   {:jason, "~> 1.0"},
#   {:phoenix, "~> 1.7.0"},
#   {:phoenix_live_view, "~> 0.19.0"}
# ])

defmodule Example.ErrorView do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Debugger do
  def debug(pid) do
    if Process.alive?(pid) do
      IO.puts("ALIVE #{inspect(pid)} #{self() |> inspect()}")
    else
      IO.puts("NOT ALIVE #{inspect(pid)} #{self() |> inspect()}")
    end

    Process.sleep(1000)

    debug(pid)
  end
end

defmodule Example.HomeLive do
  use Phoenix.LiveView, layout: {__MODULE__, :live}

  alias Boombox.Live.WebRTC.{Capture, Player}

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        ingress_signaling = Membrane.WebRTC.SignalingChannel.new()
        egress_signaling = Membrane.WebRTC.SignalingChannel.new()

        {:ok, boombox_pid} =
          Task.start_link(fn ->
            Boombox.run(
              input: {:webrtc, ingress_signaling},
              output: {:webrtc, egress_signaling}
            )
          end)

        IO.inspect(socket, label: "PARENT MOUNT")

        _debug_task = Task.start_link(fn -> Debugger.debug(boombox_pid) end)

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
        |> assign(
          ingress_signaling: ingress_signaling,
          egress_signaling: egress_signaling,
          boombox: boombox_pid
        )
      else
        socket
      end

    {:ok, socket}
  end

  defp phx_vsn, do: Application.spec(:phoenix, :vsn)
  defp lv_vsn, do: Application.spec(:phoenix_live_view, :vsn)

  def render("live.html", assigns) do
    ~H"""
    <script src={"https://cdn.jsdelivr.net/npm/phoenix@#{phx_vsn()}/priv/static/phoenix.min.js"}></script>
    <script src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@#{lv_vsn()}/priv/static/phoenix_live_view.min.js"}></script>
    <script>
      let Hooks = {};

      function createCaptureHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
        return {
          async mounted() {
            this.handleEvent("media_constraints-" + this.el.id, async (mediaConstraints) => {
              console.log("[" + this.el.id + "] Received media constraints:", mediaConstraints);

              const localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
              const pcConfig = { iceServers: iceServers };
              this.pc = new RTCPeerConnection(pcConfig);

              this.pc.onicecandidate = (event) => {
                if (event.candidate === null) return;
                console.log("[" + this.el.id + "] Sent ICE candidate:", event.candidate);
                message = JSON.stringify({ type: "ice_candidate", data: event.candidate });
                this.pushEventTo(this.el, "webrtc_signaling", message);
              };

              this.pc.onconnectionstatechange = () => {
                console.log(
                  "[" + this.el.id + "] RTCPeerConnection state changed to",
                  this.pc.connectionState
                );
              };

              for (const track of localStream.getTracks()) {
                this.pc.addTrack(track, localStream);
              }

              this.handleEvent("webrtc_signaling-" + this.el.id, async (event) => {
                const { type, data } = event

                switch (type) {
                  case "sdp_answer":
                    console.log("[" + this.el.id + "] Received SDP answer:", data);
                    await this.pc.setRemoteDescription(data);
                    break;
                  case "ice_candidate":
                    console.log("[" + this.el.id + "] Recieved ICE candidate:", data);
                    await this.pc.addIceCandidate(data);
                    break;
                }
              });

              const offer = await this.pc.createOffer();
              await this.pc.setLocalDescription(offer);
              console.log("[" + this.el.id + "] Sent SDP offer:", offer);
              message = JSON.stringify({ type: "sdp_offer", data: offer });
              this.pushEventTo(this.el, "webrtc_signaling", message);
            });
          },
        };
      }

      function createPlayerHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
        return {
          async mounted() {
            this.pc = new RTCPeerConnection({ iceServers: iceServers });
            this.el.srcObject = new MediaStream();

            this.pc.ontrack = (event) => {
              this.el.srcObject.addTrack(event.track);
            };

            this.pc.onicecandidate = (ev) => {
              console.log("[" + this.el.id + "] Sent ICE candidate:", ev.candidate);
              message = JSON.stringify({ type: "ice_candidate", data: ev.candidate });
              this.pushEventTo(this.el, "webrtc_signaling", message);
            };

            const eventName = "webrtc_signaling-" + this.el.id;
            this.handleEvent(eventName, async (event) => {
              const { type, data } = event;

              switch (type) {
                case "sdp_offer":
                  console.log("[" + this.el.id + "] Received SDP offer:", data);
                  await this.pc.setRemoteDescription(data);

                  const answer = await this.pc.createAnswer();
                  await this.pc.setLocalDescription(answer);

                  message = JSON.stringify({ type: "sdp_answer", data: answer });
                  this.pushEventTo(this.el, "webrtc_signaling", message);
                  console.log("[" + this.el.id + "] Sent SDP answer:", answer);

                  break;
                case "ice_candidate":
                  console.log("[" + this.el.id + "] Recieved ICE candidate:", data);
                  await this.pc.addIceCandidate(data);
              }
            });
          },
        };
      }

      const iceServers = [{ urls: "stun:stun.l.google.com:19302" }]
      Hooks.Capture = createCaptureHook(iceServers)
      Hooks.Player = createPlayerHook(iceServers)

      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
        hooks: Hooks
      });

      liveSocket.connect()
    </script>
    <style>
      * { font-size: 1.1em; }
    </style>
    <%= @inner_content %>
    """
  end

  def render(%{capture: %Capture{}, player: %Player{}} = assigns) do
    ~H"""
    <Capture.live_render socket={@socket}, capture={@capture} />
    <Player.live_render socket={@socket} player={@player} />
    """
  end

  def render(assigns) do
    ~H"""
    """
  end
end

defmodule Example.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", Example do
    pipe_through(:browser)

    live("/", HomeLive, :index)
  end
end

defmodule Example.Endpoint do
  use Phoenix.Endpoint, otp_app: :sample
  socket("/live", Phoenix.LiveView.Socket)
  plug(Example.Router)
end

{:ok, _} = Supervisor.start_link([Example.Endpoint], strategy: :one_for_one)
Process.sleep(:infinity)
