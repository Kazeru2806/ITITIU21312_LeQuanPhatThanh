defmodule VnParty.Telemetry do
  @moduledoc """
  Telemetry helpers for thesis measurements (latency, etc).
  """

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Telemetry.LatencyMeasurement

  def record_latency(attrs) when is_map(attrs) do
    %LatencyMeasurement{}
    |> LatencyMeasurement.changeset(attrs)
    |> Repo.insert()
  end

  def list_latency(opts \\ []) do
    room_id = Keyword.get(opts, :room_id)
    event = Keyword.get(opts, :event)

    LatencyMeasurement
    |> maybe_where(:room_id, room_id)
    |> maybe_where(:event, event)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  defp maybe_where(query, _field, nil), do: query
  defp maybe_where(query, field, val), do: where(query, [m], field(m, ^field) == ^val)
end

