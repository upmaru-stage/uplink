defmodule Uplink.Packages.DistributionTest do
  use ExUnit.Case
  use Plug.Test

  alias Uplink.{
    Clients,
    Members,
    Packages,
    Cache
  }

  alias Clients.LXD

  @app_slug "upmaru/something-1640927800"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Uplink.Repo)

    bypass = Bypass.open()

    Cache.put(:self, %{
      "credential" => %{
        "endpoint" => "http://localhost:#{bypass.port}"
      }
    })

    Cache.put({:networks, "managed"}, %LXD.Network{
      managed: true,
      name: "lxdfan0"
    })

    deployment_payload = %{
      "actor" => %{
        "identifier" => "zacksiri",
        "provider" => "instellar",
        "id" => 1
      },
      "installation_id" => 1,
      "deployment" => %{
        "hash" => "some-hash",
        "stack" => "alpine/3.14",
        "channel" => "develop",
        "archive_url" =>
          "archives/7a363fba-8ca7-4ea4-8e84-f3785ac97102/packages.zip",
        "metadata" => %{
          "id" => 1,
          "slug" => "uplink-web",
          "service_port" => 4000,
          "exposed_port" => 49152,
          "variables" => [
            %{"key" => "SOMETHING", "value" => "blah"}
          ],
          "channel" => %{
            "slug" => "develop",
            "package" => %{
              "slug" => "something-1640927800",
              "credential" => %{
                "public_key" => "public_key"
              },
              "organization" => %{
                "slug" => "upmaru"
              }
            }
          },
          "instances" => [
            %{
              "id" => 1,
              "slug" => "something-1",
              "node" => %{
                "slug" => "some-node"
              }
            }
          ]
        }
      }
    }

    {:ok, actor} =
      Members.get_or_create_actor(%{
        "identifier" => "zacksiri",
        "provider" => "instellar",
        "id" => "1"
      })

    app = Packages.get_or_create_app(@app_slug)

    deployment_params = Map.get(deployment_payload, "deployment")

    {:ok, deployment} =
      Packages.get_or_create_deployment(app, deployment_params)

    {:ok, _installation} =
      Packages.create_install(deployment, %{
        "installation_id" => 1,
        "deployment" => deployment_params
      })

    {:ok, %{resource: preparing_deployment}} =
      Packages.transition_deployment_with(deployment, actor, "prepare")

    leases_list = File.read!("test/fixtures/lxd/networks/leases.json")

    allowed_ips =
      leases_list
      |> Jason.decode!()
      |> Map.get("metadata")
      |> Enum.map(fn data ->
        data["address"]
      end)

    %LXD.Network{} = network = LXD.managed_network()

    Uplink.Cache.delete({:leases, "uplink"})

    Bypass.expect(
      bypass,
      "GET",
      "/1.0/networks/#{network.name}/leases",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, leases_list)
      end
    )

    [first, second, third, fourth] =
      List.first(allowed_ips)
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    address = {first, second, third, fourth}

    {:ok,
     actor: actor,
     deployment: preparing_deployment,
     bypass: bypass,
     allowed_ips: allowed_ips,
     address: address}
  end

  describe "matching archive node" do
    setup %{deployment: deployment, actor: actor} do
      {:ok, archive} =
        Packages.create_archive(deployment, %{
          node: "nonode@nohost",
          locations: [
            "#{deployment.channel}/#{@app_slug}/x86_64/APKINDEX.tar.gz"
          ]
        })

      {:ok, %{resource: completed_deployment}} =
        Packages.transition_deployment_with(deployment, actor, "complete")

      {:ok, archive: archive, deployment: completed_deployment}
    end

    test "successfully fetch file", %{
      bypass: bypass,
      deployment: deployment,
      address: address
    } do
      project_found = File.read!("test/fixtures/lxd/projects/show.json")

      Bypass.expect(
        bypass,
        "GET",
        "/1.0/projects/default",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(200, project_found)
        end
      )

      conn =
        conn(
          :get,
          "/distribution/#{deployment.channel}/#{@app_slug}/x86_64/APKINDEX.tar.gz"
        )
        |> Map.put(:remote_ip, address)
        |> Uplink.Internal.call([])

      assert conn.status == 200
    end
  end

  describe "not matching arvhive node" do
    setup %{deployment: deployment, actor: actor} do
      node_host = "somethingelse"

      {:ok, archive} =
        Packages.create_archive(deployment, %{
          node: "nonode@#{node_host}",
          locations: [
            "#{deployment.channel}/#{@app_slug}/x86_64/APKINDEX.tar.gz"
          ]
        })

      {:ok, %{resource: completed_deployment}} =
        Packages.transition_deployment_with(deployment, actor, "complete")

      {:ok,
       archive: archive, deployment: completed_deployment, node_host: node_host}
    end

    test "successfully redirect", %{
      bypass: bypass,
      deployment: deployment,
      address: address,
      node_host: node_host
    } do
      project_found = File.read!("test/fixtures/lxd/projects/show.json")

      Bypass.expect(
        bypass,
        "GET",
        "/1.0/projects/default",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(200, project_found)
        end
      )

      path =
        "/distribution/#{deployment.channel}/#{@app_slug}/x86_64/APKINDEX.tar.gz"

      conn =
        conn(:get, path)
        |> Map.put(:remote_ip, address)
        |> Uplink.Internal.call([])

      assert [location] = get_resp_header(conn, "location")

      assert conn.status == 302

      assert location =~ node_host
      assert location =~ path
      assert location =~ "4080"
    end
  end
end
