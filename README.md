# SFU

Work in progress example of a Selective Forwarding Unit in Elixir, using `ex_webrtc`

## Development

Clone the repo, install dependencies with `mix deps.get`, and then run it with:


```sh
mix run --no-halt
```

Alternatively you can run it through `iex -S mix` if you want to interact with it at the same time.

Once it's running, open two tabs in your web browser, both at: `http://localhost:7001/index.html`.

And you should see audio/video flowing!

## Discussion

This is still at a very rough, example stage. There's a few pieces to clean up from here:

1. There is currently the `PeerHandler` which connects to each signalling websocket for each peer, and one `RoomServer`
2. Right now the `PeerHandler` kind of does most of the work, but the idea is that it would be modified to have the
   `RoomServer` do more of this (while remaining cognizant of bottlenecking that one genserver)
3. The `RoomServer` currently does not use registry, which is a todo
4. The `RoomServer` is currently a singleton, so it needs to be able to be dynamically supervised and grow with new
   signalled connections
5. There needs to be additional endpoints in the signalling system to make rooms and go beyond the 1 room two
   participants test
6. it has currently only been tested with 2 participants
7. there is as-yet little error handling and failure state recovery
