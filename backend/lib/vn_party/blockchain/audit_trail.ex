defmodule VnParty.Blockchain.AuditTrail do
  @moduledoc false

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Game.BlockchainAnchor
  alias VnParty.Blockchain.EvmClient

  def on_event(event) do
    if Application.get_env(:vn_party, :async_blockchain_anchoring, true) do
      Task.start(fn -> anchor_event(event) end)
    else
      anchor_event(event)
    end
    :ok
  end

  def anchor_event(%{id: event_id, room_id: room_id, seq: seq} = event) do
    prev_chain_hash =
      case :ets.lookup(:room_chain_hash, room_id) do
        [{^room_id, hash}] ->
          hash

        [] ->
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

    event_hash = event_hash(event)
    chain_hash = chain_hash(prev_chain_hash, event_hash)

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
      :ets.insert(:room_chain_hash, {room_id, chain_hash})

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

  def list_room_anchors(room_id) do
    BlockchainAnchor
    |> where([a], a.room_id == ^room_id)
    |> order_by([a], asc: a.seq)
    |> Repo.all()
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
end
