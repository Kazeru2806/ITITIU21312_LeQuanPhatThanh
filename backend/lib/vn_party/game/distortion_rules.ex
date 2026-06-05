defmodule VnParty.Game.DistortionRules do
  @moduledoc """
  Per-game caps on distortion powers (thesis-defensible, anti-loophole).
  See `limits_for_ui/0` and `README_GAME_RULES.md` for numeric caps.
  """

  @max_remove_per_player 1
  @max_remove_total 8
  @max_swap_per_player 2
  @max_swap_per_room 4
  @max_force_blind_per_player 1
  @max_force_blind_per_room 3
  @max_fake_per_player 1
  @max_merge_per_game 1

  def limits_for_ui do
    %{
      remove_option: %{per_player: @max_remove_per_player, per_game_total: @max_remove_total},
      swap_category: %{per_player: @max_swap_per_player, per_game_total: @max_swap_per_room},
      force_blind: %{per_player: @max_force_blind_per_player, per_game_total: @max_force_blind_per_room},
      inject_fake_option: %{per_player: @max_fake_per_player},
      merge_realities: %{per_game_total: @max_merge_per_game}
    }
  end

  def can_use?(room_id, player_id, action) when is_binary(action) do
    case action do
      "remove_option" ->
        player_uses(room_id, player_id, action) < @max_remove_per_player and
          total_uses(room_id, action) < @max_remove_total

      "swap_category" ->
        player_uses(room_id, player_id, action) < @max_swap_per_player and
          total_uses(room_id, action) < @max_swap_per_room

      "force_blind" ->
        player_uses(room_id, player_id, action) < @max_force_blind_per_player and
          total_uses(room_id, action) < @max_force_blind_per_room

      "inject_fake_option" ->
        player_uses(room_id, player_id, action) < @max_fake_per_player

      "merge_realities" ->
        total_uses(room_id, action) < @max_merge_per_game

      _ ->
        false
    end
  end

  def record_use!(room_id, player_id, action) do
    player_key = {room_id, player_id, action}
    total_key = {room_id, :total, action}
    :ets.update_counter(:distortion_usage, player_key, 1, {player_key, 0})
    :ets.update_counter(:distortion_usage, total_key, 1, {total_key, 0})
    :ok
  end

  def clear_room(room_id) when is_binary(room_id) do
    :ets.match_delete(:distortion_usage, {room_id, :_, :_})
    :ets.match_delete(:distortion_usage, {room_id, :total, :_})
    :ok
  end

  defp player_uses(room_id, player_id, action) do
    case :ets.lookup(:distortion_usage, {room_id, player_id, action}) do
      [{_, n}] -> n
      _ -> 0
    end
  end

  defp total_uses(room_id, action) do
    case :ets.lookup(:distortion_usage, {room_id, :total, action}) do
      [{_, n}] -> n
      _ -> 0
    end
  end

  def denial_reason("remove_option") do
    "Remove option limit reached (max #{@max_remove_per_player} per player, #{@max_remove_total} per game for the room)"
  end

  def denial_reason("swap_category") do
    "Swap category limit reached (max #{@max_swap_per_player} per player, #{@max_swap_per_room} per room per game)"
  end

  def denial_reason("force_blind") do
    "Force blind limit reached (max #{@max_force_blind_per_player} per player, #{@max_force_blind_per_room} per room per game)"
  end

  def denial_reason(action), do: "Distortion limit reached for #{action}"
end
