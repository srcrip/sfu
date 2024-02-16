defmodule SFU.MixProject do
  use Mix.Project

  def project do
    [
      app: :sfu,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SFU.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.15.0"},
      {:bandit, "~> 1.2.0"},
      {:websock_adapter, "~> 0.5.0"},
      {:jason, "~> 1.4.0"},
      # {:ex_webrtc, "~> 0.1.0"}
      {:ex_webrtc, path: "../ex_webrtc"}
    ]
  end
end
