defmodule SFU.Peer do
  defstruct [
    :ws_pid,
    :pc_pid,
    :in_video_track_id,
    :in_audio_track_id,
    :outgoing_video_tracks,
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
  def add_peer(pid, ws_pid, pc_pid, in_video_track_id, in_audio_track_id, uuid) do
    new_peer = %SFU.Peer{ws_pid: ws_pid, pc_pid: pc_pid,
      in_video_track_id: in_video_track_id, in_audio_track_id: in_audio_track_id,
      peer_uuid: uuid}
    GenServer.cast(pid, {:add_peer, new_peer})
  end

  def add_track_to_peer(pid, pc_pid, kind, in_track_id) do
    GenServer.cast(pid, {:add_track_to_peer, pc_pid, kind, in_track_id})
  end

  def set_outgoing_track(pid, pc_pid, tracks) do
    GenServer.cast(pid, {:set_outgoing_tracks, pc_pid, tracks})
  end

  def get_peers(pid) do
    GenServer.call(pid, :get_peers)
  end

  def signal_everybody(pid) do
    for %{ws_pid: ws_pid} <- get_peers(pid) do
      dbg "sending signal event to #{inspect ws_pid}"
      send(ws_pid, {:signal})
      dbg "sleeping"
      Process.sleep(1000)
    end
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

  #todo: this does video only
  def handle_cast({:set_outgoing_tracks, pc_pid, tracks}, state) do
    peer = Enum.find(state.peers, fn peer -> peer.pc_pid == pc_pid end)
    peer = %SFU.Peer{peer | outgoing_video_tracks: tracks}

    peers = state.peers
    |> Enum.map(fn p -> if p.pc_pid == pc_pid, do: peer, else: p end)

    new_state = %{state | peers: peers}

    {:noreply, new_state}
  end

  def handle_cast({:add_track_to_peer, pc_pid, kind, in_track_id}, state) do
    peer = Enum.find(state.peers, fn peer -> peer.pc_pid == pc_pid end)
    case kind do
      :video ->
        peer = %SFU.Peer{peer | in_video_track_id: in_track_id}

        peers = state.peers
        |> Enum.map(fn p -> if p.pc_pid == pc_pid, do: peer, else: p end)

        new_state = %{state | peers: peers}

        {:noreply, new_state}

      :audio ->
        # peer = %SFU.Peer{peer | in_audio_track_id: in_track_id}
        {:noreply, state}
    end
  end
end
