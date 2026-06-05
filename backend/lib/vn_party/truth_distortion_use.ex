defmodule VnParty.TruthDistortionUse do
  @moduledoc false

  alias VnParty.Game
  alias VnParty.Game.DistortionRules
  alias VnPartyWeb.Endpoint

  @type apply_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Applies a distortion power during results / discussion / transition.
  Used by WebSocket handlers, HTTP fallback, and bundled truth_results_ready.
  """
  @spec apply(String.t(), String.t(), String.t(), String.t(), map()) :: apply_result()
  def apply(room_id, player_id, nickname, action, payload) when is_binary(action) do
    room = Game.get_room!(room_id)

    cond do
      Game.room_mode(room) != "truth_collapse" ->
        {:error, "Distortions are only available in Truth Collapse"}

      current_truth_phase(room_id) not in ["results", "discussion", "transition"] ->
        {:error, "Distortions can only be used during the results phase"}

      action == "inject_fake_option" ->
        apply_inject_fake(room, player_id, nickname, payload)

      true ->
        apply_standard(room, player_id, nickname, action, payload)
    end
  end

  @doc """
  Completes inject fake after lock_fake_option (charge already spent at lock).
  """
  @spec complete_inject_fake(String.t(), String.t(), String.t(), String.t()) :: apply_result()
  def complete_inject_fake(room_id, player_id, nickname, fake_text) do
    room = Game.get_room!(room_id)
    phase = current_truth_phase(room_id)
    effect_round = distortion_effect_round(room, phase)
    lock_key = {room_id, effect_round, player_id}

    cond do
      Game.room_mode(room) != "truth_collapse" ->
        {:error, "Distortions are only available in Truth Collapse"}

      phase not in ["results", "discussion", "transition"] ->
        {:error, "Fake inject can only be used during the results phase"}

      :ets.lookup(:truth_fake_locks, lock_key) == [] ->
        {:error, "You must lock this power first"}

      true ->
        case validate_payload("inject_fake_option", %{"fake_text" => fake_text}, room, player_id) do
          {:error, reason} ->
            {:error, reason}

          {:ok, cleaned_payload} ->
            persist_distortion(room, player_id, nickname, "inject_fake_option", cleaned_payload, effect_round)
            :ets.delete(:truth_fake_locks, lock_key)
            {:ok, %{used: true, remaining_charges: get_truth_stats(player_id).charges}}
        end
    end
  end

  defp apply_inject_fake(room, player_id, nickname, payload) do
    fake_text = Map.get(payload, "fake_text", Map.get(payload, :fake_text, ""))
    complete_inject_fake(room.id, player_id, nickname, fake_text)
  end

  defp apply_standard(room, player_id, nickname, action, payload) do
    if action == "inject_fake_option" do
      {:error, "Use fake-option lock flow first"}
    else
      phase = current_truth_phase(room.id)
      cost = distortion_cost(action)
      stats = get_truth_stats(player_id)

      cond do
        stats.charges < cost ->
          {:error, "Not enough distortion power"}

        not DistortionRules.can_use?(room.id, player_id, action) ->
          {:error, DistortionRules.denial_reason(action)}

        true ->
          case validate_payload(action, payload, room, player_id) do
            {:error, reason} ->
              {:error, reason}

            {:ok, cleaned_payload} ->
              effect_round = distortion_effect_round(room, phase)

              DistortionRules.record_use!(room.id, player_id, action)

              update_truth_stats(player_id, fn s ->
                %{s | charges: max(0, s.charges - cost), di: s.di + cost * 10}
              end)

              persist_distortion(room, player_id, nickname, action, cleaned_payload, effect_round)

              {:ok,
               %{
                 used: true,
                 remaining_charges: get_truth_stats(player_id).charges
               }}
          end
      end
    end
  end

  defp persist_distortion(room, player_id, nickname, action, cleaned_payload, effect_round) do
    room_id = room.id

    if action == "inject_fake_option" do
      DistortionRules.record_use!(room_id, player_id, action)
    end

    :ets.insert(:truth_distortions, {room_id, effect_round, player_id, action, cleaned_payload})

    Game.create_event(room_id, "distortion_used", %{
      action: action,
      round: effect_round,
      payload: cleaned_payload
    }, player_id)

    log_payload = %{
      round: effect_round,
      player_id: player_id,
      nickname: nickname,
      action: action,
      payload: cleaned_payload,
      remaining_charges: get_truth_stats(player_id).charges
    }

    Endpoint.broadcast("game:#{room.code}", "distortion_used", log_payload)
    Endpoint.broadcast("display:#{room.code}", "display:distortion_used", log_payload)
    broadcast_truth_stats(room)
    :ok
  end

  defp broadcast_truth_stats(room) do
    stats_public =
      room.id
      |> Game.list_players()
      |> Enum.map(fn p ->
        s = get_truth_stats(p.id)
        %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges}
      end)

    Endpoint.broadcast("game:#{room.code}", "truth_stats_updated", %{stats: stats_public})
  end

  defp current_truth_phase(room_id) do
    case :ets.lookup(:truth_room_phase, room_id) do
      [{^room_id, %{phase: phase}}] when is_binary(phase) ->
        phase

      _ ->
        room = Game.get_room!(room_id)

        cond do
          :ets.lookup(:truth_last_results, {room_id, room.current_round}) != [] ->
            "results"

          :ets.lookup(:truth_round_data, {room_id, room.current_round}) != [] ->
            "answering"

          true ->
            nil
        end
    end
  end

  defp distortion_effect_round(room, "results"), do: min(room.current_round + 1, room.total_rounds)
  defp distortion_effect_round(room, _), do: room.current_round

  defp get_truth_stats(player_id) do
    case :ets.lookup(:truth_player_stats, player_id) do
      [{^player_id, stats}] ->
        stats

      [] ->
        defaults = %{tp: 0, di: 0, ps: 0, charges: 0}
        :ets.insert(:truth_player_stats, {player_id, defaults})
        defaults
    end
  end

  defp update_truth_stats(player_id, fun) do
    current = get_truth_stats(player_id)
    updated = fun.(current)
    :ets.insert(:truth_player_stats, {player_id, updated})
    updated
  end

  defp distortion_cost("remove_option"), do: 2
  defp distortion_cost("swap_category"), do: 2
  defp distortion_cost("force_blind"), do: 3
  defp distortion_cost("inject_fake_option"), do: 4
  defp distortion_cost("merge_realities"), do: 4
  defp distortion_cost(_), do: 99

  defp validate_payload("remove_option", payload, room, player_id) do
    target = Map.get(payload, "target_player_id", Map.get(payload, :target_player_id))
    room_player_ids = room.id |> Game.list_players() |> Enum.map(& &1.id)

    cond do
      not is_binary(target) or target == "" ->
        {:error, "Please select a target player"}

      target == player_id ->
        {:error, "Cannot target yourself with Remove option"}

      target not in room_player_ids ->
        {:error, "Target player is not in this room"}

      true ->
        {:ok, %{"target_player_id" => target}}
    end
  end

  defp validate_payload("inject_fake_option", payload, _room, _player_id) do
    raw = Map.get(payload, "fake_text", Map.get(payload, :fake_text, ""))
    txt = sanitize_fake_text(raw)

    cond do
      txt == "" ->
        {:error, "Please enter a fake answer"}

      String.length(txt) < 3 and not Regex.match?(~r/^\d+$/, txt) ->
        {:error, "Fake answer is too short (min 3 chars, or a number like 5)"}

      String.length(txt) > 60 ->
        {:error, "Fake answer is too long (max 60 chars)"}

      contains_prohibited_text?(txt) ->
        {:error, "That text is not allowed by room safety filter"}

      true ->
        {:ok, %{"fake_text" => txt}}
    end
  end

  defp validate_payload("force_blind", payload, room, player_id) do
    target = Map.get(payload, "target_player_id", Map.get(payload, :target_player_id))
    connected_ids = room.id |> Game.list_players() |> Enum.filter(& &1.connected) |> Enum.map(& &1.id)

    cond do
      not is_binary(target) or target == "" ->
        {:ok, %{"target_player_id" => "__all_others__"}}

      target == player_id ->
        {:error, "Cannot force-blind yourself"}

      target not in connected_ids ->
        {:error, "Target player is not connected"}

      true ->
        {:ok, %{"target_player_id" => target}}
    end
  end

  defp validate_payload("merge_realities", payload, room, _player_id) do
    if room.current_round >= room.total_rounds do
      {:error, "Merge realities has no effect on the final round"}
    else
      {:ok, payload}
    end
  end

  defp validate_payload(_action, payload, _room, _player_id), do: {:ok, payload}

  defp sanitize_fake_text(txt) when is_binary(txt) do
    txt
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp sanitize_fake_text(_), do: ""

  defp contains_prohibited_text?(txt) do
    lower = String.downcase(txt)

    banned = [
      "fuck",
      "fucking",
      "shit",
      "bitch",
      "asshole",
      "cunt",
      "dick",
      "nigger",
      "rape",
      "kill yourself",
      "suicide",
      "địt",
      "đụ",
      "đéo",
      "đĩ",
      "đĩ mẹ",
      "cặc",
      "lồn",
      "buồi",
      "óc chó"
    ]

    has_banned = Enum.any?(banned, &String.contains?(lower, &1))
    has_url = String.match?(lower, ~r/https?:\/\/|www\./)
    has_contact = String.match?(lower, ~r/\b\d{8,}\b|@/)
    has_sql = String.match?(lower, ~r/--|\/\*|\*\/|drop\s+table|select\s+\*/)

    has_banned or has_url or has_contact or has_sql
  end
end
