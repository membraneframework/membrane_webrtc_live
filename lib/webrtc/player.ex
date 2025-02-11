defmodule Boombox.Live.Player do
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

  @type t() :: struct()

  defstruct [:video?, :audio?, :ice_servers, id: nil, signaling_channel: nil]

  attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

  attr(:player, __MODULE__,
    required: true,
    doc: """
    Player struct. It is used to pass player id and publisher id to the newly created live view via live view session.
    This data is then used to do a handshake between parent live view and child live view during which child live view receives
    the whole Player struct.
    """
  )

  attr(:class, :string, default: nil, doc: "CSS/Tailwind classes for styling HTMLVideoElement")

  @doc """
  Helper function for rendering Player live view.
  """
  def live_render(assigns) do
    ~H"""
    <%= live_render(@socket, __MODULE__, id: "#{@player.id}-lv", session: %{"class" => @class}) %>
    """
  end

  @doc """
  Attaches required hooks and creates `t:t/0` struct.

  Created struct is saved in socket's assigns and has to be passed to `LiveExWebRTC.Player.live_render/1`.

  Options:
  * `id` - player id. This is typically your user id (if there is users database).
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

    player = struct!(__MODULE__, opts)

    socket
    |> assign(player: player)
    |> attach_hook(:handshake, :handle_info, &handshake/2)
  end

  defp handshake({__MODULE__, {:connected, ref, child_pid, _meta}}, socket) do
    # child live view is connected, send it player struct
    send(child_pid, {ref, socket.assigns.player})
    {:halt, socket}
  end

  defp handshake(_msg, socket) do
    {:cont, socket}
  end

  ## CALLBACKS

  @impl true
  def render(%{player: nil} = assigns) do
    ~H"""
    NOT RENDERED {inspect(self())}
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    RENDERED  {inspect(self())}
    <video id={@player.id} phx-hook="Player" class={@class} controls autoplay muted></video>
    """
  end

  # todo: simplify the function below later, but for now it should work fine
  @impl true
  def mount(_params, %{"class" => class}, socket) do
    socket = assign(socket, class: class, player: nil)

    IO.inspect({self(), connected?(socket)}, label: "MOUNT BEGIN")

    if connected?(socket) do
      ref = make_ref()
      send(socket.parent_pid, {__MODULE__, {:connected, ref, self(), %{}}})

      socket =
        receive do
          {^ref, %__MODULE__{} = player} ->
            IO.inspect(player, label: "PLAYER MOUNT")
            socket |> assign(player: player)
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
    {:noreply,
     socket
     |> push_event("webrtc_signaling", Jason.encode!(message))}
  end

  @impl true
  def handle_event("webrtc_signaling", message, socket) do
    SignalingChannel.signal(
      socket.assigns.signaling_channel,
      Jason.decode!(message)
    )

    {:noreply, socket}
  end
end
