defmodule VnParty.CacheSweeper do
  @moduledoc """
  A background worker that periodically cleans up stale rooms from the ETS cache
  to prevent memory bloat and Out-Of-Memory errors during high load.
  """
  use GenServer

  alias VnParty.Game

  # Sweep every 30 seconds
  @sweep_interval_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(state) do
    schedule_sweep()
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    if cache_enabled?() do
      Game.cleanup_stale_rooms()
    end

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp cache_enabled? do
    Application.get_env(:vn_party, :cache_enabled, true)
  end
end
