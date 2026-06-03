defmodule VnParty.Game.BlockchainAnchor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "blockchain_anchors" do
    field :seq, :integer
    field :event_hash, :string
    field :prev_chain_hash, :string
    field :chain_hash, :string
    field :tx_hash, :string
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :room, VnParty.Game.Room
    belongs_to :event, VnParty.Game.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(anchor, attrs) do
    anchor
    |> cast(attrs, [
      :room_id,
      :event_id,
      :seq,
      :event_hash,
      :prev_chain_hash,
      :chain_hash,
      :tx_hash,
      :status,
      :error
    ])
    |> validate_required([:room_id, :event_id, :seq, :event_hash, :chain_hash, :status])
    |> unique_constraint(:event_id)
  end
end

