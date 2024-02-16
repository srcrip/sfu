defmodule SFU.RoomServer do
  use GenServer

  # peers: start as list of pids but add struct later
  defstruct [
    :name,
    :peers
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: :room_server)
  end

  # todo: add registry
  def add_peer(pid, peer) do
    GenServer.cast(pid, {:add_peer, peer})
  end

  def receive_video_packet(pid, {incoming_peer_pid, track_id, packet}) do
    GenServer.cast(pid, {:receive_video_packet, {incoming_peer_pid, track_id, packet}})
  end

  def receive_audio_packet(pid, {incoming_peer_pid, track_id, packet}) do
    GenServer.cast(pid, {:receive_audio_packet, {incoming_peer_pid, track_id, packet}})
  end

  @impl GenServer
  def init(_opts) do
    IO.puts("Starting room server...")
    state = %__MODULE__{name: "room1", peers: []}
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add_peer, peer}, state) do
    new_state = %{state | peers: [peer | state.peers]}
    dbg("adding peer")
    dbg(new_state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:receive_video_packet, {incoming_peer_pid, track_id, packet}}, state) do
    # todo filter out not this pid
    # for peer <- state.peers, peer != incoming_peer_pid do
    for peer <- state.peers do
      # from = nil
      # msg = {:rtp, track_id, packet}
      # dbg("sending audio packet to peer: #{inspect(peer)}")
      send(peer, {:distribute_video_packet, track_id, packet})
    end

    {:noreply, state}
  end

  def handle_cast({:receive_audio_packet, {incoming_peer_pid, track_id, packet}}, state) do
    # for peer <- state.peers, peer != incoming_peer_pid do
    for peer <- state.peers do
      # from = nil
      # msg = {:rtp, track_id, packet}
      # dbg("sending video packet to peer: #{inspect(peer)}")
      send(peer, {:distribute_audio_packet, track_id, packet})
    end

    {:noreply, state}
  end
end
