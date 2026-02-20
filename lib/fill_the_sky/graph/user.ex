defmodule FillTheSky.Graph.User do
  @moduledoc """
  Schema for Bluesky users identified by their DID.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :did, :string
    field :handle, :string
    field :display_name, :string
    field :bio, :string
    field :avatar_url, :string
    field :followers_count, :integer, default: 0
    field :following_count, :integer, default: 0
    field :posts_count, :integer, default: 0
    field :crawl_state, :string, default: "pending"
    field :crawled_at, :utc_datetime_usec
    field :profile_fetched_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:did]
  @optional_fields [
    :handle,
    :display_name,
    :bio,
    :avatar_url,
    :followers_count,
    :following_count,
    :posts_count,
    :crawl_state,
    :crawled_at,
    :profile_fetched_at
  ]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:did)
  end

  @profile_fields [
    :handle,
    :display_name,
    :bio,
    :avatar_url,
    :followers_count,
    :following_count,
    :posts_count,
    :profile_fetched_at
  ]

  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, @profile_fields)
    |> validate_required([:handle])
  end
end
