defmodule Uplink.Packages.Deployment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uplink.Packages.{
    App,
    Archive,
    Installation
  }

  use Eventful.Transitable,
    transitions_module: __MODULE__.Transitions

  schema "deployments" do
    field :hash, :string
    field :archive_url, :string
    field :current_state, :string, default: "created"

    field :metadata, :map, virtual: true

    belongs_to :app, App

    has_one :archive, Archive

    has_many :installations, Installation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(deployment, params) do
    deployment
    |> cast(params, [:hash, :archive_url, :metadata])
    |> validate_required([:hash, :archive_url, :metadata])
  end

  def identifier(%__MODULE__{hash: hash, app: app}) do
    Path.join([~s(deployments), app.slug, hash])
  end
end
