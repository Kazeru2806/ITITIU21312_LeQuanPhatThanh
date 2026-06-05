defmodule VnParty.FakeInject do
  @moduledoc false

  @doc """
  Picks which option letter to hijack for an inject-fake distortion.
  Prefers an existing option whose text already matches the fake text
  (including the correct answer), so picks on that letter credit the injector.
  """
  def pick_victim(question, fake_text, used_ids \\ MapSet.new()) do
    norm_fake = normalize_text(fake_text)

    text_match =
      Enum.find(Map.get(question, :options, []), fn o ->
        normalize_text(o.text) == norm_fake and not MapSet.member?(used_ids, o.id)
      end)

    if text_match do
      text_match
    else
      correct_ids =
        case Map.get(question, :correct) do
          list when is_list(list) -> list
          id when is_binary(id) -> [id]
          _ -> []
        end

      wrongs =
        question.options
        |> Enum.filter(fn o -> o.id not in correct_ids and not MapSet.member?(used_ids, o.id) end)

      case wrongs do
        [] -> nil
        list -> Enum.at(list, :rand.uniform(length(list)) - 1)
      end
    end
  end

  defp normalize_text(text) when is_binary(text), do: text |> String.trim() |> String.downcase()
  defp normalize_text(_), do: ""
end
