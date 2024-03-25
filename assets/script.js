const pcConfig = { iceServers: [] }
// just need host candidate for testing locally
// const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] }
const mediaConstraints = { video: true, audio: false }
const address = 'ws://localhost:7001/ws'

let pendingAnswer = false

const ws = new WebSocket(address)
ws.onopen = (_) => start_connection(ws)
ws.onclose = (event) =>
  console.log('WebSocket connection was terminated:', event)

const start_connection = async (ws) => {
  const pc = new RTCPeerConnection(pcConfig)
  window.pc = pc

  pc.ontrack = (event) => {
    console.log('Received remote track:', event.track)

    if (event.track.kind === 'audio') {
      return
    }

    let el = document.createElement('video')
    el.srcObject = event.streams[0]
    el.autoplay = true
    el.controls = true
    document.getElementById('remoteVideos').appendChild(el)

    event.track.onmute = (_event) => {
      el.play()
    }

    event.streams[0].onremovetrack = (_event) => {
      if (el.parentNode) {
        el.parentNode.removeChild(el)
      }
    }
  }
  pc.onicecandidate = (event) => {
    if (event.candidate === null) return

    console.log('Sent ICE candidate:', event.candidate)
    ws.send(JSON.stringify({ type: 'ice', data: event.candidate }))
  }
  pc.onnegotiationneeded = async (_) => {
    console.log('Negotiation needed: unsure if need to fire from here? it kinda breaks things if i do...')
    // if (!pendingAnswer) {
    // const offer = await pc.createOffer()
    // await pc.setLocalDescription(offer)
    // console.log('Sent SDP offer:', offer)
    // ws.send(JSON.stringify({ type: 'offer', data: offer }))
    // }
  }

  const localVideo = document.getElementById('localVideo')

  const localStream =
    await navigator.mediaDevices.getUserMedia(mediaConstraints)

  for (const track of localStream.getTracks()) {
    pc.addTrack(track, localStream)
  }

  localVideo.srcObject = localStream

  ws.onmessage = async (event) => {
    const { type, data } = JSON.parse(event.data)

    switch (type) {
      case 'offer':
        console.log('Received SDP offer:', data)
        await pc.setRemoteDescription(data)

        const answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)

        console.log('Sent SDP answer:', answer)
        ws.send(JSON.stringify({ type: 'answer', data: answer }))

        break

      case 'answer':
        pendingAnswer = false
        console.log('Received SDP answer:', data)
        await pc.setRemoteDescription(data)
        break
      case 'ice':
        console.log('Recieved ICE candidate:', data)
        await pc.addIceCandidate(data)
    }
  }

  pendingAnswer = true
  const offer = await pc.createOffer()
  await pc.setLocalDescription(offer)
  console.log('Sent SDP offer:', offer)
  ws.send(JSON.stringify({ type: 'offer', data: offer }))
}
