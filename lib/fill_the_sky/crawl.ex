defmodule FillTheSky.Crawl do
  @moduledoc """
  Context for managing crawl state: seeds and pagination cursors.
  """

  import Ecto.Query

  alias FillTheSky.Crawl.{CrawlCursor, CrawlSeed}
  alias FillTheSky.Repo

  # --- Seeds ---

  @spec add_seed(String.t(), keyword()) :: {:ok, CrawlSeed.t()} | {:error, Ecto.Changeset.t()}
  def add_seed(did, opts \\ []) do
    %CrawlSeed{}
    |> CrawlSeed.changeset(%{
      did: did,
      handle: Keyword.get(opts, :handle),
      depth: Keyword.get(opts, :depth, 2),
      priority: Keyword.get(opts, :priority, 0)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:status, :depth, :handle, :updated_at]},
      conflict_target: :did,
      returning: true
    )
  end

  @spec reset_stale_seeds() :: {non_neg_integer(), nil}
  def reset_stale_seeds do
    from(s in CrawlSeed, where: s.status == "crawling")
    |> Repo.update_all(set: [status: "pending", updated_at: DateTime.utc_now()])
  end

  @spec list_seeds() :: list(CrawlSeed.t())
  def list_seeds do
    from(s in CrawlSeed, order_by: [desc: s.priority, desc: s.inserted_at])
    |> Repo.all()
  end

  @spec pending_seeds(non_neg_integer()) :: list(CrawlSeed.t())
  def pending_seeds(limit \\ 50) do
    from(s in CrawlSeed,
      where: s.status == "pending",
      order_by: [desc: s.priority, asc: s.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec update_seed_status(CrawlSeed.t(), String.t()) ::
          {:ok, CrawlSeed.t()} | {:error, Ecto.Changeset.t()}
  def update_seed_status(seed, status) do
    seed
    |> CrawlSeed.changeset(%{status: status})
    |> Repo.update()
  end

  @spec seed_stats() :: %{
          pending: non_neg_integer(),
          crawling: non_neg_integer(),
          complete: non_neg_integer(),
          error: non_neg_integer()
        }
  def seed_stats do
    from(s in CrawlSeed,
      group_by: s.status,
      select: {s.status, count(s.id)}
    )
    |> Repo.all()
    |> Map.new()
    |> then(fn counts ->
      %{
        pending: Map.get(counts, "pending", 0),
        crawling: Map.get(counts, "crawling", 0),
        complete: Map.get(counts, "complete", 0),
        error: Map.get(counts, "error", 0)
      }
    end)
  end

  @spec cursor_stats() :: %{
          total: non_neg_integer(),
          completed: non_neg_integer(),
          pages_fetched: non_neg_integer()
        }
  def cursor_stats do
    total = Repo.aggregate(CrawlCursor, :count)
    completed = Repo.aggregate(from(c in CrawlCursor, where: c.completed == true), :count)
    pages = Repo.aggregate(CrawlCursor, :sum, :page_count) || 0

    %{total: total, completed: completed, pages_fetched: pages}
  end

  # --- Cursors ---

  @spec get_or_create_cursor(String.t(), String.t()) ::
          {:ok, CrawlCursor.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_cursor(endpoint, target_did) do
    case Repo.get_by(CrawlCursor, endpoint: endpoint, target_did: target_did) do
      nil ->
        %CrawlCursor{}
        |> CrawlCursor.changeset(%{endpoint: endpoint, target_did: target_did})
        |> Repo.insert()

      cursor ->
        {:ok, cursor}
    end
  end

  @spec update_cursor(CrawlCursor.t(), map()) ::
          {:ok, CrawlCursor.t()} | {:error, Ecto.Changeset.t()}
  def update_cursor(cursor, attrs) do
    cursor
    |> CrawlCursor.changeset(attrs)
    |> Repo.update()
  end

  @spec incomplete_cursors(String.t()) :: list(CrawlCursor.t())
  def incomplete_cursors(endpoint) do
    from(c in CrawlCursor,
      where: c.endpoint == ^endpoint and c.completed == false,
      order_by: [asc: c.updated_at]
    )
    |> Repo.all()
  end
end
