defmodule FillTheSky.Repo.Migrations.CreateCrawlTables do
  use Ecto.Migration

  def change do
    create table(:crawl_seeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :did, :string, null: false
      add :handle, :string
      add :depth, :integer, default: 2
      add :status, :string, default: "pending"
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crawl_seeds, [:did])

    create table(:crawl_cursors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :endpoint, :string, null: false
      add :target_did, :string, null: false
      add :cursor, :string
      add :completed, :boolean, default: false
      add :page_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crawl_cursors, [:endpoint, :target_did])
  end
end
