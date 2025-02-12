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

  alias Boombox.Live.Player

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        signaling_channel = Membrane.WebRTC.SignalingChannel.new()

        {:ok, boombox_pid} =
          Task.start_link(fn ->
            # Boombox.run(input: "../output.mp4", output: {:webrtc, signaling_channel})

            overlay =
              Req.get!("https://avatars.githubusercontent.com/u/25247695?s=200&v=4").body
              |> Vix.Vips.Image.new_from_buffer()
              |> then(fn {:ok, img} -> img end)
              |> Image.trim!()
              |> Image.thumbnail!(100)

            bg = Image.new!(640, 480, color: :light_gray)
            max_x = Image.width(bg) - Image.width(overlay)
            max_y = Image.height(bg) - Image.height(overlay)

            Stream.iterate({_x = 300, _y = 0, _dx = 1, _dy = 2, _pts = 0}, fn {x, y, dx, dy, pts} ->
              dx = if (x + dx) in 0..max_x, do: dx, else: -dx
              dy = if (y + dy) in 0..max_y, do: dy, else: -dy
              pts = pts + div(Membrane.Time.seconds(1), _fps = 60)
              {x + dx, y + dy, dx, dy, pts}
            end)
            |> Stream.map(fn {x, y, _dx, _dy, pts} ->
              img = Image.compose!(bg, overlay, x: x, y: y)
              %Boombox.Packet{kind: :video, payload: img, pts: pts}
            end)
            |> Boombox.run(
              input: {:stream, video: :image, audio: false},
              output: {:webrtc, signaling_channel}
            )
          end)

        IO.inspect(socket, label: "PARENT MOUNT")

        _debug_task = Task.start_link(fn -> Debugger.debug(boombox_pid) end)

        socket
        |> Player.attach(id: "videoPlayer", signaling_channel: signaling_channel)
        |> assign(signaling_channel: signaling_channel, boombox: boombox_pid)
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

      function createPlayerHook(iceServers = [{ urls: "stun:stun.l.google.com:19302" }]) {
        return {
          async mounted() {
            console.log("MOUNTED")

            this.pc = new RTCPeerConnection({ iceServers: iceServers });
            this.el.srcObject = new MediaStream()

            this.pc.ontrack = (event) => {
              console.log("NEW TRACK", this.el)
              this.el.srcObject.addTrack(event.track);
            }

            this.pc.onicecandidate = (ev) => {
              console.log("NEW BROWSER ICE CANDIDATE")
              message = JSON.stringify({ type: "ice_candidate", data: ev.candidate });
              this.pushEventTo(this.el, "webrtc_signaling", message);
            };

            const eventName = "webrtc_signaling-" + this.el.id
            this.handleEvent(eventName, async (event) => {

              console.log("NEW SIGNALING MESSAGE", event)

              const { type, data } = event;

              switch (type) {
                case "sdp_offer":
                  console.log("Received SDP offer:", data);
                  await this.pc.setRemoteDescription(data);

                  const answer = await this.pc.createAnswer();
                  await this.pc.setLocalDescription(answer);

                  message = JSON.stringify({ type: "sdp_answer", data: answer });
                  this.pushEventTo(this.el, "webrtc_signaling", message);
                  console.log("Sent SDP answer:", answer);

                  break;
                case "ice_candidate":
                  console.log("Recieved ICE candidate:", data);
                  await this.pc.addIceCandidate(data);
              }
            });
          },
        };
      }

      Hooks.Player = createPlayerHook([{ urls: "stun:stun.l.google.com:19302" }])

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

  def render(%{player: %Player{}} = assigns) do
    ~H"""
    <Player.live_render socket={@socket} player={@player} />
    """
  end

  def render(assigns) do
    ~H"""
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
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
