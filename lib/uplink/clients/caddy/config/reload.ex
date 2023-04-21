defmodule Uplink.Clients.Caddy.Config.Reload do
  use Oban.Worker, queue: :caddy, max_attempts: 1

  @moduledoc """
  Reloads configuration for caddy on all nodes
  """

  alias Uplink.Repo
  alias Uplink.Cache

  alias Uplink.Members

  alias Uplink.Packages
  alias Uplink.Packages.Install

  alias Uplink.Clients.Caddy

  import Ecto.Query, only: [preload: 2]

  require Logger

  @task_supervisor Application.compile_env(:uplink, :task_supervisor) ||
                     Task.Supervisor

  def perform(%Oban.Job{args: %{"install_id" => install_id} = params}) do
    %Install{} =
      install =
      Install
      |> preload([:deployment])
      |> Repo.get(install_id)

    install
    |> Packages.install_cache_key()
    |> Cache.delete()

    [Node.self() | Node.list()]
    |> Enum.each(fn node ->
      Logger.info("[Caddy.Config.Reload] running on #{node}...")

      @task_supervisor.async_nolink({Uplink.TaskSupervisor, node}, fn ->
        Caddy.build_new_config()
        |> Caddy.load_config()
      end)
    end)

    maybe_mark_install_complete(install, params)

    :ok
  end

  defp maybe_mark_install_complete(
         %Install{current_state: "refreshing"} = install,
         params
       ) do
    actor_id = Map.get(params, "actor_id")

    actor =
      if actor_id do
        Repo.get(Members.Actor, actor_id)
      else
        Members.get_bot!()
      end

    Packages.transition_install_with(install, actor, "complete")
  end

  defp maybe_mark_install_complete(_install, _params), do: :ok
end