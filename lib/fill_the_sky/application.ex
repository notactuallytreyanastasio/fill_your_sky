defmodule FillTheSky.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FillTheSkyWeb.Telemetry,
      FillTheSky.Repo,
      {DNSCluster, query: Application.get_env(:fill_the_sky, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FillTheSky.PubSub},
      FillTheSky.Bluesky.RateLimiter,
      {DynamicSupervisor, name: FillTheSky.PipelineSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      FillTheSkyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FillTheSky.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FillTheSkyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
