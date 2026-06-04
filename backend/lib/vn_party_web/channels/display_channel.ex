defmodule VnPartyWeb.DisplayChannel do
  use VnPartyWeb, :channel
  alias VnParty.Game
  alias VnPartyWeb.Endpoint
  alias VnPartyWeb.GameChannel

  @impl true
  def join("display:" <> room_code, _params, socket) do
    case Game.get_room_by_code_with_players(room_code) do
      nil ->
        {:error, %{reason: "Room not found"}}

      room ->
        socket =
          socket
          |> assign(:room_id, room.id)
          |> assign(:room_code, room.code)

        game_state = get_game_state(room)
        mode = Game.room_mode(room)

        response =
          if room.state == "round_start" and room.current_round > 0 and mode != "truth_collapse" do
            question = generate_mock_question(room.current_round)
            Map.put(game_state, :current_question, question)
          else
            game_state
          end

        {:ok, response, socket}
    end
  end

  @impl true
  def handle_in("close_room", _payload, socket) do
    Game.close_room_session(socket.assigns.room_id)
    {:stop, :normal, assign(socket, :room_closed_intentionally, true)}
  end

  @impl true
  def handle_in("request_force_end", _payload, socket) do
    :ets.insert(:force_end_pending, {socket.assigns.room_id, System.system_time(:millisecond)})

    {:reply,
     {:ok,
      %{
        require_confirm: true,
        room_code: socket.assigns.room_code,
        message: "Type the room code to confirm ending the game."
      }}, socket}
  end

  @impl true
  def handle_in("confirm_force_end", %{"room_code" => code}, socket) do
    room_id = socket.assigns.room_id
    expected = String.upcase(socket.assigns.room_code || "")
    given = String.upcase(code || "")

    pending? =
      case :ets.lookup(:force_end_pending, room_id) do
        [{^room_id, _}] -> true
        _ -> false
      end

    cond do
      not pending? ->
        {:reply, {:error, %{reason: "Start by requesting end game first"}}, socket}

      given != expected ->
        {:reply, {:error, %{reason: "Room code does not match"}}, socket}

      true ->
        :ets.delete(:force_end_pending, room_id)

        case Game.end_game_early(room_id) do
          {:ok, result} ->
            display_payload = %{
              final_scores: result.final_scores,
              winner: result.winner,
              forced: true
            }

            player_payload = %{
              message: "The host ended the game. See the screen for final scores.",
              forced: true
            }

            Endpoint.broadcast("display:#{socket.assigns.room_code}", "display:game_ended", display_payload)
            Endpoint.broadcast("game:#{socket.assigns.room_code}", "game_ended", player_payload)

            {:reply, {:ok, %{game_ended: true}}, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: inspect(reason)}}, socket}
        end
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Room is closed only via explicit `close_room` push — not when the host TV
    # navigates lobby → game (which remounts the WebSocket).
    :ok
  end

  defp get_game_state(room) do
    players = Game.list_players(room.id)
    mode = Game.room_mode(room)

    %{
      room_code: room.code,
      mode: mode,
      state: room.state,
      current_round: room.current_round,
      total_rounds: room.total_rounds,
      players: format_players(players, mode),
      truth_resume: GameChannel.build_truth_resume(room)
    }
  end

  defp format_players(players, mode) do
    Enum.map(players, fn player ->
      truth = if mode == "truth_collapse", do: get_truth_stats(player.id), else: %{tp: 0, di: 0, ps: 0, charges: 0}

      %{
        id: player.id,
        nickname: player.nickname,
        score: player.score,
        connected: player.connected,
        is_host: player.is_host,
        status: if(player.connected, do: "online", else: "absent"),
        truth_points: truth.tp,
        distortion_impact: truth.di,
        prediction_score: truth.ps,
        distortion_charges: truth.charges
      }
    end)
  end

  defp get_truth_stats(player_id) do
    case :ets.lookup(:truth_player_stats, player_id) do
      [{^player_id, stats}] -> stats
      [] -> %{tp: 0, di: 0, ps: 0, charges: 0}
    end
  end

  defp generate_mock_question(round) do
    questions = [
      %{
        id: "q1",
        text: "Tết Nguyên Đán là ngày lễ quan trọng nhất trong năm của người Việt. Tết thường diễn ra vào tháng nào?",
        options: [
          %{id: "A", text: "Tháng 12 dương lịch"},
          %{id: "B", text: "Tháng 1 hoặc tháng 2 dương lịch"},
          %{id: "C", text: "Tháng 3 dương lịch"},
          %{id: "D", text: "Tháng 4 dương lịch"}
        ],
        correct: "B",
        time_limit: 15
      },
      %{
        id: "q2",
        text: "Món ăn nào sau đây là đặc sản nổi tiếng của Việt Nam?",
        options: [
          %{id: "A", text: "Phở"},
          %{id: "B", text: "Sushi"},
          %{id: "C", text: "Pizza"},
          %{id: "D", text: "Burger"}
        ],
        correct: "A",
        time_limit: 15
      },
      %{
        id: "q3",
        text: "Thủ đô hiện tại của Việt Nam là thành phố nào?",
        options: [
          %{id: "A", text: "TP. Hồ Chí Minh"},
          %{id: "B", text: "Hà Nội"},
          %{id: "C", text: "Đà Nẵng"},
          %{id: "D", text: "Huế"}
        ],
        correct: "B",
        time_limit: 15
      },
      %{
        id: "q4",
        text: "Hồ Hoàn Kiếm nằm ở thành phố nào?",
        options: [
          %{id: "A", text: "Hà Nội"},
          %{id: "B", text: "TP. Hồ Chí Minh"},
          %{id: "C", text: "Đà Nẵng"},
          %{id: "D", text: "Cần Thơ"}
        ],
        correct: "A",
        time_limit: 15
      },
      %{
        id: "q5",
        text: "Năm nào đánh dấu sự kiện Việt Nam thống nhất đất nước?",
        options: [
          %{id: "A", text: "1945"},
          %{id: "B", text: "1954"},
          %{id: "C", text: "1975"},
          %{id: "D", text: "1986"}
        ],
        correct: "C",
        time_limit: 15
      }
    ]

    index = rem(round - 1, length(questions))
    Enum.at(questions, index)
  end
end
