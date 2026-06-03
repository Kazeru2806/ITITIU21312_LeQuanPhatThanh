defmodule VnParty.Repo do
  use Ecto.Repo,
    otp_app: :vn_party,
    adapter: Ecto.Adapters.Postgres
end
