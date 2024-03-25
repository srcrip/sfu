defmodule SFU.RemoteTrack do
  defstruct [:kind, :peer_pid, :peer_uuid, :in_track_id, :out_track]
end

defmodule SFU.PeerHandler do
  require Logger

  alias ExWebRTC.{
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    RTPCodecParameters,
    SessionDescription
  }

  @behaviour WebSock

  # just need host candidate for testing locally
  @ice_servers [
    # %{urls: "stun:stun.l.google.com:19302"}
  ]

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
  ]

  @audio_codecs [
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]

  @impl true
  def init(_) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: @ice_servers,
        video_codecs: @video_codecs,
        audio_codecs: @audio_codecs
      )

    uuid = UUID.uuid4()

    state = %{
      uuid: uuid,
      peer_connection: pc,
      connection_state: nil,
      out_video_tracks: %{},
      out_audio_tracks: %{},
      pending_track_edits: false,
      pending_answer: false,
      outgoing_video_tracks: [],
      outgoing_audio_tracks: [],
      in_video_track_id: nil,
      in_audio_track_id: nil
    }

    SFU.RoomServer.add_peer(:room_server, self(), pc, nil, nil, uuid)

    {:ok, state}
  end


  def handle_info({:add_other_tracks}, state) do
    state =
      for %{ws_pid: ws_pid, in_video_track_id: vid, peer_uuid: _peer_uuid} <- SFU.RoomServer.get_peers(:room_server),
        ws_pid != self(),
        reduce: state do
        state ->
          in_track_id = vid
          add_local_track(state, :video, state.uuid, in_track_id)
    end

    {:ok, state}
  end

  @impl true
  def handle_in({msg, [opcode: :text]}, state) do
    msg
    |> Jason.decode!()
    |> handle_ws_msg(state)
  end

  def handle_info({:add_local_track, kind, uuid, in_track_id}, state) do
    Logger.info("in the handle info for local track")
    {:ok, add_local_track(state, kind, uuid, in_track_id)}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, state) do
    handle_webrtc_msg(msg, state)
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("WebSocket connection was terminated, reason: #{inspect(reason)}")
  end

  defp handle_ws_msg(%{"type" => "answer", "data" => data}, state) do
    Logger.info("Received SDP answer for: #{state.uuid}")

    if state.in_video_track_id == nil do
      dbg "waiting for video track"
      Process.sleep(1000)
    end

    state = %{state | pending_answer: false}

    answer = SessionDescription.from_json(data)
    :ok = PeerConnection.set_remote_description(state.peer_connection, answer)

    {:ok, state}
  end

  defp handle_ws_msg(%{"type" => "offer", "data" => data}, state) do
    Logger.info("Received SDP offer for: #{state.uuid}")

    offer = SessionDescription.from_json(data)
    :ok = PeerConnection.set_remote_description(state.peer_connection, offer)

    {:ok, answer} = PeerConnection.create_answer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, answer)

    answer_json = SessionDescription.to_json(answer)

    msg =
      %{"type" => "answer", "data" => answer_json}
      |> Jason.encode!()

    Logger.info("Sent SDP answer for: #{state.uuid}")

    {:push, {:text, msg}, state}
  end

  defp handle_ws_msg(%{"type" => "ice", "data" => data}, state) do
    Logger.info("Received ICE candidate for: #{state.uuid}")

    candidate = ICECandidate.from_json(data)
    :ok = PeerConnection.add_ice_candidate(state.peer_connection, candidate)
    {:ok, state}
  end

  defp handle_webrtc_msg({:ice_candidate, candidate}, state) do
    candidate_json = ICECandidate.to_json(candidate)

    msg =
      %{"type" => "ice", "data" => candidate_json}
      |> Jason.encode!()

    Logger.info("Sent ICE candidate from: #{state.uuid}")

    {:push, {:text, msg}, state}
  end

  defp handle_webrtc_msg({:track, track}, state) do
    %MediaStreamTrack{kind: kind, id: id} = track

    Logger.info("Received incoming #{kind} (#{id}) for #{inspect(state.peer_connection)}")

    state =
      case kind do
        :video -> %{state | in_video_track_id: id}
        :audio -> %{state | in_audio_track_id: id}
      end

    SFU.RoomServer.add_track_to_peer(:room_server, state.peer_connection, kind, id)

    # Loop through every other peer, and add a track to them to write this peers packets to.
    for %{ws_pid: ws_pid, in_video_track_id: vid, in_audio_track_id: aid, peer_uuid: peer_uuid} <- SFU.RoomServer.get_peers(:room_server),
      ws_pid != self() do

      # Process.sleep(500)
      send(ws_pid, {:add_local_track, kind, state.uuid, id})
    end

    # # Loop through every other peer, and add a track to thie peer to write the other peers packets to.
    Process.send_after(self(), {:add_other_tracks}, 500)

    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, packet}, %{in_audio_track_id: id} = state) do
    # SFU.RoomServer.receive_audio_packet(:room_server, {self(), state.uuid, packet})
    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, packet}, %{in_video_track_id: id} = state) do
    for %{ws_pid: ws_pid, pc_pid: pc, outgoing_video_tracks: ts, peer_uuid: peer_uuid} <- SFU.RoomServer.get_peers(:room_server),
      ts != nil,
      ws_pid != self(),
      t <- ts,
      t.in_track_id == id do
      PeerConnection.send_rtp(pc, t.out_track.id, packet)
    end

    {:ok, state}
  end

  def handle_info({:signal}, state) do
    msg = do_offer(state)

    {:push, {:text, msg}, state}
  end

  defp handle_webrtc_msg({:connection_state_change, connection_state}, state) do
    Logger.info("Connection state changed to #{connection_state} for: #{state.uuid}")

    state = %{state | connection_state: connection_state}

    case connection_state do
      :connected ->
        # once connected, trigger the offer

        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  defp handle_webrtc_msg(:negotiation_needed, state) do
    # {:ok, state}
    # dbg state
    if state.pending_answer do
      IO.puts("👻 pending offer")
      IO.puts("👻 pending offer")
      IO.puts("👻 pending offer")
      IO.puts("👻 pending offer")
      {:ok, state}
    else
      IO.puts("firing renegotiation for #{inspect(state.uuid)}")


      case state.connection_state do
        :connected ->
          msg = do_offer(state)

          {:push, {:text, msg}, state}

        _ ->
          Process.send_after(self(), {:ex_webrtc, self(), :negotiation_needed}, 50)

          {:ok, state}
      end

    end
  end

  defp handle_webrtc_msg(_msg, state), do: {:ok, state}

  defp add_local_track(state, kind, uuid, in_track_id) do
    IO.puts("👻 Adding local track for #{inspect(state.uuid)}")

    video_track = MediaStreamTrack.new(kind)

    {:ok, _sender} = PeerConnection.add_track(state.peer_connection, video_track)

    outgoing_track = %SFU.RemoteTrack{kind: kind, peer_pid: state.peer_connection, peer_uuid: uuid, in_track_id: in_track_id, out_track: video_track}

    case kind do
      :video ->
        tracks = [outgoing_track | state.outgoing_video_tracks]
        SFU.RoomServer.set_outgoing_track(:room_server, state.peer_connection, tracks)
        %{state | outgoing_video_tracks: tracks}

      :audio ->
        tracks = [outgoing_track | state.outgoing_audio_tracks]
        %{state | outgoing_audio_tracks: tracks}
    end
  end

  defp do_offer(state) do
    {:ok, offer} = PeerConnection.create_offer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, offer)

    offer_json = SessionDescription.to_json(offer)

    msg =
      %{"type" => "offer", "data" => offer_json}
      |> Jason.encode!()

    Logger.info("Sent SDP offer from: #{state.uuid}")

    msg
  end
end
