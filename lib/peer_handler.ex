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

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"}
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
      out_video_tracks: %{},
      out_audio_tracks: %{},
      in_video_track_id: nil,
      in_audio_track_id: nil
    }

    SFU.RoomServer.add_peer(:room_server, self(), uuid)

    {:ok, state}
  end

  @impl true
  def handle_in({msg, [opcode: :text]}, state) do
    msg
    |> Jason.decode!()
    |> handle_ws_msg(state)
  end

  @impl true
  def handle_info({:add_outgoing_tracks, uuid}, state) do
    IO.puts("Adding outgoing tracks for #{uuid}")

    video_track = MediaStreamTrack.new(:video)
    audio_track = MediaStreamTrack.new(:audio)

    {:ok, _sender} = PeerConnection.add_track(state.peer_connection, video_track)
    {:ok, _sender} = PeerConnection.add_track(state.peer_connection, audio_track)

    video_tracks =
      state.out_video_tracks
      |> Map.update(uuid, [video_track], fn tracks -> [video_track | tracks] end)

    audio_tracks =
      state.out_audio_tracks
      |> Map.update(uuid, [audio_track], fn tracks -> [audio_track | tracks] end)

    new_state = %{
      state
      | out_video_tracks: video_tracks,
        out_audio_tracks: audio_tracks
    }

    {:ok, new_state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, state) do
    handle_webrtc_msg(msg, state)
  end

  def handle_info({:distribute_video_packet, uuid, packet}, state) do
    for track <- Map.get(state.out_video_tracks, uuid, []) do
      PeerConnection.send_rtp(state.peer_connection, track.id, packet)
    end

    {:ok, state}
  end

  def handle_info({:distribute_audio_packet, uuid, packet}, state) do
    for track <- Map.get(state.out_audio_tracks, uuid, []) do
      PeerConnection.send_rtp(state.peer_connection, track.id, packet)
    end

    {:ok, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("WebSocket connection was terminated, reason: #{inspect(reason)}")
  end

  defp handle_ws_msg(%{"type" => "answer", "data" => data}, state) do
    Logger.info("Received SDP answer: #{inspect(data)}")

    answer = SessionDescription.from_json(data)
    :ok = PeerConnection.set_remote_description(state.peer_connection, answer)

    {:ok, state}
  end

  defp handle_ws_msg(%{"type" => "offer", "data" => data}, state) do
    Logger.info("Received SDP offer: #{inspect(data)}")

    # before we answer, we will:
    # 1. loop through every other peer and add a local track to them. We will write this peers packets to those tracks.
    # 2. loop through every other peer, add a local track to this peer. We will write the other peers outgoing packets onto this one.

    for %{ws_pid: ws_pid, peer_uuid: peer_uuid} <- SFU.RoomServer.get_peers(:room_server),
        ws_pid != self() do
      send(ws_pid, {:add_outgoing_tracks, state.uuid})
    end

    state =
      for %{ws_pid: ws_pid, peer_uuid: peer_uuid} <- SFU.RoomServer.get_peers(:room_server),
          ws_pid != self(),
          reduce: state do
        state ->
          add_local_tracks(state, state.uuid)
      end

    offer = SessionDescription.from_json(data)
    :ok = PeerConnection.set_remote_description(state.peer_connection, offer)

    {:ok, answer} = PeerConnection.create_answer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, answer)

    answer_json = SessionDescription.to_json(answer)

    msg =
      %{"type" => "answer", "data" => answer_json}
      |> Jason.encode!()

    Logger.info("Sent SDP answer: #{inspect(answer_json)}")

    {:push, {:text, msg}, state}
  end

  defp handle_ws_msg(%{"type" => "ice", "data" => data}, state) do
    Logger.info("Received ICE candidate: #{inspect(data)}")

    candidate = ICECandidate.from_json(data)
    :ok = PeerConnection.add_ice_candidate(state.peer_connection, candidate)
    {:ok, state}
  end

  defp handle_webrtc_msg({:ice_candidate, candidate}, state) do
    candidate_json = ICECandidate.to_json(candidate)

    msg =
      %{"type" => "ice", "data" => candidate_json}
      |> Jason.encode!()

    Logger.info("Sent ICE candidate: #{inspect(candidate_json)}")

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

    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, packet}, %{in_audio_track_id: id} = state) do
    SFU.RoomServer.receive_audio_packet(:room_server, {self(), state.uuid, packet})
    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, packet}, %{in_video_track_id: id} = state) do
    SFU.RoomServer.receive_video_packet(:room_server, {self(), state.uuid, packet})
    {:ok, state}
  end

  defp handle_webrtc_msg(:negotiation_needed, state) do
    IO.puts("firing renegotiation for #{inspect(state.uuid)}")

    {:ok, offer} = PeerConnection.create_offer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, offer)

    offer_json = SessionDescription.to_json(offer)

    msg =
      %{"type" => "offer", "data" => offer_json}
      |> Jason.encode!()

    Logger.info("Sent SDP offer: #{inspect(offer_json)}")

    {:push, {:text, msg}, state}
  end

  defp handle_webrtc_msg(_msg, state), do: {:ok, state}

  defp add_local_tracks(state, uuid) do
    video_track = MediaStreamTrack.new(:video)
    audio_track = MediaStreamTrack.new(:audio)

    {:ok, _sender} = PeerConnection.add_track(state.peer_connection, video_track)
    {:ok, _sender} = PeerConnection.add_track(state.peer_connection, audio_track)

    video_tracks =
      state.out_video_tracks
      |> Map.update(uuid, [video_track], fn tracks -> [video_track | tracks] end)

    audio_tracks =
      state.out_audio_tracks
      |> Map.update(uuid, [audio_track], fn tracks -> [audio_track | tracks] end)

    new_state = %{
      state
      | out_video_tracks: video_tracks,
        out_audio_tracks: audio_tracks
    }

    new_state
  end
end
