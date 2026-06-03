defmodule VnPartyWeb.TelemetryController do
  use VnPartyWeb, :controller

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Game
  alias VnParty.Telemetry.LatencyMeasurement

  @doc """
  GET /api/telemetry/latency.csv?room_code=ABCD

  Returns latency measurements as CSV for analysis.
  """
  def latency_csv(conn, %{"room_code" => room_code} = params) do
    room =
      case Game.get_room_by_code(room_code) do
        nil -> nil
        r -> r
      end

    if is_nil(room) do
      conn
      |> put_status(:not_found)
      |> json(%{success: false, error: "Room not found"})
    else
      event = Map.get(params, "event")

      rows =
        LatencyMeasurement
        |> where([m], m.room_id == ^room.id)
        |> maybe_where_event(event)
        |> order_by([m], asc: m.inserted_at)
        |> Repo.all()

      csv = build_latency_csv(room.code, rows)

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", "attachment; filename=\"latency_#{room.code}.csv\"")
      |> send_resp(200, csv)
    end
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
          r.inserted_at |> to_string(),
          r.event,
          r.direction,
          r.mode || "",
          r.round || "",
          r.player_id || "",
          r.client_timestamp_ms || "",
          r.server_received_timestamp_ms,
          r.latency_ms || ""
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

