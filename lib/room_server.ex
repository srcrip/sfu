defmodule SFU.Peer do
  defstruct [
    :ws_pid,
    :peer_uuid
  ]
end

defmodule SFU.RoomServer do
  use GenServer

  defstruct [
    :name,
    :peers
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: :room_server)
  end

  # todo: add registry
  # todo: add supervision and ability to have this not be a singleton
  def add_peer(pid, ws_pid, uuid) do
    new_peer = %SFU.Peer{ws_pid: ws_pid, peer_uuid: uuid}
    GenServer.cast(pid, {:add_peer, new_peer})
  end

  def get_peers(pid) do
    GenServer.call(pid, :get_peers)
  end

  def receive_video_packet(pid, {incoming_peer_pid, incoming_uuid, packet}) do
    GenServer.cast(pid, {:receive_video_packet, {incoming_peer_pid, incoming_uuid, packet}})
  end

  def receive_audio_packet(pid, {incoming_peer_pid, incoming_uuid, packet}) do
    GenServer.cast(pid, {:receive_audio_packet, {incoming_peer_pid, incoming_uuid, packet}})
  end

  @impl GenServer
  def init(_opts) do
    IO.puts("Starting room server...")
    state = %__MODULE__{name: "room1", peers: []}
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_peers, _from, state) do
    {:reply, state.peers, state}
  end

  @impl GenServer
  def handle_cast({:add_peer, peer}, state) do
    new_state = %{state | peers: [peer | state.peers]}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:receive_video_packet, {incoming_peer_pid, incoming_uuid, packet}}, state) do
    for %{ws_pid: ws_pid, peer_uuid: peer_uuid} <- state.peers, peer_uuid != incoming_peer_pid do
      send(ws_pid, {:distribute_video_packet, incoming_uuid, packet})
    end

    {:noreply, state}
  end

  def handle_cast({:receive_audio_packet, {incoming_peer_pid, incoming_uuid, packet}}, state) do
    for %{ws_pid: ws_pid, peer_uuid: peer_uuid} <- state.peers, peer_uuid != incoming_peer_pid do
      send(ws_pid, {:distribute_audio_packet, incoming_uuid, packet})
    end

    {:noreply, state}
  end
end
