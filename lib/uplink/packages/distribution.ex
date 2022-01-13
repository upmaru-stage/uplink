defmodule Uplink.Packages.Distribution do
  use Plug.Builder
  plug Plug.Logger
  
  alias Uplink.Clients.LXD

  plug :validate

  plug Plug.Static,
    at: "/",
    from: "tmp/deployments"

  plug :respond

  defp validate(conn, _opts) do
    case LXD.network_leases() do
      leases when is_list(leases) ->
        ip_addresses = 
          Enum.map(leases, fn lease -> 
            lease.address
          end)
          
        detected_ip_address =
          conn.remote_ip
          |> :inet.ntoa()
          |> to_string()
          
        if detected_ip_address in ip_addresses do
          serve_static_or_proxy(conn)
        else
          conn
          |> send_resp(:not_allowed, "")
          |> halt()
        end
      {:error, _error} ->
        halt(conn)
    end
  end
  
  defp serve_static_or_proxy(conn) do
    
  end

  defp respond(conn, _opts),
    do: send_resp(conn)
end
