defmodule Uplink.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    oban_config = Application.fetch_env!(:uplink, Oban)
    router_config = Application.get_env(:uplink, Uplink.Router)

    children = [
      {Uplink.Cache, []},
      {Uplink.Repo, []},
      {Oban, oban_config},
      {Plug.Cowboy,
       scheme: :http,
       plug: Uplink.Router,
       port: Keyword.get(router_config, :port)}
    ]

    opts = [strategy: :one_for_one, name: Uplink.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
