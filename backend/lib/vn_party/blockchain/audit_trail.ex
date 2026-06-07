defmodule VnParty.Blockchain.AuditTrail do
  @moduledoc false

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Game.BlockchainAnchor
  alias VnParty.Blockchain.EvmClient

  def on_event(event) do
    if cache_enabled?() do
      anchor_event(event)
    else
      if Application.get_env(:vn_party, :async_blockchain_anchoring, true) do
        Task.start(fn -> anchor_event(event) end)
      else
        anchor_event(event)
      end
    end
    :ok
  end

  def anchor_event(%{id: event_id, room_id: room_id, seq: seq} = event) do
    prev_chain_hash =
      case :ets.lookup(:room_chain_hash, room_id) do
        [{^room_id, hash}] ->
          hash

        [] ->
          if cache_enabled?() do
            nil
          else
            prev =
              BlockchainAnchor
              |> where([a], a.room_id == ^room_id)
              |> order_by([a], desc: a.seq)
              |> limit(1)
              |> Repo.one()

            hash = prev && prev.chain_hash
            :ets.insert(:room_chain_hash, {room_id, hash})
            hash
          end
      end

    event_hash = event_hash(event)
    chain_hash = chain_hash(prev_chain_hash, event_hash)
    :ets.insert(:room_chain_hash, {room_id, chain_hash})

    if cache_enabled?() do
      anchor = %BlockchainAnchor{
        id: Ecto.UUID.generate(),
        room_id: room_id,
        event_id: event_id,
        seq: seq,
        event_hash: event_hash,
        prev_chain_hash: prev_chain_hash,
        chain_hash: chain_hash,
        status: "simulated",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      anchors =
        case :ets.lookup(:blockchain_anchor_cache, room_id) do
          [{_, list}] -> list
          _ -> []
        end

      :ets.insert(:blockchain_anchor_cache, {room_id, anchors ++ [anchor]})
      {:ok, anchor}
    else
      with {:ok, anchor} <-
             %BlockchainAnchor{}
             |> BlockchainAnchor.changeset(%{
               room_id: room_id,
               event_id: event_id,
               seq: seq,
               event_hash: event_hash,
               prev_chain_hash: prev_chain_hash,
               chain_hash: chain_hash,
               status: "pending"
             })
             |> Repo.insert(on_conflict: :nothing, conflict_target: :event_id) do

        if EvmClient.enabled?() do
          case EvmClient.anchor_hash(chain_hash) do
            {:ok, tx_hash} ->
              anchor
              |> Ecto.Changeset.change(%{status: "anchored", tx_hash: tx_hash})
              |> Repo.update()

            {:error, reason} ->
              anchor
              |> Ecto.Changeset.change(%{status: "failed", error: inspect(reason)})
              |> Repo.update()
          end
        else
          anchor
          |> Ecto.Changeset.change(%{status: "simulated"})
          |> Repo.update()
        end
      else
        _ -> :ok
      end
    end
  end

  def list_room_anchors(room_id) do
    if cache_enabled?() do
      case :ets.lookup(:blockchain_anchor_cache, room_id) do
        [{_, list}] -> list
        _ -> []
      end
    else
      BlockchainAnchor
      |> where([a], a.room_id == ^room_id)
      |> order_by([a], asc: a.seq)
      |> Repo.all()
    end
  end

  defp event_hash(event) do
    payload = Jason.encode!(event.payload || %{})
    meta = Jason.encode!(event.metadata || %{})
    blob = "#{event.room_id}|#{event.seq}|#{event.event_type}|#{payload}|#{meta}"
    :crypto.hash(:sha256, blob) |> Base.encode16(case: :lower)
  end

  defp chain_hash(nil, event_hash), do: event_hash

  defp chain_hash(prev_chain_hash, event_hash) do
    :crypto.hash(:sha256, "#{prev_chain_hash}:#{event_hash}")
    |> Base.encode16(case: :lower)
  end

  defp cache_enabled? do
    Application.get_env(:vn_party, :cache_enabled, true)
  end
end
