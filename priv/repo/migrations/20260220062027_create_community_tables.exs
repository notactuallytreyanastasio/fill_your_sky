defmodule FillTheSky.Repo.Migrations.CreateCommunityTables do
  use Ecto.Migration

  def change do
    create table(:community_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :user_count, :integer, default: 0
      add :edge_count, :integer, default: 0
      add :community_count, :integer, default: 0
      add :leiden_resolution, :float, default: 1.0
      add :node2vec_dimensions, :integer, default: 64
      add :error_message, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:community_runs, [:status])

    create table(:communities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:community_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :community_index, :integer, null: false
      add :label, :string
      add :top_terms, {:array, :string}, default: []
      add :category, :string
      add :color, :string
      add :member_count, :integer, default: 0
      add :centroid_x, :float
      add :centroid_y, :float

      timestamps(type: :utc_datetime_usec)
    end

    create index(:communities, [:run_id])
    create unique_index(:communities, [:run_id, :community_index])

    create table(:user_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :run_id, references(:community_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :community_id, references(:communities, type: :binary_id, on_delete: :delete_all)
      add :x, :float, null: false
      add :y, :float, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_embeddings, [:run_id])
    create index(:user_embeddings, [:community_id])
    create unique_index(:user_embeddings, [:user_id, :run_id])
  end
end
