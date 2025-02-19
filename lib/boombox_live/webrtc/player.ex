defmodule Membrane.WebRTC.Live.Player do
  @moduledoc ~S'''
  LiveView for playing audio and video get via WebRTC from `Membrane.WebRTC.Sink`.

  It:
  * renders a single HTMLVideoElement.
  * creates WebRTC PeerConnection on the browser side.
  * forwards signaling messages between the browser and `Membrane.WebRTC.Sink` via `Membrane.WebRTC.SignalingChannel`.
  * attaches audio and video from the Elixir to the HTMLVideoElement.

  ## JavaScript Hook

  Player live view requires JavaScript hook to be registered under `Player` name.
  The hook can be created using `createPlayerHook` function.
  For example:

  ```javascript
  import { createPlayerHook } from "membrane_webrtc_live";
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
  defmodule StreamerWeb.StreamViewerLive do
    use StreamerWeb, :live_view

    alias Membrane.WebRTC.Live.Player

    @impl true
    def render(assigns) do
    ~H"""
    <Player.live_render socket={@socket} player={@player} />
    """
    end

    @impl true
    def mount(_params, _session, socket) do
      signaling = Membrane.WebRTC.SignalingChannel.new()
      {:ok, _supervisor, _pipelne} = Membrane.Pipeline.start_link(MyPipeline, signaling: signaling)

      socket = Player.attach(socket, id: "player", signaling: signaling)
      socket = assign(socket, :player, Player.get_attached(socket, "player"))

      {:ok, socket}
    end
  end
  ```
  '''
  use Phoenix.LiveView

  alias Membrane.WebRTC.SignalingChannel

  require Logger

  @type t() :: struct()

  defstruct [:video?, :audio?, :ice_servers, id: nil, signaling_channel: nil]

  attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

  attr(:player, __MODULE__,
    required: true,
    doc: """
    #{inspect(__MODULE__)} struct. It is used to pass player id to the newly created live view via live view session.
    This data is then used to do a handshake between parent live view and child live view during which child live view
    receives the whole #{inspect(__MODULE__)} struct.
    """
  )

  attr(:class, :string, default: nil, doc: "CSS/Tailwind classes for styling")

  @doc """
  Helper function for rendering Player live view.
  """
  def live_render(assigns) do
    ~H"""
    <%= live_render(@socket, __MODULE__, id: "#{@player.id}-lv", session: %{"class" => @class, "id" => @player.id}) %>
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

    all_players =
      socket.assigns
      |> Map.get(__MODULE__, %{})
      |> Map.put(player.id, player)

    socket
    |> assign(__MODULE__, all_players)
    |> detach_hook(:player_handshake, :handle_info)
    |> attach_hook(:player_handshake, :handle_info, &handshake/2)
  end

  def get_attached(socket, id), do: socket.assigns[__MODULE__][id]

  defp handshake({__MODULE__, {:connected, id, child_pid, _meta}}, socket) do
    # child live view is connected, send it player struct
    player =
      socket.assigns
      |> Map.fetch!(__MODULE__)
      |> Map.fetch!(id)

    send(child_pid, player)

    {:halt, socket}
  end

  defp handshake(_msg, socket) do
    {:cont, socket}
  end

  ## CALLBACKS

  @impl true
  def render(%{player: nil} = assigns) do
    ~H"""
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <video id={@player.id} phx-hook="Player" class={@class} controls autoplay muted></video>
    """
  end

  @impl true
  def mount(_params, %{"class" => class, "id" => id}, socket) do
    socket = assign(socket, class: class, player: nil)

    if connected?(socket) do
      send(socket.parent_pid, {__MODULE__, {:connected, id, self(), %{}}})

      socket =
        receive do
          %__MODULE__{} = player ->
            player.signaling_channel
            |> SignalingChannel.register_peer(message_format: :json_data)

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
    Logger.info("""
    #{log_prefix(socket.assigns.player.id)} Sent WebRTC signaling message: #{inspect(message, pretty: true)}
    """)

    {:noreply,
     socket
     |> push_event("webrtc_signaling-#{socket.assigns.player.id}", message)}
  end

  @impl true
  def handle_event("webrtc_signaling", message, socket) do
    message = Jason.decode!(message)

    Logger.info("""
    #{log_prefix(socket.assigns.player.id)} Received WebRTC signaling message: #{inspect(message, pretty: true)}
    """)

    if message["data"] do
      SignalingChannel.signal(
        socket.assigns.player.signaling_channel,
        message
      )
    end

    {:noreply, socket}
  end

  defp log_prefix(id), do: [module: __MODULE__, id: id] |> inspect()
end
