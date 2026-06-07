defmodule VnParty.Telemetry do
  @moduledoc """
  Telemetry helpers for thesis measurements (latency, etc).
  """

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Telemetry.LatencyMeasurement

  def record_latency(attrs) when is_map(attrs) do
    if Application.get_env(:vn_party, :cache_enabled, true) do
      room_id = Map.get(attrs, :room_id) || Map.get(attrs, "room_id") || Ecto.UUID.generate()
      attrs = Map.put_new(attrs, :inserted_at, DateTime.utc_now())
      :ets.insert(:latency_measurements_cache, {room_id, attrs})
      {:ok, attrs}
    else
      insert_with_retry(attrs, 3)
    end
  end

  defp insert_with_retry(_attrs, 0), do: {:error, :max_retries}

  defp insert_with_retry(attrs, attempts_left) do
    result =
      %LatencyMeasurement{}
      |> LatencyMeasurement.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        if attempts_left > 1 do
          Process.sleep(50)
          insert_with_retry(attrs, attempts_left - 1)
        else
          err
        end
    end
  rescue
    _e ->
      if attempts_left > 1 do
        Process.sleep(50)
        insert_with_retry(attrs, attempts_left - 1)
      else
        {:error, :insert_failed}
      end
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

