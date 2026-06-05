defmodule VnParty.TruthDistortionApply do
  @moduledoc false

  alias VnParty.{FakeInject, Game}

  @type effects :: %{
          blind_targets: MapSet.t(),
          log: list(),
          category_timeline: list(),
          remove_count: non_neg_integer(),
          force_blind_count: non_neg_integer(),
          remove_targets: %{optional(String.t()) => list(String.t())},
          fake_entries: list(),
          injected_option_ids: list(String.t())
        }

  @doc """
  Applies stored truth distortions for `round` onto `base_question`.
  Reads from `:truth_distortions` ETS (bag table keyed by room_id).
  """
  @spec apply_for_round(String.t(), pos_integer(), map(), keyword()) :: {map(), effects()}
  def apply_for_round(room_id, round, question, opts \\ []) do
    swap_fn = Keyword.fetch!(opts, :swap_fn)
    category_picker = Keyword.fetch!(opts, :category_picker)
    di_fn = Keyword.get(opts, :di_fn, &default_di/1)

    distortions_raw =
      :ets.lookup(:truth_distortions, room_id)
      |> Enum.flat_map(fn
        {^room_id, ^round, pid, action, payload} ->
          [%{round: round, player_id: pid, action: action, payload: payload, di: di_fn.(pid)}]

        _ ->
          []
      end)

    player_ids =
      case Keyword.get(opts, :connected_player_ids) do
        ids when is_list(ids) ->
          ids

        _ ->
          room_id
          |> Game.list_players()
          |> Enum.filter(& &1.connected)
          |> Enum.map(& &1.id)
      end

    ordered =
      distortions_raw
      |> Enum.sort_by(fn d -> {-d.di, :rand.uniform(10_000)} end)

    initial_category = Map.get(question, :category)

    acc_init = %{
      q: question,
      timeline: if(initial_category, do: [initial_category], else: []),
      log: [],
      remove_count: 0,
      force_blind_entries: [],
      remove_entries: [],
      fake_entries: []
    }

    acc =
      Enum.reduce(ordered, acc_init, fn d, a ->
        case d.action do
          "swap_category" ->
            requested = Map.get(d.payload, "category", Map.get(d.payload, :category))
            cat = category_picker.(a.q, requested)
            new_q = swap_fn.(room_id, round, cat, :random)

            entry = %{
              player_id: d.player_id,
              action: d.action,
              category: cat,
              category_label: truth_category_label(cat)
            }

            %{a | q: new_q, timeline: a.timeline ++ [cat], log: a.log ++ [entry]}

          "remove_option" ->
            target = Map.get(d.payload, "target_player_id", Map.get(d.payload, :target_player_id))
            entry = %{player_id: d.player_id, action: d.action, target_player_id: target}
            %{a | remove_count: a.remove_count + 1, remove_entries: a.remove_entries ++ [entry], log: a.log ++ [entry]}

          "force_blind" ->
            target = Map.get(d.payload, "target_player_id", Map.get(d.payload, :target_player_id))

            entry = %{
              player_id: d.player_id,
              action: d.action,
              target_player_id: target
            }

            %{a | force_blind_entries: a.force_blind_entries ++ [entry], log: a.log ++ [entry]}

          "inject_fake_option" ->
            fake_text = Map.get(d.payload, "fake_text", Map.get(d.payload, :fake_text))
            entry = %{player_id: d.player_id, action: d.action, fake_text: fake_text}
            %{a | fake_entries: a.fake_entries ++ [entry], log: a.log ++ [entry]}

          "merge_realities" ->
            %{a | log: a.log ++ [%{player_id: d.player_id, action: d.action}]}

          _ ->
            %{a | log: a.log ++ [%{player_id: d.player_id, action: d.action}]}
        end
      end)

    blind_targets = build_blind_targets(acc.force_blind_entries, player_ids)
    {q3, effects} = finalize_question(acc, blind_targets, player_ids)
    {q3, effects}
  end

  defp build_blind_targets(force_blind_entries, player_ids) do
    if length(force_blind_entries) >= 2 do
      MapSet.new(player_ids)
    else
      Enum.reduce(force_blind_entries, MapSet.new(), fn %{player_id: source_id, target_player_id: t}, ms ->
        cond do
          t == "__all_others__" ->
            Enum.reduce(player_ids, ms, fn pid, acc_ms ->
              if pid != source_id, do: MapSet.put(acc_ms, pid), else: acc_ms
            end)

          is_binary(t) and t != "" ->
            MapSet.put(ms, t)

          true ->
            ms
        end
      end)
    end
  end

  defp finalize_question(acc, blind_targets, player_ids) do
    q1 = acc.q

    correct_ids =
      case Map.get(q1, :correct) do
        ids when is_list(ids) -> MapSet.new(ids)
        id when is_binary(id) -> MapSet.new([id])
        _ -> MapSet.new()
      end

    incorrect_ids =
      q1.options
      |> Enum.map(& &1.id)
      |> Enum.reject(&MapSet.member?(correct_ids, &1))

    # Per-target only: each remove_option hides one wrong letter for that player.
    # Multiple attackers may target the same victim; the correct option is never hidden.
    remove_targets =
      Enum.reduce(acc.remove_entries, %{}, fn %{target_player_id: t}, m ->
        if is_binary(t) and t != "" and t in player_ids and incorrect_ids != [] do
          current = Map.get(m, t, MapSet.new())
          available = Enum.reject(incorrect_ids, &MapSet.member?(current, &1))

          next_set =
            case available do
              [] ->
                current

              opts ->
                MapSet.put(current, Enum.at(opts, :rand.uniform(length(opts)) - 1))
            end

          Map.put(m, t, next_set)
        else
          m
        end
      end)

    {q3, fake_entries_applied, injected_ids} =
      Enum.reduce(acc.fake_entries, {q1, [], MapSet.new()}, fn e, {q_acc, applied, used_ids} ->
        victim = FakeInject.pick_victim(q_acc, e.fake_text, used_ids)

        case victim do
          nil ->
            {q_acc, applied, used_ids}

          %{id: vid} ->
            opts =
              Enum.map(q_acc.options, fn o ->
                if o.id == vid, do: %{o | text: e.fake_text}, else: o
              end)

            entry =
              e
              |> Map.put(:option_id, vid)
              |> Map.put(:display_text, e.fake_text)

            {%{q_acc | options: opts}, applied ++ [entry], MapSet.put(used_ids, vid)}
        end
      end)

    injected_ids = MapSet.to_list(injected_ids)
    q3 = if injected_ids == [], do: q3, else: Map.put(q3, :injected_option_ids, injected_ids)

    effects = %{
      blind_targets: blind_targets,
      log: acc.log,
      category_timeline: acc.timeline,
      remove_count: acc.remove_count,
      force_blind_count: length(acc.force_blind_entries),
      remove_targets: Enum.into(remove_targets, %{}, fn {k, ms} -> {k, MapSet.to_list(ms)} end),
      fake_entries: fake_entries_applied,
      injected_option_ids: injected_ids
    }

    {q3, effects}
  end

  defp default_di(player_id) do
    case :ets.lookup(:truth_player_stats, player_id) do
      [{^player_id, %{di: di}}] -> di
      _ -> 0
    end
  end

  defp truth_category_label("general"), do: "General"
  defp truth_category_label("weird_facts"), do: "Weird Facts"
  defp truth_category_label("social_stats"), do: "Social & Stats"
  defp truth_category_label("science_lite"), do: "Science (Lite)"
  defp truth_category_label("pop_culture"), do: "Pop Culture"
  defp truth_category_label("history"), do: "History"
  defp truth_category_label("geography"), do: "Geography"
  defp truth_category_label("food_culture"), do: "Food & Culture"
  defp truth_category_label("sports_lite"), do: "Sports (Lite)"
  defp truth_category_label("technology"), do: "Technology"
  defp truth_category_label(other) when is_binary(other),
    do: other |> String.replace("_", " ") |> String.capitalize()

  defp truth_category_label(_), do: "Unknown"
end
