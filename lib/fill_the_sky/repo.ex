defmodule FillTheSky.Repo do
  use Ecto.Repo,
    otp_app: :fill_the_sky,
    adapter: Ecto.Adapters.Postgres
end
