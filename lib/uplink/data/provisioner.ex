defmodule Uplink.Data.Provisioner do
  use GenServer

  require Logger

  alias Uplink.Clients.LXD
  alias Uplink.Clients.Instellar

  alias Uplink.Data.Pro

  alias Formation.Postgresql.Credential

  @release_tasks Application.compile_env(:uplink, :release_tasks) ||
                   Uplink.Release.Tasks

  defstruct [:mode, :project, :status, :parent]

  @type t :: %__MODULE__{
          mode: String.t(),
          project: String.t(),
          status: :ok | :error | :provisioning | nil
        }

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)

    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl true
  def init(options) do
    config = Application.get_env(:uplink, Uplink.Data) || []
    parent = Keyword.get(options, :parent)

    env =
      Keyword.get(
        options,
        :environment,
        Application.get_env(:uplink, :environment)
      )

    mode = Keyword.get(config, :mode, "pro")
    project = Keyword.get(config, :project, "default")

    send(self(), {:bootstrap, mode, env})

    {:ok, %__MODULE__{mode: mode, project: project, parent: parent}}
  end

  @impl true
  def handle_info({:bootstrap, "pro", :prod = env}, state) do
    if System.get_env("DATABASE_URL") do
      Uplink.Data.start_link([])
    else
      %{"components" => components} = Instellar.get_self()

      with {:ok, %{"credential" => credential}} <-
             components
             |> Enum.find(&Pro.match_postgresql_component/1)
             |> Pro.maybe_provision_postgresql_instance(),
           {:ok, credential} <- Credential.create(credential) do
        uri = URI.parse("ecto:///")

        %{
          username: username,
          password: password,
          hostname: host,
          port: port,
          database: database
        } = credential

        url =
          %{
            uri
            | host: host,
              userinfo: "#{username}:#{password}",
              authority: "#{host}:#{port}",
              port: port,
              path: "/#{database}"
          }
          |> to_string()

        repo_options = [
          url: url,
          queue_target: 10_000,
          ssl_opts: [
            verify: :verify_peer,
            server_name_indication: to_charlist(host),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        ]

        Application.put_env(:uplink, Uplink.Repo, repo_options)
        @release_tasks.migrate(force: true)
        Uplink.Data.start_link([])

        if state.parent, do: send(state.parent, :upgraded_to_pro)

        {:noreply, put_in(state.status, :ok)}
      else
        {:error, _error} = result ->
          Logger.info("[Data.Provisioner] falling back to lite ...")

          send(self(), {:bootstrap, "lite", env})

          {:noreply, put_in(state.status, :provisioning)}
      end
    end
  end

  def handle_info({:bootstrap, "pro", _}, state) do
    Uplink.Data.start_link([])

    {:noreply, put_in(state.status, :ok)}
  end

  def handle_info({:bootstrap, "lite", _env}, state) do
    db_url = Formation.Lxd.Alpine.postgresql_connection_url(scheme: "ecto")
    uri = URI.parse(db_url)

    [username, password] = String.split(uri.userinfo, ":")
    [_, database_name] = String.split(uri.path, "/")

    {:ok, conn} =
      Postgrex.start_link(
        hostname: uri.host,
        username: username,
        password: password,
        database: database_name
      )

    case Postgrex.query(conn, "SELECT 1", []) do
      {:ok, _} ->
        Application.put_env(:uplink, Uplink.Repo, url: db_url)
        GenServer.stop(conn)

        Uplink.Release.Tasks.migrate(force: true)
        Uplink.Data.start_link([])

        {:noreply, put_in(state.status, :ok)}

      {:error, _} ->
        GenServer.stop(conn)

        Logger.info("[Data.Provisioner] provisioning local postgresql ...")

        client = LXD.client()

        Formation.Lxd.Alpine.provision_postgresql(client, project: state.project)

        Process.send_after(self(), {:bootstrap, state.mode}, 5_000)

        {:noreply, put_in(state.status, :provisioning)}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end
end
