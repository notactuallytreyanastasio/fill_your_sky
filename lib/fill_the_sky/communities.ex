defmodule FillTheSky.Communities do
  @moduledoc """
  Context for community detection runs, communities, and user embeddings.
  """

  import Ecto.Query

  alias FillTheSky.Communities.{Community, CommunityRun, UserEmbedding}
  alias FillTheSky.Repo

  # --- Community Runs ---

  @spec create_run(map()) :: {:ok, CommunityRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs \\ %{}) do
    %CommunityRun{}
    |> CommunityRun.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: {:ok, CommunityRun.t()} | {:error, :not_found}
  def get_run(id) do
    case Repo.get(CommunityRun, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @spec update_run(CommunityRun.t(), map()) ::
          {:ok, CommunityRun.t()} | {:error, Ecto.Changeset.t()}
  def update_run(run, attrs) do
    run
    |> CommunityRun.changeset(attrs)
    |> Repo.update()
  end

  @spec latest_complete_run() :: {:ok, CommunityRun.t()} | {:error, :not_found}
  def latest_complete_run do
    query =
      from(r in CommunityRun,
        where: r.status == "complete",
        order_by: [desc: r.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @spec list_runs() :: list(CommunityRun.t())
  def list_runs do
    from(r in CommunityRun, order_by: [desc: r.inserted_at])
    |> Repo.all()
  end

  # --- Communities ---

  @spec batch_insert_communities(String.t(), list(map())) :: {non_neg_integer(), nil}
  def batch_insert_communities(run_id, communities) when is_list(communities) do
    now = DateTime.utc_now()

    entries =
      Enum.map(communities, fn c ->
        %{
          id: Ecto.UUID.generate(),
          run_id: run_id,
          community_index: c.community_index,
          label: c[:label],
          top_terms: c[:top_terms] || [],
          color: c[:color],
          member_count: c[:member_count] || 0,
          centroid_x: c[:centroid_x],
          centroid_y: c[:centroid_y],
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Community, entries)
  end

  @spec get_communities_for_run(String.t()) :: list(Community.t())
  def get_communities_for_run(run_id) do
    from(c in Community,
      where: c.run_id == ^run_id,
      order_by: [asc: c.community_index]
    )
    |> Repo.all()
  end

  # --- User Embeddings ---

  @spec batch_insert_embeddings(list(map())) :: {non_neg_integer(), nil}
  def batch_insert_embeddings(embeddings) when is_list(embeddings) do
    now = DateTime.utc_now()

    entries =
      Enum.map(embeddings, fn e ->
        %{
          id: Ecto.UUID.generate(),
          user_id: e.user_id,
          run_id: e.run_id,
          community_id: e[:community_id],
          x: e.x,
          y: e.y,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(UserEmbedding, entries)
  end

  @spec get_map_data(String.t()) :: list(map())
  def get_map_data(run_id) do
    from(e in UserEmbedding,
      join: u in assoc(e, :user),
      join: c in assoc(e, :community),
      where: e.run_id == ^run_id,
      select: %{
        user_id: u.id,
        did: u.did,
        handle: u.handle,
        display_name: u.display_name,
        x: e.x,
        y: e.y,
        community_index: c.community_index,
        community_label: c.label,
        color: c.color
      }
    )
    |> Repo.all()
  end
end
