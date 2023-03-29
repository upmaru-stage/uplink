defmodule Uplink.Clients.LXD do
  alias Uplink.Cache
  alias Uplink.Clients.Instellar

  alias Uplink.Clients.LXD

  defdelegate list_cluster_members(),
    to: __MODULE__.Cluster.Manager,
    as: :list_members

  defdelegate list_profiles(),
    to: __MODULE__.Profile.Manager,
    as: :list

  defdelegate get_profile(name),
    to: __MODULE__.Profile.Manager,
    as: :get

  defdelegate list_instances(project),
    to: __MODULE__.Instance.Manager,
    as: :list

  defdelegate managed_network(),
    to: __MODULE__.Network.Manager,
    as: :managed

  defdelegate network_leases(project),
    to: __MODULE__.Network.Manager,
    as: :leases

  def uplink_leases do
    Cache.get({:leases, "uplink"}) ||
      (
        config = Application.get_env(:uplink, Uplink.Data) || []
        uplink_project = Keyword.get(config, :project, "default")

        case LXD.network_leases(uplink_project) do
          leases when is_list(leases) ->
            uplink_addresses =
              Enum.map(leases, fn lease ->
                lease.address
              end)

            Cache.put({:leases, "uplink"}, uplink_addresses,
              ttl: :timer.hours(3)
            )

            uplink_addresses

          {:error, error} ->
            {:error, error}
        end
      )
  end

  def client do
    %{
      "credential" => credential
    } = Instellar.get_self()

    Lexdee.create_client(
      credential["endpoint"],
      credential["certificate"],
      credential["private_key"]
    )
  end
end
