import Config

if System.get_env("PHX_SERVER") do
  config :vn_party, VnPartyWeb.Endpoint, server: true
end

config :vn_party, VnPartyWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :vn_party, VnParty.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :vn_party, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :vn_party, VnPartyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base,
    check_origin: [
      "https://vn-party-thesis.vercel.app",
      "https://vn-party-thesis-host.vercel.app",
      "https://vn-party-thesis-host-2bjn9x6y1-kazs-projects-a81dd6d8.vercel.app"
    ]
end

config :vn_party, :cache_enabled, config_env() != :test and System.get_env("CACHE_ENABLED") != "false"
