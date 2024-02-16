defmodule SFU.Application do
  @moduledoc """
  A simple, Elixir-based Selective Forwarding Unit for video applications.
  """

  use Application

  require Logger

  @scheme :http
  @port 7001

  @doc "Start the application."
  @impl true
  def start(_type, _args) do
    Logger.configure(level: :info)

    children = [
      {Bandit, plug: SFU.Router, scheme: @scheme, port: @port},
      SFU.RoomServer
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
