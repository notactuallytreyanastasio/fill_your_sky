defmodule FillTheSky.Communities.Community do
  @moduledoc """
  Schema for a detected community within a run.
  Stores the cluster label, top terms, color, and centroid coordinates.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FillTheSky.Communities.CommunityRun

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "communities" do
    belongs_to :run, CommunityRun
    field :community_index, :integer
    field :label, :string
    field :top_terms, {:array, :string}, default: []
    field :category, :string
    field :color, :string
    field :member_count, :integer, default: 0
    field :centroid_x, :float
    field :centroid_y, :float

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(community, attrs) do
    community
    |> cast(attrs, [
      :run_id,
      :community_index,
      :label,
      :top_terms,
      :category,
      :color,
      :member_count,
      :centroid_x,
      :centroid_y
    ])
    |> validate_required([:run_id, :community_index])
    |> unique_constraint([:run_id, :community_index])
    |> foreign_key_constraint(:run_id)
  end
end
