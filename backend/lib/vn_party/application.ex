defmodule VnParty.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS tables for shared state storage
    :ets.new(:rematch_votes, [:set, :public, :named_table])
    :ets.new(:rematch_declined, [:set, :public, :named_table])
    :ets.new(:round_scored, [:set, :public, :named_table])
    :ets.new(:truth_player_stats, [:set, :public, :named_table])
    :ets.new(:truth_predictions, [:set, :public, :named_table])
    :ets.new(:truth_distortions, [:bag, :public, :named_table])
    :ets.new(:truth_round_data, [:set, :public, :named_table])
    :ets.new(:truth_active_category, [:set, :public, :named_table])
    :ets.new(:truth_results_ack, [:set, :public, :named_table])
    :ets.new(:truth_room_phase, [:set, :public, :named_table])
    :ets.new(:truth_discussion_mono, [:set, :public, :named_table])
    :ets.new(:truth_last_results, [:set, :public, :named_table])
    :ets.new(:truth_answering_mono, [:set, :public, :named_table])
    :ets.new(:truth_question_history, [:set, :public, :named_table])
    :ets.new(:truth_fake_locks, [:set, :public, :named_table])
    :ets.new(:rematch_snapshot, [:set, :public, :named_table])
    :ets.new(:commit_windows, [:set, :public, :named_table])
    :ets.new(:player_absent, [:set, :public, :named_table])
    :ets.new(:player_round_skip, [:set, :public, :named_table])
    :ets.new(:force_end_pending, [:set, :public, :named_table])
    :ets.new(:pending_answers, [:set, :public, :named_table])
    :ets.new(:distortion_usage, [:set, :public, :named_table])
    :ets.new(:truth_discussion_ack, [:set, :public, :named_table])
    :ets.new(:truth_inject_preview, [:set, :public, :named_table])

    pubsub_child =
      case System.get_env("REDIS_URL") do
        url when is_binary(url) and url != "" ->
          # Redis PubSub adapter for H2 scalability validation
          {Phoenix.PubSub,
           name: VnParty.PubSub,
           adapter: Phoenix.PubSub.Redis,
           redis_opts: url,
           node_name: node()}

        _ ->
          {Phoenix.PubSub, name: VnParty.PubSub}
      end

    children = [
      VnPartyWeb.Telemetry,
      VnParty.Repo,
      {DNSCluster, query: Application.get_env(:vn_party, :dns_cluster_query) || :ignore},
      pubsub_child,
      # Start a worker by calling: VnParty.Worker.start_link(arg)
      # {VnParty.Worker, arg},
      # Start to serve requests, typically the last entry
      VnPartyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VnParty.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VnPartyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
