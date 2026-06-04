defmodule VnPartyWeb.RoomController do
  use VnPartyWeb, :controller
  alias VnParty.Game

  @doc """
  POST /api/rooms
  Creates a new game room
  """
  def create(conn, params) do
    case Game.create_room(params) do
      {:ok, room} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          room: %{
            id: room.id,
            code: room.code,
            state: room.state,
            max_players: room.max_players,
            total_rounds: room.total_rounds
          }
        })
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          errors: format_errors(changeset)
        })
    end
  end

  @doc """
  GET /api/rooms/:code
  Gets room information by code
  """
  def show(conn, %{"code" => code}) do
    case Game.get_room_by_code_with_players(code) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Room not found"})
      
      room ->
        conn
        |> json(%{
          success: true,
          room: %{
            id: room.id,
            code: room.code,
            state: room.state,
            current_round: room.current_round,
            total_rounds: room.total_rounds,
            max_players: room.max_players,
            player_count: length(room.players),
            started_at: room.started_at
          }
        })
    end
  end

  @doc """
  POST /api/rooms/:code/join
  Joins a player to a room
  """
  def join(conn, %{"code" => code, "nickname" => nickname} = params) do
    attrs =
      params
      |> Map.take(["player_id"])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    case Game.join_room(code, nickname, attrs) do
      {:ok, player} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          player: %{
            id: player.id,
            nickname: player.nickname,
            is_host: player.is_host,
            room_code: code
          }
        })
      
      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Room not found"})
      
      {:error, :room_full} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: "Room is full"})

      {:error, :game_in_progress} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: "Game already started. Rejoin with the same device session."})

      {:error, :nickname_mismatch} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: "Use the same name as when you joined this game."})
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          errors: format_errors(changeset)
        })
    end
  end

  @doc """
  GET /api/rooms/:code/players
  Lists all players in a room
  """
  def list_players(conn, %{"code" => code}) do
    case Game.get_room_by_code(code) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Room not found"})
      
      room ->
        players = Game.list_players(room.id)
        
        conn
        |> json(%{
          success: true,
          players: Enum.map(players, fn player ->
            %{
              id: player.id,
              nickname: player.nickname,
              score: player.score,
              connected: player.connected,
              is_host: player.is_host
            }
          end)
        })
    end
  end

  @doc """
  GET /api/rooms/:code/audit
  Returns blockchain anchor trail for a room.
  """
  def audit(conn, %{"code" => code}) do
    case Game.get_room_by_code(code) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Room not found"})

      room ->
        anchors =
          Game.list_blockchain_anchors(room.id)
          |> Enum.map(fn a ->
            %{
              seq: a.seq,
              event_hash: a.event_hash,
              prev_chain_hash: a.prev_chain_hash,
              chain_hash: a.chain_hash,
              tx_hash: a.tx_hash,
              status: a.status,
              inserted_at: a.inserted_at
            }
          end)

        json(conn, %{success: true, room_code: room.code, anchors: anchors})
    end
  end

  # Helper function to format Ecto changeset errors
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end