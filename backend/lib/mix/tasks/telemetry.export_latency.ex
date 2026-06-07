defmodule Mix.Tasks.Telemetry.ExportLatency do
  use Mix.Task

  @shortdoc "Export latency measurements to CSV"

  @moduledoc """
  Exports latency measurements for a room to CSV.

      mix telemetry.export_latency ROOM_CODE [--event commit_answer] [--out path.csv]
  """

  import Ecto.Query, warn: false

  alias VnParty.Repo
  alias VnParty.Game
  alias VnParty.Telemetry.LatencyMeasurement

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [event: :string, out: :string]
      )

    room_code = positional |> List.first()

    if is_nil(room_code) or room_code == "" do
      Mix.raise("Usage: mix telemetry.export_latency ROOM_CODE [--event commit_answer] [--out path.csv]")
    end

    room = Game.get_room_by_code(room_code)

    if is_nil(room) do
      Mix.raise("Room not found: #{room_code}")
    end

    event = Keyword.get(opts, :event)
    out = Keyword.get(opts, :out, "latency_#{String.upcase(room_code)}.csv")

    db_rows =
      LatencyMeasurement
      |> where([m], m.room_id == ^room.id)
      |> maybe_where_event(event)
      |> order_by([m], asc: m.inserted_at)
      |> Repo.all()

    cached_rows =
      case :ets.lookup(:latency_measurements_cache, room.id) do
        [] -> []
        list ->
          list
          |> Enum.map(fn {_, attrs} -> attrs end)
          |> Enum.filter(fn r ->
            is_nil(event) || event == "" || Map.get(r, :event) == event || Map.get(r, "event") == event
          end)
      end

    rows =
      (db_rows ++ cached_rows)
      |> Enum.sort_by(fn r ->
        Map.get(r, :inserted_at) || Map.get(r, "inserted_at")
      end)

    csv = build_latency_csv(room.code, rows)
    File.write!(out, csv)
    Mix.shell().info("Wrote #{length(rows)} rows to #{out}")
  end

  defp maybe_where_event(query, nil), do: query
  defp maybe_where_event(query, ""), do: query
  defp maybe_where_event(query, event), do: where(query, [m], m.event == ^event)

  defp build_latency_csv(room_code, rows) do
    header = [
      "room_code",
      "inserted_at",
      "event",
      "direction",
      "mode",
      "round",
      "player_id",
      "client_timestamp_ms",
      "server_received_timestamp_ms",
      "latency_ms"
    ]

    body =
      Enum.map(rows, fn r ->
        [
          room_code,
          (Map.get(r, :inserted_at) || Map.get(r, "inserted_at")) |> to_string(),
          Map.get(r, :event) || Map.get(r, "event"),
          Map.get(r, :direction) || Map.get(r, "direction"),
          Map.get(r, :mode) || Map.get(r, "mode") || "",
          Map.get(r, :round) || Map.get(r, "round") || "",
          Map.get(r, :player_id) || Map.get(r, "player_id") || "",
          Map.get(r, :client_timestamp_ms) || Map.get(r, "client_timestamp_ms") || "",
          Map.get(r, :server_received_timestamp_ms) || Map.get(r, "server_received_timestamp_ms") || "",
          Map.get(r, :latency_ms) || Map.get(r, "latency_ms") || ""
        ]
        |> Enum.map(&escape_csv/1)
        |> Enum.join(",")
      end)

    Enum.join([Enum.join(header, ",") | body], "\n") <> "\n"
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(v) when is_integer(v), do: Integer.to_string(v)

  defp escape_csv(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(v, "\"", "\"\"") <> "\""
    else
      v
    end
  end

  defp escape_csv(v), do: escape_csv(to_string(v))
end

