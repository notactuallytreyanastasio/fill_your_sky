defmodule FillTheSky.Communities.CommunityRun do
  @moduledoc """
  Schema for ML pipeline runs. Each run captures a snapshot of community detection
  with its parameters, allowing comparison between runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FillTheSky.Communities.Community

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["pending", "running", "exporting", "computing", "importing", "complete", "error"]

  schema "community_runs" do
    field :status, :string, default: "pending"
    field :user_count, :integer, default: 0
    field :edge_count, :integer, default: 0
    field :community_count, :integer, default: 0
    field :leiden_resolution, :float, default: 1.0
    field :node2vec_dimensions, :integer, default: 64
    field :error_message, :string

    has_many :communities, Community, foreign_key: :run_id

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :user_count,
      :edge_count,
      :community_count,
      :leiden_resolution,
      :node2vec_dimensions,
      :error_message
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:leiden_resolution, greater_than: 0)
    |> validate_number(:node2vec_dimensions, greater_than: 0)
  end
end
