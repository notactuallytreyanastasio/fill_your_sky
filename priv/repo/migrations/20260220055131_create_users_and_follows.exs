defmodule FillTheSky.Repo.Migrations.CreateUsersAndFollows do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :did, :string, null: false
      add :handle, :string
      add :display_name, :string
      add :bio, :text
      add :avatar_url, :string
      add :followers_count, :integer, default: 0
      add :following_count, :integer, default: 0
      add :posts_count, :integer, default: 0
      add :crawl_state, :string, default: "pending"
      add :crawled_at, :utc_datetime_usec
      add :profile_fetched_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:did])
    create index(:users, [:handle])
    create index(:users, [:crawl_state])

    create table(:follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :follower_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :following_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:follows, [:follower_id, :following_id])
    create index(:follows, [:following_id])
  end
end
