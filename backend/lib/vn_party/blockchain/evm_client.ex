defmodule VnParty.Blockchain.EvmClient do
  @moduledoc false

  def enabled? do
    rpc = System.get_env("BLOCKCHAIN_RPC_URL")
    from = System.get_env("BLOCKCHAIN_FROM_ADDRESS")
    is_binary(rpc) and rpc != "" and is_binary(from) and from != ""
  end

  def anchor_hash(chain_hash) when is_binary(chain_hash) do
    rpc = System.get_env("BLOCKCHAIN_RPC_URL")
    from = System.get_env("BLOCKCHAIN_FROM_ADDRESS")
    to = System.get_env("BLOCKCHAIN_TO_ADDRESS") || from

    if not enabled?() do
      {:error, :blockchain_not_configured}
    else
      payload = %{
        jsonrpc: "2.0",
        id: System.unique_integer([:positive]),
        method: "eth_sendTransaction",
        params: [
          %{
            from: from,
            to: to,
            value: "0x0",
            data: hash_to_hex_data(chain_hash)
          }
        ]
      }

      case Req.post(rpc, json: payload) do
        {:ok, %{status: 200, body: %{"result" => tx_hash}}} when is_binary(tx_hash) ->
          {:ok, tx_hash}

        {:ok, %{body: %{"error" => err}}} ->
          {:error, {:rpc_error, err}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp hash_to_hex_data(hash) do
    clean = String.replace_prefix(hash, "0x", "")
    "0x" <> Base.encode16(clean, case: :lower)
  end
end

