defmodule FillTheSky.Crawl.CrawlSeed do
  @moduledoc """
  Schema for seed accounts to begin graph crawling from.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "crawl_seeds" do
    field :did, :string
    field :handle, :string
    field :depth, :integer, default: 2
    field :status, :string, default: "pending"
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(seed, attrs) do
    seed
    |> cast(attrs, [:did, :handle, :depth, :status, :priority])
    |> validate_required([:did])
    |> validate_inclusion(:status, ~w(pending crawling complete error))
    |> validate_number(:depth, greater_than: 0, less_than_or_equal_to: 5)
    |> unique_constraint(:did)
  end
end
