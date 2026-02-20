defmodule FillTheSky.Crawl.CrawlCursor do
  @moduledoc """
  Schema for tracking pagination cursor state when crawling Bluesky API endpoints.
  Enables resumable crawling across restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "crawl_cursors" do
    field :endpoint, :string
    field :target_did, :string
    field :cursor, :string
    field :completed, :boolean, default: false
    field :page_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [:endpoint, :target_did, :cursor, :completed, :page_count])
    |> validate_required([:endpoint, :target_did])
    |> validate_inclusion(:endpoint, ~w(getFollows getFollowers getAuthorFeed))
    |> unique_constraint([:endpoint, :target_did])
  end
end
