defmodule Uplink.Clients.Caddy.Config.Builder do
  alias Uplink.{
    Clients,
    Packages,
    Repo
  }

  alias Clients.Caddy
  alias Caddy.Admin
  alias Caddy.Apps
  alias Caddy.Storage

  def new do
    install_states =
      Packages.Install.latest_by_installation_id(1)
      |> Repo.all()
      |> Repo.preload(deployment: [:app])
      |> Enum.map(&Packages.build_install_state/1)
      |> Enum.reject(fn %{metadata: metadata} ->
        metadata.hosts == [] || is_nil(metadata.main_port)
      end)

    %{"organization" => %{"storage" => storage_params}} =
      uplink = Uplink.Clients.Instellar.get_self()

    %{
      admin: admin(uplink),
      apps: apps(install_states),
      storage: Storage.parse(storage_params),
      logging: %{
        sink: %{
          writer: %{
            output: "stdout"
          }
        },
        logs: %{
          default: %{
            writer: %{
              output: "stdout"
            },
            encoder: %{
              format: "console"
            }
          }
        }
      }
    }
  end

  def admin(uplink) do
    identifiers =
      if instances = Map.get(uplink, "instances") do
        instances
        |> Enum.map(fn i ->
          i["node"]["public_ip"]
        end)
      else
        []
      end

    %{
      identity: %{
        identifiers: identifiers
      }
    }
    |> Admin.parse()
  end

  def apps(install_states) do
    %{
      http: %{
        servers: servers(install_states)
      }
    }
    |> Apps.parse()
  end

  def servers(installs) do
    %{
      "uplink" => %{
        listen: [":443"],
        routes:
          Enum.map(installs, &build_route/1)
          |> List.flatten()
      }
    }
  end

  defp build_route(
         %{install: %{deployment: %{app: _app}}, metadata: metadata} = _state
       ) do
    main_routing = Map.get(metadata.main_port, :routing)

    main_paths =
      if main_routing do
        main_routing.paths
      else
        ["*"]
      end

    main_group =
      if main_routing do
        "router_#{main_routing.router_id}"
      else
        "installation_#{metadata.id}"
      end

    main_route = %{
      group: main_group,
      match: [
        %{
          host: metadata.hosts,
          path: main_paths
        }
      ],
      handle: [
        %{
          handler: "reverse_proxy",
          load_balancing: %{
            selection_policy: %{
              policy: "ip_hash"
            }
          },
          health_checks: %{
            passive: %{
              fail_duration: "10s",
              max_fails: 3,
              unhealthy_request_count: 80,
              unhealthy_status: [500, 501, 502, 503, 504],
              unhealthy_latency: "30s"
            }
          },
          upstreams:
            Enum.map(metadata.instances, fn instance ->
              %{
                dial: "#{instance.slug}:#{metadata.main_port.target}",
                max_requests: 80
              }
            end)
        }
      ]
    }

    sub_routes =
      metadata.ports
      |> Enum.map(fn port ->
        hosts =
          Enum.map(metadata.hosts, fn host ->
            port.slug <> "." <> host
          end)

        routing = Map.get(port, :routing)

        paths =
          if routing do
            routing.paths
          else
            ["*"]
          end

        group =
          if routing,
            do: "router_#{routing.router_id}",
            else: "installation_#{metadata.id}"

        %{
          group: group,
          match: [
            %{
              host: hosts,
              path: paths
            }
          ],
          handle: [
            %{
              handler: "reverse_proxy",
              load_balancing: %{
                selection_policy: %{
                  policy: "ip_hash"
                }
              },
              health_checks: %{
                passive: %{
                  fail_duration: "10s",
                  max_fails: 3,
                  unhealthy_request_count: 80,
                  unhealthy_status: [500, 501, 502, 503, 504],
                  unhealthy_latency: "30s"
                }
              },
              upstreams:
                Enum.map(metadata.instances, fn instance ->
                  %{
                    dial: "#{instance.slug}:#{port.target}",
                    max_requests: 80
                  }
                end)
            }
          ]
        }
      end)

    [main_route | sub_routes]
  end
end
