defmodule Uplink.Clients.Caddy.Config.BuilderTest do
  use ExUnit.Case

  import Uplink.Scenarios.Deployment

  setup [:setup_endpoints, :setup_base]

  setup do
    Application.put_env(:uplink, Uplink.Clients.Caddy,
      storage: %{
        prefix: "uplink"
      }
    )

    :ok
  end

  test "generate caddy config", %{bypass: bypass} do
    Uplink.Cache.delete({:proxies, 1})

    System.put_env("CLOUDFLARE_DNS_TOKEN", "something")

    Bypass.expect_once(
      bypass,
      "GET",
      "/uplink/self/routers/1/proxies",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => [
              %{
                "attributes" => %{
                  "id" => 1,
                  "router_id" => 1,
                  "hosts" => ["opsmaru.com", "www.opsmaru.com"],
                  "paths" => ["/how-to*"],
                  "tls" => true,
                  "target" => "proxy.webflow.com",
                  "port" => 80
                }
              }
            ]
          })
        )
      end
    )

    assert %{admin: admin, apps: apps, storage: storage} =
             Uplink.Clients.Caddy.build_new_config()

    assert %{http: %{servers: %{"uplink" => server}}, tls: tls} = apps

    assert %{automation: %{policies: [policy]}} = tls

    assert %{issuers: [issuer]} = policy

    assert %{"challenges" => challenges} = issuer

    assert %{"dns" => dns, "tls-alpn" => _tls_alpn, "http" => _http} =
             challenges

    assert %{
             "provider" => %{"api_token" => "something", "name" => "cloudflare"}
           } = dns

    assert %{routes: [first_route, second_route, third_route]} = server

    assert %{handle: [handle], match: [match]} = first_route
    assert %{handle: [second_handle], match: [second_match]} = second_route
    assert %{handle: [third_handle], match: [third_match]} = third_route

    assert match.path == ["/configure*"]

    assert third_match.path == ["*"]

    assert second_match.path == ["/how-to*"]

    assert "grpc.something.com" in third_match.host

    [third_upstream] = third_handle.upstreams

    assert third_upstream.dial =~ "6000"

    assert %{handler: "reverse_proxy"} = handle
    assert %{host: _hosts} = match

    [second_upstream] = second_handle.upstreams

    assert %{protocol: "http", tls: %{}} = second_handle.transport

    assert second_upstream.dial == "proxy.webflow.com:80"

    assert %{identity: identity} = admin
    assert %{identifiers: ["127.0.0.1"]} = identity

    assert %{module: "s3"} = storage
  end
end
