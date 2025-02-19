defmodule Membrane.WebRTC.Live.Capture do
  @moduledoc ~S'''
  Component for sending and playing audio and video via WebRTC from a Phoenix app to a browser (browser subscribes).

  It:
  * renders a single HTMLVideoElement
  * creates WebRTC PeerConnection both on the server and client side
  * connects those two peer connections negotiating a single audio and a single video track
  * attaches audio and video on the client side to the HTMLVideoElement
  * subscribes to the configured PubSub where it expects audio and video packets and sends them to the client side.

  When `LiveExWebRTC.Publisher` is used, audio an video packets are delivered automatically,
  assuming both components are configured with the same PubSub.

  If `LiveExWebRTC.Publisher` is not used, you should send packets to the
  `streams:audio:#{publisher_id}` and `streams:video:#{publisher_id}` topics.

  Keyframe requests are sent under `publishers:#{publisher_id}` topic.

  ## JavaScript Hook

  Player live view requires JavaScript hook to be registered under `Player` name.
  The hook can be created using `createPlayerHook` function.
  For example:

  ```javascript
  import { createPlayerHook } from "live_ex_webrtc";
  let Hooks = {};
  const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
  Hooks.Player = createPlayerHook(iceServers);
  let liveSocket = new LiveSocket("/live", Socket, {
    // ...
    hooks: Hooks
  });
  ```

  ## Examples

  ```elixir
  defmodule LiveTwitchWeb.StreamViewerLive do
    use LiveTwitchWeb, :live_view

    alias LiveExWebRTC.Player

    @impl true
    def render(assigns) do
    ~H"""
    <Player.live_render socket={@socket} player={@player} />
    """
    end

    @impl true
    def mount(_params, _session, socket) do
      socket = Player.attach(socket, id: "player", publisher_id: "publisher", pubsub: LiveTwitch.PubSub)
      {:ok, socket}
    end
  end
  ```
  '''
  use Phoenix.LiveView

  alias Membrane.WebRTC.SignalingChannel

  require Logger

  @type t() :: struct()

  defstruct [:ice_servers, id: nil, signaling_channel: nil, video?: true, audio?: true]

  attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

  attr(:capture, __MODULE__, required: true, doc: """
  #{inspect(__MODULE__)} struct. It is used to pass player id to the newly created live view via live view session.
  This data is then used to do a handshake between parent live view and child live view during which child live view
  receives the whole #{inspect(__MODULE__)} struct.
  """)

  attr(:class, :string, default: nil, doc: "CSS/Tailwind classes for styling")

  @doc """
  Helper function for rendering Capture live view.
  """
  def live_render(assigns) do
    ~H"""
    <%= live_render(@socket, __MODULE__, id: "#{@capture.id}-lv", session: %{"class" => @class, "id" => @capture.id}) %>
    """
  end

  @doc """
  Attaches required hooks and creates `t:t/0` struct.

  Created struct is saved in socket's assigns and has to be passed to `LiveExWebRTC.Player.live_render/1`.

  Options:
  * `id` - capture id. This is typically your user id (if there is users database).
  It is used to identify live view and generated HTML video player.
  * `class` - a list of CSS/Tailwind classes that will be applied to the HTMLVideoPlayer. Defaults to "".
  """
  @spec attach(Phoenix.LiveView.Socket.t(), Keyword.t()) :: Phoenix.LiveView.Socket.t()
  def attach(socket, opts) do
    opts =
      opts
      |> Keyword.validate!([
        :id,
        :signaling_channel,
        video?: true,
        audio?: true,
        ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]
      ])

    capture = struct!(__MODULE__, opts)

    all_captures =
      socket.assigns
      |> Map.get(__MODULE__, %{})
      |> Map.put(capture.id, capture)

    socket
    |> assign(__MODULE__, all_captures)
    |> detach_hook(:capture_handshake, :handle_info)
    |> attach_hook(:capture_handshake, :handle_info, &handshake/2)
  end

  def get_attached(socket, id), do: socket.assigns[__MODULE__][id]

  defp handshake({__MODULE__, {:connected, capture_id, child_pid, _meta}}, socket) do
    # child live view is connected, send it capture struct
    capture =
      socket.assigns
      |> Map.fetch!(__MODULE__)
      |> Map.fetch!(capture_id)

    send(child_pid, capture)

    {:halt, socket}
  end

  defp handshake(_msg, socket) do
    {:cont, socket}
  end

  ## CALLBACKS

  @impl true
  def render(%{capture: nil} = assigns) do
    ~H"""
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@capture.id} phx-hook="Capture" class={@class} style="display: none;"></div>
    """
  end

  @impl true
  def mount(_params, %{"class" => class, "id" => id}, socket) do
    socket = assign(socket, class: class, capture: nil)

    if connected?(socket) do
      send(socket.parent_pid, {__MODULE__, {:connected, id, self(), %{}}})

      socket =
        receive do
          %__MODULE__{} = capture ->
            capture.signaling_channel
            |> SignalingChannel.register_peer(message_format: :json_data)

            media_constraints = %{
              "audio" => inspect(capture.audio?),
              "video" => inspect(capture.video?)
            }

            socket
            |> assign(capture: capture)
            |> push_event("media_constraints-#{capture.id}", media_constraints)
        after
          5000 -> exit(:timeout)
        end

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({SignalingChannel, _pid, message, _metadata}, socket) do
    Logger.info("""
    #{log_prefix(socket.assigns.capture.id)} Sent WebRTC signaling message: #{inspect(message, pretty: true)}
    """)

    {:noreply,
     socket
     |> push_event("webrtc_signaling-#{socket.assigns.capture.id}", message)}
  end

  @impl true
  def handle_event("webrtc_signaling", message, socket) do
    message = Jason.decode!(message)

    Logger.info("""
    #{log_prefix(socket.assigns.capture.id)} Received WebRTC signaling message: #{inspect(message, pretty: true)}
    """)

    if message["data"] do
      SignalingChannel.signal(
        socket.assigns.capture.signaling_channel,
        message
      )
    end

    {:noreply, socket}
  end

  defp log_prefix(id), do: [module: __MODULE__, id: id] |> inspect()
end
