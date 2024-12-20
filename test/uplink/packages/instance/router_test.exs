defmodule Uplink.Packages.Instance.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @app_slug "upmaru/something-1640927800"

  alias Uplink.{
    Members,
    Packages
  }

  alias Packages.Instance.Router

  @opts Router.init([])

  @valid_body Jason.encode!(%{
                "actor" => %{
                  "provider" => "instellar",
                  "identifier" => "zacksiri",
                  "id" => "1"
                },
                "installation_id" => 1,
                "deployment" => %{
                  "hash" => "some-hash"
                },
                "instance" => %{
                  "slug" => "some-instane-1",
                  "node" => %{
                    "slug" => "some-node-1"
                  }
                }
              })

  @deployment_params %{
    "hash" => "some-hash",
    "archive_url" => "http://localhost:4000/archives/packages.zip",
    "stack" => "alpine/3.14",
    "channel" => "develop",
    "metadata" => %{
      "id" => 1,
      "slug" => "uplink-web",
      "service_port" => 4000,
      "exposed_port" => 49152,
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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Uplink.Repo)

    {:ok, actor} =
      Members.get_or_create_actor(%{
        "identifier" => "zacksiri",
        "provider" => "instellar",
        "id" => "1"
      })

    app = Packages.get_or_create_app(@app_slug)

    {:ok, deployment} =
      Packages.get_or_create_deployment(app, @deployment_params)

    {:ok, %{resource: deployment}} =
      Packages.transition_deployment_with(deployment, actor, "prepare")

    {:ok, _transition} =
      Packages.transition_deployment_with(deployment, actor, "complete")

    {:ok, _install} =
      Packages.create_install(deployment, %{
        "installation_id" => 1,
        "deployment" => @deployment_params
      })

    :ok
  end

  describe "successfully schedule bootstrap instance" do
    test "returns 201 for instance bootstrap" do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), @valid_body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/bootstrap", @valid_body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201

      assert %{"data" => %{"id" => _job_id}} = Jason.decode!(conn.resp_body)
    end

    test "returns 201 for instance cleanup" do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), @valid_body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/cleanup", @valid_body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201

      assert %{"data" => %{"id" => _job_id}} = Jason.decode!(conn.resp_body)
    end

    test "returns 201 for instance upgrade" do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), @valid_body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/upgrade", @valid_body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201

      assert %{"data" => %{"id" => _job_id}} = Jason.decode!(conn.resp_body)
    end

    test "return unauthorized when request sent without signature" do
      conn =
        conn(:post, "/bootstrap", @valid_body)
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 401
    end
  end

  describe "fallback on install not found" do
    setup do
      valid_body =
        Jason.encode!(%{
          "actor" => %{
            "provider" => "instellar",
            "identifier" => "zacksiri",
            "id" => "1"
          },
          "installation_id" => 1,
          "deployment" => %{
            "hash" => "some-hash-not-existing"
          },
          "instance" => %{
            "slug" => "some-instane-1",
            "node" => %{
              "slug" => "some-node-1"
            }
          }
        })

      {:ok, body: valid_body}
    end

    test "returns 404 for instance bootstrap", %{body: body} do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/bootstrap", body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
    end

    test "returns 201 for instance cleanup", %{body: body} do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/cleanup", body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201

      assert %{"data" => %{"id" => _job_id}} = Jason.decode!(conn.resp_body)
    end

    test "returns 201 for instance restart", %{body: body} do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/restart", body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201

      assert %{"data" => %{"id" => _job_id}} = Jason.decode!(conn.resp_body)
    end

    test "returns 404 for instance upgrade", %{body: body} do
      signature =
        :crypto.mac(:hmac, :sha256, Uplink.Secret.get(), body)
        |> Base.encode16()
        |> String.downcase()

      conn =
        conn(:post, "/upgrade", body)
        |> put_req_header("x-uplink-signature-256", "sha256=#{signature}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end
end
