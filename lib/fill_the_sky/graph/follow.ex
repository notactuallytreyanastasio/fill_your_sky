defmodule FillTheSky.Graph.Follow do
  @moduledoc """
  Schema for follow relationships between users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FillTheSky.Graph.User

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "follows" do
    belongs_to :follower, User
    belongs_to :following, User

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:follower_id, :following_id])
    |> validate_required([:follower_id, :following_id])
    |> unique_constraint([:follower_id, :following_id])
    |> foreign_key_constraint(:follower_id)
    |> foreign_key_constraint(:following_id)
  end
end
