defmodule VnParty.TruthQuestionBank do
  @moduledoc false
  @letters ~w(A B C D E F G H I)

  def pools do
    %{
      "general" => general(),
      "weird_facts" => weird_facts(),
      "social_stats" => social_stats(),
      "science_lite" => science_lite(),
      "pop_culture" => pop_culture(),
      "history" => history(),
      "geography" => geography(),
      "food_culture" => food_culture(),
      "sports_lite" => sports_lite(),
      "technology" => technology()
    }
  end

  defp q(id, prompt, correct_idx, choices) do
    opts =
      choices
      |> Enum.take(9)
      |> Enum.with_index()
      |> Enum.map(fn {text, i} -> %{id: Enum.at(@letters, i), text: text} end)

    %{id: id, text: prompt, options: opts, correct: Enum.at(@letters, correct_idx)}
  end

  defp general do
    [
      q("tg1", "Quốc gia nào tiêu thụ cà phê bình quân đầu người nhiều nhất?", 0, [
        "Phần Lan",
        "Mỹ",
        "Brazil",
        "Nhật Bản",
        "Thụy Điển",
        "Na Uy",
        "Colombia",
        "Ethiopia",
        "Việt Nam"
      ]),
      q("tg2", "Bạch tuộc có bao nhiêu trái tim?", 2, [
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "0",
        "8",
        "10"
      ]),
      q("tg3", "Số nguyên tố nhỏ nhất là gì?", 2, [
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "7",
        "9",
        "11"
      ]),
      q("tg4", "Hành tinh nào được gọi là Hành tinh Đỏ?", 1, [
        "Sao Kim",
        "Sao Hỏa",
        "Sao Mộc",
        "Sao Thổ",
        "Sao Thủy",
        "Sao Hải Vương",
        "Sao Thiên Vương",
        "Sao Diêm Vương",
        "Trái Đất"
      ]),
      q("tg5", "Trái Đất có bao nhiêu châu lục (theo mô hình tiêu chuẩn)?", 2, [
        "5",
        "6",
        "7",
        "8",
        "4",
        "9",
        "3",
        "10",
        "12"
      ]),
      q("tg6", "Khí nào chiếm phần lớn bầu khí quyển Trái Đất?", 1, [
        "Oxy",
        "Nitơ",
        "Carbon Dioxide",
        "Argon",
        "Heli",
        "Hydro",
        "Metan",
        "Neon",
        "Hơi nước"
      ]),
      q("tg7", "Ký hiệu hóa học của vàng là gì?", 2, [
        "Go",
        "Gd",
        "Au",
        "Ag",
        "Fe",
        "Cu",
        "Pt",
        "Pb",
        "Al"
      ]),
      q("tg8", "Đại dương nào lớn nhất theo diện tích bề mặt?", 3, [
        "Đại Tây Dương",
        "Ấn Độ Dương",
        "Bắc Băng Dương",
        "Thái Bình Dương",
        "Nam Đại Dương",
        "Biển Địa Trung Hải",
        "Biển Caribe",
        "Biển Baltic",
        "Biển Caspi"
      ])
    ]
  end

  defp weird_facts do
    [
      q("tw1", "Khoảng bao nhiêu phần trăm người ngủ mang tất?", 2, [
        "10%",
        "20%",
        "30%",
        "40%",
        "50%",
        "5%",
        "15%",
        "25%",
        "35%"
      ]),
      q("tw2", "Mật ong không bao giờ hỏng vì có tính axit cao và độ ẩm thấp.", 1, [
        "Sai",
        "Đúng",
        "Chỉ ở khí hậu lạnh",
        "Chỉ mật ong tiệt trùng",
        "Sai với mật ong thô",
        "Chỉ trong 1 năm",
        "Chỉ trong lọ thủy tinh",
        "Tùy thuộc vào ong",
        "Chỉ mật ong hữu cơ"
      ]),
      q("tw3", "Một nhóm hồng hạc được gọi là gì?", 1, [
        "Nghị viện",
        "Lộng lẫy (Flamboyance)",
        "Triệu tập",
        "Quây quần",
        "Đàn",
        "Tổ",
        "Bầy ngỗng",
        "Đàn quạ",
        "Bầy"
      ]),
      q("tw4", "Chuối là quả mọng, nhưng dâu tây thì không (về mặt thực vật học).", 1, [
        "Sai",
        "Đúng",
        "Chỉ ở vùng nhiệt đới",
        "Chỉ loại hoang dã",
        "Chỉ loại hữu cơ",
        "Chỉ loại xanh",
        "Chỉ loại khô",
        "Chỉ loại lai",
        "Chỉ loại không hạt"
      ]),
      q("tw5", "Con người chia sẻ khoảng 60% DNA với chuối (theo khoa học phổ thông).", 1, [
        "0%",
        "Khoảng 60%",
        "99%",
        "10%",
        "25%",
        "80%",
        "100%",
        "5%",
        "40%"
      ]),
      q("tw6", "Một ngày trên Sao Kim dài hơn một năm trên Sao Kim.", 1, [
        "Sai",
        "Đúng",
        "Chỉ ở hai cực",
        "Chỉ vào mùa hè",
        "Chỉ trên quỹ đạo",
        "Chỉ trên bề mặt",
        "Chỉ trong khí quyển",
        "Chỉ đối với robot",
        "Chỉ trên lý thuyết"
      ]),
      q("tw7", "Phân của gấu túi wombat có hình khối vuông nổi tiếng.", 1, [
        "Sai",
        "Đúng",
        "Chỉ gấu con",
        "Chỉ trong vườn thú",
        "Chỉ vào mùa đông",
        "Chỉ con đực",
        "Chỉ con cái",
        "Chỉ vào ban đêm",
        "Chỉ ở sa mạc Úc"
      ]),
      q("tw8", "Cá mập đã tồn tại trước cả cây cối (theo trình tự địa chất).", 1, [
        "Sai",
        "Đúng",
        "Cùng thời kỳ",
        "Cây trước",
        "Chim trước",
        "Khủng long trước",
        "Con người trước",
        "Nấm trước",
        "Côn trùng trước"
      ])
    ]
  end

  defp social_stats do
    [
      q("ts1", "Ứng dụng mạng xã hội được sử dụng rộng rãi nhất toàn cầu?", 3, [
        "TikTok",
        "Instagram",
        "YouTube",
        "Facebook",
        "Twitter/X",
        "Snapchat",
        "LinkedIn",
        "Pinterest",
        "Reddit"
      ]),
      q("ts2", "Nhóm tuổi nào có thời gian sử dụng màn hình trung bình nhiều nhất mỗi ngày?", 1, [
        "13–17",
        "18–24",
        "35–44",
        "65+",
        "0–5",
        "6–12",
        "25–34",
        "45–54",
        "55–64"
      ]),
      q("ts3", "Tỷ lệ biết chữ của người trưởng thành trên thế giới xấp xỉ bao nhiêu?", 2, [
        "55%",
        "70%",
        "86%",
        "95%",
        "40%",
        "60%",
        "75%",
        "90%",
        "99%"
      ]),
      q("ts4", "Khoảng bao nhiêu phần trăm dân số thế giới sử dụng internet (ước tính ITU)?", 2, [
        "40%",
        "55%",
        "67%",
        "90%",
        "20%",
        "30%",
        "45%",
        "80%",
        "95%"
      ]),
      q("ts5", "Chỉ số nào thường được dùng để đo mức độ tương tác trên bài đăng?", 1, [
        "Độ trễ",
        "Tỷ lệ tương tác",
        "Băng thông",
        "Thời gian hoạt động",
        "Mất gói dữ liệu",
        "Sử dụng CPU",
        "Disk I/O",
        "Ping",
        "Hash rate"
      ]),
      q("ts6", "Thử nghiệm A/B trong nhóm sản phẩm chủ yếu được dùng để…", 0, [
        "So sánh hai phiên bản",
        "Xóa dữ liệu người dùng",
        "Mã hóa mật khẩu",
        "Vận chuyển phần cứng",
        "Thay thế máy chủ",
        "Cấm người dùng",
        "Đóng văn phòng",
        "In tài liệu",
        "Sửa máy in"
      ]),
      q("ts7", "Chỉ số Net Promoter Score (NPS) đo…", 0, [
        "Khả năng giới thiệu",
        "Nhiệt độ CPU",
        "Mất gói dữ liệu",
        "Độ phân giải màn hình",
        "Điện áp pin",
        "Tốc độ quạt",
        "RAM timing",
        "GPU shaders",
        "SSD wear"
      ]),
      q("ts8", "Trong khảo sát, thang đo Likert thường yêu cầu người trả lời…", 0, [
        "Đánh giá mức độ đồng ý",
        "Vẽ bản đồ",
        "Đo cân nặng",
        "Ghi nhịp tim",
        "Đếm bước chân",
        "Quét mã vạch",
        "Gõ code",
        "Tải video",
        "Chia sẻ mật khẩu"
      ])
    ]
  end

  defp science_lite do
    [
      q("tc1", "Cây cối chủ yếu hấp thụ khí gì cho quang hợp?", 2, [
        "Oxy",
        "Nitơ",
        "Carbon Dioxide",
        "Heli",
        "Hydro",
        "Metan",
        "Argon",
        "Neon",
        "Clo"
      ]),
      q("tc2", "Tốc độ ánh sáng trong chân không xấp xỉ bao nhiêu?", 2, [
        "300 km/s",
        "3.000 km/s",
        "300.000 km/s",
        "3 triệu km/s",
        "30 km/s",
        "30.000 km/s",
        "3 tỷ km/s",
        "300 m/s",
        "3.000 m/s"
      ]),
      q("tc3", "Nước sôi ở 100°C tại áp suất mực nước biển tiêu chuẩn.", 1, [
        "Sai",
        "Đúng",
        "Chỉ với nước muối",
        "Chỉ trên mực nước biển",
        "Chỉ vào mùa đông",
        "Chỉ trong chân không",
        "Chỉ trong nồi áp suất",
        "Chỉ vào ban đêm",
        "Chỉ trong phòng thí nghiệm"
      ]),
      q("tc4", "Hạt nào mang điện tích âm?", 2, [
        "Proton",
        "Neutron",
        "Electron",
        "Photon",
        "Quark (up)",
        "Neutrino",
        "Positron",
        "Muon+",
        "Hạt alpha"
      ]),
      q("tc5", "DNA viết tắt của…", 0, [
        "Axit deoxyribonucleic",
        "Axit hạt nhân động",
        "Mảng nitơ kép",
        "Nguyên tử nucleotide đặc",
        "Truy cập mạng số",
        "Axit nitric hai nguyên tử",
        "Thuật toán thần kinh dẫn xuất",
        "Bộ chuyển đổi nút trực tiếp",
        "Cơ quan tên phân tán"
      ]),
      q("tc6", "Bào quan nào là nhà máy năng lượng của tế bào?", 2, [
        "Nhân",
        "Ribosome",
        "Ti thể",
        "Golgi",
        "Lysosome",
        "Không bào",
        "Lục lạp",
        "Trung thể",
        "Thành tế bào"
      ]),
      q("tc7", "Âm thanh truyền nhanh nhất trong môi trường nào?", 2, [
        "Chân không",
        "Không khí",
        "Thép",
        "Nước",
        "Không gian",
        "Bóng bay heli",
        "Bông",
        "Xốp",
        "Cát"
      ]),
      q("tc8", "Độ pH của nước tinh khiết ở 25°C gần nhất với…", 2, [
        "0",
        "1",
        "7",
        "10",
        "14",
        "3",
        "5",
        "9",
        "12"
      ])
    ]
  end

  defp pop_culture do
    [
      q("tp1", "Thương hiệu nào có 'Jedi'?", 0, [
        "Star Wars",
        "Star Trek",
        "Dune",
        "Avatar",
        "Marvel",
        "Harry Potter",
        "Chúa Nhẫn",
        "Matrix",
        "Hunger Games"
      ]),
      q("tp2", "Ai viết tiểu thuyết '1984'?", 1, [
        "Huxley",
        "Orwell",
        "Bradbury",
        "Atwood",
        "Asimov",
        "Tolkien",
        "Rowling",
        "King",
        "Austen"
      ]),
      q("tp3", "Pac-Man là nhân vật từ kỷ nguyên game nào?", 0, [
        "Arcade thập niên 1970",
        "PC thập niên 1990",
        "Di động thập niên 2000",
        "VR thập niên 2010",
        "Console thập niên 1980",
        "Cloud thập niên 2020",
        "Mainframe thập niên 1960",
        "Pinball thập niên 1950",
        "Neural thập niên 2040"
      ]),
      q("tp4", "Ban nhạc nào phát hành album 'Abbey Road'?", 2, [
        "Rolling Stones",
        "Queen",
        "The Beatles",
        "Nirvana",
        "U2",
        "Coldplay",
        "BTS",
        "ABBA",
        "Metallica"
      ]),
      q("tp5", "Studio Ghibli gắn liền nhất với hoạt hình nước nào?", 2, [
        "Mỹ",
        "Pháp",
        "Nhật Bản",
        "Hàn Quốc",
        "Trung Quốc",
        "Anh",
        "Canada",
        "Ý",
        "Brazil"
      ]),
      q("tp6", "Nhân vật Mario xuất hiện lần đầu trong thể loại game nào?", 2, [
        "Đua xe",
        "Đối kháng",
        "Phiêu lưu hành động",
        "Giải đố",
        "Thể thao",
        "Âm nhạc",
        "Kinh dị",
        "Chiến lược",
        "Mô phỏng"
      ]),
      q("tp7", "Nền tảng streaming nào sản xuất 'Stranger Things'?", 1, [
        "Hulu",
        "Netflix",
        "Disney+",
        "HBO Max",
        "Amazon Prime",
        "Apple TV+",
        "Peacock",
        "Crunchyroll",
        "YouTube"
      ]),
      q("tp8", "Giải Oscar chủ yếu gắn liền với ngành nào?", 2, [
        "Âm nhạc",
        "Thể thao",
        "Điện ảnh",
        "Thời trang",
        "Ẩm thực",
        "Công nghệ",
        "Chỉ văn học",
        "Chỉ kịch nghệ",
        "Trò chơi điện tử"
      ])
    ]
  end

  defp history do
    [
      q("th1", "Thế chiến II kết thúc ở Châu Âu vào năm nào?", 2, [
        "1943",
        "1944",
        "1945",
        "1946",
        "1939",
        "1940",
        "1941",
        "1942",
        "1947"
      ]),
      q("th2", "Bức tường Berlin sụp đổ vào năm nào?", 1, [
        "1987",
        "1989",
        "1991",
        "1993",
        "1985",
        "1986",
        "1988",
        "1990",
        "1992"
      ]),
      q("th3", "Thế vận hội cổ đại bắt nguồn từ đâu?", 1, [
        "La Mã",
        "Hy Lạp",
        "Ai Cập",
        "Ba Tư",
        "Trung Quốc",
        "Ấn Độ",
        "Anh",
        "Maya",
        "Vùng đất Viking"
      ]),
      q("th4", "Cách mạng Pháp bắt đầu vào thế kỷ nào?", 2, [
        "16",
        "17",
        "18",
        "19",
        "20",
        "15",
        "14",
        "21",
        "12"
      ]),
      q("th5", "Ai là Tổng thống đầu tiên của Hoa Kỳ?", 1, [
        "Jefferson",
        "Washington",
        "Lincoln",
        "Adams",
        "Madison",
        "Monroe",
        "Jackson",
        "Roosevelt",
        "Kennedy"
      ]),
      q("th6", "Thủ đô chính của Đế chế La Mã là…", 1, [
        "Athens",
        "Rome",
        "Carthage",
        "Alexandria",
        "Paris",
        "London",
        "Chỉ Constantinople",
        "Jerusalem",
        "Venice"
      ]),
      q("th7", "Máy in được phổ biến ở Châu Âu bởi…", 2, [
        "Galileo",
        "Newton",
        "Gutenberg",
        "Darwin",
        "Copernicus",
        "Einstein",
        "Tesla",
        "Edison",
        "Curie"
      ]),
      q("th8", "Đại Hiến chương Magna Carta được ký ở quốc gia nào?", 2, [
        "Pháp",
        "Tây Ban Nha",
        "Anh",
        "Đức",
        "Ý",
        "Chỉ Scotland",
        "Ireland",
        "Bồ Đào Nha",
        "Hà Lan"
      ])
    ]
  end

  defp geography do
    [
      q("tgeo1", "Con sông dài nhất thế giới là gì (theo địa lý phổ thông)?", 1, [
        "Amazon",
        "Nile",
        "Dương Tử",
        "Mississippi",
        "Danube",
        "Rhine",
        "Thames",
        "Mekong",
        "Hằng Hà"
      ]),
      q("tgeo2", "Đỉnh Everest nằm trên biên giới Nepal và quốc gia nào?", 1, [
        "Ấn Độ",
        "Trung Quốc",
        "Bhutan",
        "Pakistan",
        "Bangladesh",
        "Myanmar",
        "Chỉ Tây Tạng (lịch sử)",
        "Afghanistan",
        "Lào"
      ]),
      q("tgeo3", "Châu lục nhỏ nhất là?", 1, [
        "Châu Âu",
        "Châu Úc",
        "Nam Cực",
        "Nam Mỹ",
        "Châu Phi",
        "Châu Á",
        "Bắc Mỹ",
        "Greenland",
        "Châu Đại Dương không phải châu lục"
      ]),
      q("tgeo4", "Quốc gia nào có diện tích đất lớn nhất?", 2, [
        "Mỹ",
        "Trung Quốc",
        "Nga",
        "Canada",
        "Brazil",
        "Úc",
        "Ấn Độ",
        "Argentina",
        "Kazakhstan"
      ]),
      q("tgeo5", "Sa mạc Sahara chủ yếu nằm ở châu lục nào?", 2, [
        "Châu Á",
        "Châu Âu",
        "Châu Phi",
        "Châu Úc",
        "Nam Mỹ",
        "Nam Cực",
        "Bắc Mỹ",
        "Châu Đại Dương",
        "Bắc Cực"
      ]),
      q("tgeo6", "Thành phố nào là thủ đô của Nhật Bản?", 2, [
        "Osaka",
        "Kyoto",
        "Tokyo",
        "Seoul",
        "Bắc Kinh",
        "Bangkok",
        "Manila",
        "Hà Nội",
        "Đài Bắc"
      ]),
      q("tgeo7", "Biển Chết thực chất là gì?", 2, [
        "Đại Tây Dương",
        "Thái Bình Dương",
        "Hồ muối nội địa",
        "Ấn Độ Dương",
        "Bắc Băng Dương",
        "Biển Caribe",
        "Biển Địa Trung Hải",
        "Biển Baltic",
        "Chỉ Biển Caspi"
      ]),
      q("tgeo8", "Quốc gia nào nằm ở cả Châu Âu và Châu Á (xuyên lục địa)?", 2, [
        "Ý",
        "Tây Ban Nha",
        "Thổ Nhĩ Kỳ",
        "Bồ Đào Nha",
        "Hy Lạp",
        "Ba Lan",
        "Thụy Điển",
        "Ireland",
        "Bỉ"
      ])
    ]
  end

  defp food_culture do
    [
      q("tf1", "Đậu nành lên men truyền thống của Nhật Bản gọi là gì?", 1, [
        "Miso",
        "Natto",
        "Tempeh",
        "Kimchi",
        "Đậu phụ",
        "Nước tương",
        "Edamame",
        "Sake",
        "Wasabi"
      ]),
      q("tf2", "Quốc gia nào sản xuất cà phê nhiều nhất?", 2, [
        "Việt Nam",
        "Colombia",
        "Brazil",
        "Ethiopia",
        "Indonesia",
        "Mỹ",
        "Ý",
        "Pháp",
        "Nhật Bản"
      ]),
      q("tf3", "Phở gắn liền nhất với ẩm thực nước nào?", 1, [
        "Thái Lan",
        "Việt Nam",
        "Trung Quốc",
        "Nhật Bản",
        "Hàn Quốc",
        "Lào",
        "Campuchia",
        "Malaysia",
        "Philippines"
      ]),
      q("tf4", "Sushi truyền thống sử dụng loại ngũ cốc chính nào?", 2, [
        "Lúa mì",
        "Ngô",
        "Gạo",
        "Lúa mạch",
        "Yến mạch",
        "Quinoa",
        "Lúa mạch đen",
        "Kê",
        "Kiều mạch"
      ]),
      q("tf5", "Loại phô mai Ý nào thường dùng trên pizza?", 2, [
        "Cheddar",
        "Brie",
        "Mozzarella",
        "Gouda",
        "Feta",
        "Phô mai Thụy Sĩ",
        "Blue Stilton",
        "Camembert",
        "Chỉ Parmesan cho tráng miệng"
      ]),
      q("tf6", "Rượu Champagne được đặt tên theo vùng nào ở quốc gia nào?", 2, [
        "Ý",
        "Tây Ban Nha",
        "Pháp",
        "Đức",
        "Mỹ",
        "Úc",
        "Chile",
        "Bồ Đào Nha",
        "Hy Lạp"
      ]),
      q("tf7", "Gia vị nào được chiết xuất từ vỏ cây khô?", 2, [
        "Tiêu",
        "Thì là",
        "Quế",
        "Nghệ",
        "Paprika",
        "Oregano",
        "Húng quế",
        "Cỏ xạ hương",
        "Chỉ nhục đậu khấu từ hạt"
      ]),
      q("tf8", "Matcha là dạng bột của loại đồ uống gì?", 2, [
        "Cà phê",
        "Ca cao",
        "Trà xanh",
        "Trà đen",
        "Bạc hà thảo mộc",
        "Rooibos",
        "Hỗn hợp gia vị Chai",
        "Espresso",
        "Chỉ Oolong"
      ])
    ]
  end

  defp sports_lite do
    [
      q("tsp1", "Mỗi đội bóng rổ có bao nhiêu cầu thủ trên sân?", 1, [
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "11",
        "12"
      ]),
      q("tsp2", "FIFA World Cup được tổ chức mỗi…", 2, [
        "2 năm",
        "3 năm",
        "4 năm",
        "5 năm",
        "1 năm",
        "6 năm",
        "8 năm",
        "10 năm",
        "12 năm"
      ]),
      q("tsp3", "Trong tennis, 'love' có nghĩa là…", 2, [
        "Lợi thế",
        "Hòa",
        "Không điểm",
        "Điểm trận",
        "Tie-break",
        "Lỗi",
        "Giao bóng ăn điểm",
        "Let",
        "Điểm set"
      ]),
      q("tsp4", "Cuộc đua marathon tiêu chuẩn dài bao nhiêu (xấp xỉ)?", 2, [
        "10 km",
        "21 km",
        "42 km",
        "50 km",
        "5 km",
        "100 km",
        "15 km",
        "30 km",
        "60 km"
      ]),
      q("tsp5", "Môn thể thao nào sử dụng quả bóng gỗ phẳng (puck)?", 2, [
        "Bóng đá",
        "Bóng rổ",
        "Khúc côn cầu trên băng",
        "Tennis",
        "Golf",
        "Cricket",
        "Bóng bầu dục",
        "Bóng chuyền",
        "Cầu lông"
      ]),
      q("tsp6", "Biểu tượng Olympic có bao nhiêu vòng tròn đan xen?", 3, [
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "12"
      ]),
      q("tsp7", "Trong bóng đá, hat-trick nghĩa là cầu thủ ghi…", 2, [
        "1 bàn",
        "2 bàn",
        "3 bàn",
        "4 bàn",
        "5 bàn",
        "Phản lưới nhà",
        "Chỉ phạt đền",
        "Chỉ đánh đầu",
        "Không bàn"
      ]),
      q("tsp8", "Quốc gia nào phát minh ra judo hiện đại?", 2, [
        "Trung Quốc",
        "Hàn Quốc",
        "Nhật Bản",
        "Brazil",
        "Mỹ",
        "Nga",
        "Pháp",
        "Anh",
        "Mông Cổ"
      ])
    ]
  end

  defp technology do
    [
      q("tt1", "HTTP viết tắt của…", 0, [
        "HyperText Transfer Protocol",
        "High Transfer Text Process",
        "Hosted Text Transmission Packet",
        "Hybrid Terminal Transport Program",
        "Hyperlink Table Transfer Program",
        "Host Text Tunnel Process",
        "High Traffic Transfer Port",
        "Hardware Test Transport Protocol",
        "Hash Token Transfer Package"
      ]),
      q("tt2", "Ai tạo ra nhân Linux?", 0, [
        "Torvalds (dự án cá nhân)",
        "Microsoft",
        "IBM",
        "Apple",
        "Google",
        "Intel",
        "Oracle",
        "Adobe",
        "SAP"
      ]),
      q("tt3", "CPU viết tắt của…", 0, [
        "Central Processing Unit",
        "Computer Personal Utility",
        "Core Program Utility",
        "Cached Processing Upper bus",
        "Central Power Unit",
        "Chip Protocol Utility",
        "Compute Process Upload",
        "Control Panel Unit",
        "Cluster Parallel Unit"
      ]),
      q("tt4", "Ngôn ngữ nào chạy trong trình duyệt cùng HTML/CSS?", 2, [
        "Python",
        "Java",
        "JavaScript",
        "C++",
        "Rust",
        "Go",
        "Swift",
        "Kotlin",
        "Ruby"
      ]),
      q("tt5", "RAM thường là…", 1, [
        "Bộ nhớ vĩnh viễn",
        "Bộ nhớ tạm thời",
        "Đĩa quang",
        "Băng từ",
        "Cáp mạng",
        "GPU shader",
        "Nguồn điện",
        "Quạt tản nhiệt",
        "Ốc vít bo mạch chủ"
      ]),
      q("tt6", "Git chủ yếu được dùng cho…", 2, [
        "Chỉnh sửa ảnh",
        "Phát video trực tuyến",
        "Quản lý phiên bản",
        "Lưu trữ email",
        "Định tuyến DNS",
        "In 3D",
        "Trộn nhạc",
        "Bảng tính",
        "Quét virus"
      ]),
      q("tt7", "HTTPS thêm lớp nào trên HTTP?", 2, [
        "FTP",
        "SMTP",
        "Mã hóa TLS/SSL",
        "ICMP",
        "ARP",
        "Chỉ UDP",
        "Telnet",
        "SNMP",
        "POP3"
      ]),
      q("tt8", "Tên miền trong URL được phân giải bằng…", 2, [
        "HTTP",
        "FTP",
        "DNS",
        "SMTP",
        "SSH",
        "HTML",
        "CSS",
        "JSON",
        "PNG"
      ])
    ]
  end
end
