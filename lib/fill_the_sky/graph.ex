defmodule FillTheSky.Graph do
  @moduledoc """
  Context for managing the social graph: users and follow relationships.
  """

  import Ecto.Query

  alias FillTheSky.Graph.{Follow, User}
  alias FillTheSky.Repo

  # --- Users ---

  @spec get_user(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_user_by_did(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_by_did(did) do
    case Repo.get_by(User, did: did) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec upsert_user_by_did(String.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def upsert_user_by_did(did, attrs \\ %{}) do
    %User{}
    |> User.changeset(Map.put(attrs, :did, did))
    |> Repo.insert(
      on_conflict: {:replace, [:handle, :display_name, :updated_at]},
      conflict_target: :did,
      returning: true
    )
  end

  @spec update_user_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @spec batch_upsert_users_by_did(list(String.t())) :: {non_neg_integer(), list(User.t()) | nil}
  def batch_upsert_users_by_did(dids) when is_list(dids) do
    now = DateTime.utc_now()

    entries =
      Enum.map(dids, fn did ->
        %{
          id: Ecto.UUID.generate(),
          did: did,
          crawl_state: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(User, entries, on_conflict: :nothing, conflict_target: :did)
  end

  @spec search_users(String.t(), keyword()) :: list(User.t())
  def search_users(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    pattern = "%#{query}%"

    from(u in User,
      where: ilike(u.handle, ^pattern) or ilike(u.bio, ^pattern),
      order_by: [desc: u.followers_count],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec users_needing_profiles(non_neg_integer()) :: list(User.t())
  def users_needing_profiles(limit \\ 100) do
    from(u in User,
      where: is_nil(u.profile_fetched_at),
      order_by: [asc: u.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  # --- Follows ---

  @spec create_follow(String.t(), String.t()) :: {:ok, Follow.t()} | {:error, Ecto.Changeset.t()}
  def create_follow(follower_id, following_id) do
    %Follow{}
    |> Follow.changeset(%{follower_id: follower_id, following_id: following_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:follower_id, :following_id])
  end

  @spec batch_upsert_follows(list(map())) :: {non_neg_integer(), nil}
  def batch_upsert_follows(follows) when is_list(follows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(follows, fn %{follower_id: fid, following_id: fgid} ->
        %{
          id: Ecto.UUID.generate(),
          follower_id: fid,
          following_id: fgid,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Follow, entries,
      on_conflict: :nothing,
      conflict_target: [:follower_id, :following_id]
    )
  end

  @spec follow_count() :: non_neg_integer()
  def follow_count, do: Repo.aggregate(Follow, :count)

  @spec user_count() :: non_neg_integer()
  def user_count, do: Repo.aggregate(User, :count)

  @spec export_edges() :: list({String.t(), String.t()})
  def export_edges do
    from(f in Follow,
      join: follower in User,
      on: f.follower_id == follower.id,
      join: following in User,
      on: f.following_id == following.id,
      select: {follower.did, following.did}
    )
    |> Repo.all()
  end

  @spec export_user_bios() :: map()
  def export_user_bios do
    from(u in User, where: not is_nil(u.bio), select: {u.did, u.bio})
    |> Repo.all()
    |> Map.new()
  end
end
