defmodule Uplink.Monitors.Instance do
  alias Uplink.Clients.LXD

  defstruct [:name, :data]

  def metrics do
    LXD.list_instances(recursion: 2)

    # members
    # |> Enum.map(fn member ->
    #   Lexdee.show_resources(client, member.server_name)
    #   |> case do
    #     {:ok, %{body: metric}} ->
    #       %__MODULE__{node: member.server_name, data: metric}

    #     {:error, error} ->
    #       error
    #   end
    # end)
  end
end
