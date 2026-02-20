defmodule FillTheSky.Communities.UserEmbedding do
  @moduledoc """
  Schema for 2D user coordinates produced by Node2Vec + UMAP.
  Links a user to a community within a specific run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FillTheSky.Communities.{Community, CommunityRun}
  alias FillTheSky.Graph.User

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_embeddings" do
    belongs_to :user, User
    belongs_to :run, CommunityRun
    belongs_to :community, Community
    field :x, :float
    field :y, :float

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:user_id, :run_id, :community_id, :x, :y])
    |> validate_required([:user_id, :run_id, :x, :y])
    |> unique_constraint([:user_id, :run_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:community_id)
  end
end
