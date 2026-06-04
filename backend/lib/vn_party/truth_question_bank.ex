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
      q("tg1", "Which country consumes the most coffee per capita?", 0, [
        "Finland",
        "USA",
        "Brazil",
        "Japan",
        "Sweden",
        "Norway",
        "Colombia",
        "Ethiopia",
        "Vietnam"
      ]),
      q("tg2", "How many hearts does an octopus have?", 2, [
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
      q("tg3", "What is the smallest prime number?", 2, [
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
      q("tg4", "Which planet is known as the Red Planet?", 1, [
        "Venus",
        "Mars",
        "Jupiter",
        "Saturn",
        "Mercury",
        "Neptune",
        "Uranus",
        "Pluto",
        "Earth"
      ]),
      q("tg5", "How many continents are there on Earth (standard model)?", 2, [
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
      q("tg6", "Which gas makes up most of Earth's atmosphere?", 1, [
        "Oxygen",
        "Nitrogen",
        "Carbon Dioxide",
        "Argon",
        "Helium",
        "Hydrogen",
        "Methane",
        "Neon",
        "Water vapor"
      ]),
      q("tg7", "What is the chemical symbol for gold?", 2, [
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
      q("tg8", "Which ocean is the largest by surface area?", 3, [
        "Atlantic",
        "Indian",
        "Arctic",
        "Pacific",
        "Southern",
        "Mediterranean",
        "Caribbean",
        "Baltic",
        "Caspian"
      ])
    ]
  end

  defp weird_facts do
    [
      q("tw1", "Roughly what percentage of people sleep with socks on?", 2, [
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
      q("tw2", "Honey never spoils because it is highly acidic and low in moisture.", 1, [
        "Myth",
        "True",
        "Only in cold climates",
        "Only pasteurized honey",
        "False for raw honey",
        "Only for 1 year",
        "Only in glass jars",
        "Depends on bees",
        "Only organic honey"
      ]),
      q("tw3", "A group of flamingos is called a …", 1, [
        "Parliament",
        "Flamboyance",
        "Convocation",
        "Huddle",
        "Flock",
        "Colony",
        "Gaggle",
        "Murder",
        "Pack"
      ]),
      q("tw4", "Bananas are berries, but strawberries are not (botanically).", 1, [
        "False",
        "True",
        "Only in tropics",
        "Only wild types",
        "Only organic",
        "Only green ones",
        "Only dried",
        "Only hybrids",
        "Only seedless"
      ]),
      q("tw5", "Humans share about 60% of DNA with bananas (popular science claim).", 1, [
        "0%",
        "About 60%",
        "99%",
        "10%",
        "25%",
        "80%",
        "100%",
        "5%",
        "40%"
      ]),
      q("tw6", "A day on Venus is longer than a year on Venus.", 1, [
        "False",
        "True",
        "Only at the poles",
        "Only in summer",
        "Only in orbit",
        "Only on surface",
        "Only in atmosphere",
        "Only for robots",
        "Only in theory"
      ]),
      q("tw7", "Wombat poop is famously cube-shaped.", 1, [
        "Myth",
        "True",
        "Only babies",
        "Only in zoos",
        "Only in winter",
        "Only males",
        "Only females",
        "Only at night",
        "Only in Australia deserts"
      ]),
      q("tw8", "Sharks existed before trees (rough geological ordering).", 1, [
        "False",
        "True",
        "Same era",
        "Trees first",
        "Birds first",
        "Dinosaurs first",
        "Humans first",
        "Fungi first",
        "Insects first"
      ])
    ]
  end

  defp social_stats do
    [
      q("ts1", "Most used social app globally by breadth of users?", 3, [
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
      q("ts2", "Which age group reports the most daily screen time on average (typical surveys)?", 1, [
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
      q("ts3", "What is the approximate world literacy rate for adults?", 2, [
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
      q("ts4", "Roughly what share of the world uses the internet (ITU estimate)?", 2, [
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
      q("ts5", "Which metric is commonly used to measure audience engagement on posts?", 1, [
        "Latency",
        "Engagement rate",
        "Bandwidth",
        "Uptime",
        "Packet loss",
        "CPU usage",
        "Disk I/O",
        "Ping",
        "Hash rate"
      ]),
      q("ts6", "A/B testing in product teams is primarily used to…", 0, [
        "Compare two variants",
        "Delete user data",
        "Encrypt passwords",
        "Ship hardware",
        "Replace servers",
        "Ban users",
        "Close offices",
        "Print manuals",
        "Fix printers"
      ]),
      q("ts7", "Net Promoter Score (NPS) measures…", 0, [
        "Likelihood to recommend",
        "CPU temperature",
        "Packet loss",
        "Screen resolution",
        "Battery voltage",
        "Fan speed",
        "RAM timing",
        "GPU shaders",
        "SSD wear"
      ]),
      q("ts8", "In surveys, a Likert scale typically asks respondents to…", 0, [
        "Rate agreement on a scale",
        "Draw a map",
        "Measure weight",
        "Record heart rate",
        "Count steps",
        "Scan barcode",
        "Type code",
        "Upload video",
        "Share password"
      ])
    ]
  end

  defp science_lite do
    [
      q("tc1", "What gas do plants primarily absorb for photosynthesis?", 2, [
        "Oxygen",
        "Nitrogen",
        "Carbon Dioxide",
        "Helium",
        "Hydrogen",
        "Methane",
        "Argon",
        "Neon",
        "Chlorine"
      ]),
      q("tc2", "Speed of light in vacuum is approximately?", 2, [
        "300 km/s",
        "3,000 km/s",
        "300,000 km/s",
        "3 million km/s",
        "30 km/s",
        "30,000 km/s",
        "3 billion km/s",
        "300 m/s",
        "3,000 m/s"
      ]),
      q("tc3", "Water boils at 100°C at standard sea-level pressure.", 1, [
        "False",
        "True",
        "Only for salt water",
        "Only above sea level",
        "Only in winter",
        "Only in vacuum",
        "Only in pressure cooker",
        "Only at night",
        "Only in labs"
      ]),
      q("tc4", "Which particle has a negative electric charge?", 2, [
        "Proton",
        "Neutron",
        "Electron",
        "Photon",
        "Quark (up)",
        "Neutrino",
        "Positron",
        "Muon+",
        "Alpha particle"
      ]),
      q("tc5", "DNA stands for…", 0, [
        "Deoxyribonucleic acid",
        "Dynamic nuclear acid",
        "Dual nitrogen array",
        "Dense nucleotide atom",
        "Digital network access",
        "Diatomic nitric acid",
        "Derived neural algorithm",
        "Direct node adapter",
        "Distributed name authority"
      ]),
      q("tc6", "Which organelle is the powerhouse of the cell?", 2, [
        "Nucleus",
        "Ribosome",
        "Mitochondria",
        "Golgi",
        "Lysosome",
        "Vacuole",
        "Chloroplast",
        "Centriole",
        "Cell wall"
      ]),
      q("tc7", "Sound travels fastest in which medium?", 2, [
        "Vacuum",
        "Air",
        "Steel",
        "Water",
        "Space",
        "Helium balloon",
        "Cotton",
        "Foam",
        "Sand"
      ]),
      q("tc8", "The pH of pure water at 25°C is closest to…", 2, [
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
      q("tp1", "Which franchise features 'Jedi'?", 0, [
        "Star Wars",
        "Star Trek",
        "Dune",
        "Avatar",
        "Marvel",
        "Harry Potter",
        "Lord of the Rings",
        "Matrix",
        "Hunger Games"
      ]),
      q("tp2", "Who wrote the novel '1984'?", 1, [
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
      q("tp3", "Pac-Man is a character from which era of gaming?", 0, [
        "1970s arcade",
        "1990s PC",
        "2000s mobile",
        "2010s VR",
        "1980s console only",
        "2020s cloud",
        "1960s mainframe",
        "1950s pinball",
        "2040s neural"
      ]),
      q("tp4", "Which band released the album 'Abbey Road'?", 2, [
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
      q("tp5", "Studio Ghibli is most associated with which country's animation?", 2, [
        "USA",
        "France",
        "Japan",
        "Korea",
        "China",
        "UK",
        "Canada",
        "Italy",
        "Brazil"
      ]),
      q("tp6", "The character Mario first appeared in which type of game?", 2, [
        "Racing",
        "Fighting",
        "Platformer",
        "Puzzle",
        "Sports",
        "Rhythm",
        "Horror",
        "Strategy",
        "Simulation"
      ]),
      q("tp7", "Which streaming platform produced 'Stranger Things'?", 1, [
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
      q("tp8", "Oscar awards are primarily associated with which industry?", 2, [
        "Music",
        "Sports",
        "Film",
        "Fashion",
        "Food",
        "Tech",
        "Literature only",
        "Theater only",
        "Video games"
      ])
    ]
  end

  defp history do
    [
      q("th1", "World War II ended in Europe in which year?", 2, [
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
      q("th2", "The Berlin Wall fell in which year?", 1, [
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
      q("th3", "Ancient Olympic Games originated in?", 1, [
        "Rome",
        "Greece",
        "Egypt",
        "Persia",
        "China",
        "India",
        "Britain",
        "Maya",
        "Viking lands"
      ]),
      q("th4", "The French Revolution began in which century?", 2, [
        "16th",
        "17th",
        "18th",
        "19th",
        "20th",
        "15th",
        "14th",
        "21st",
        "12th"
      ]),
      q("th5", "Who was the first President of the United States?", 1, [
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
      q("th6", "The Roman Empire's capital was primarily…", 1, [
        "Athens",
        "Rome",
        "Carthage",
        "Alexandria",
        "Paris",
        "London",
        "Constantinople only always",
        "Jerusalem",
        "Venice"
      ]),
      q("th7", "The printing press was popularized in Europe by…", 2, [
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
      q("th8", "The Magna Carta was signed in which country?", 2, [
        "France",
        "Spain",
        "England",
        "Germany",
        "Italy",
        "Scotland only",
        "Ireland",
        "Portugal",
        "Netherlands"
      ])
    ]
  end

  defp geography do
    [
      q("tgeo1", "What is the longest river in the world (common geographic claim)?", 1, [
        "Amazon",
        "Nile",
        "Yangtze",
        "Mississippi",
        "Danube",
        "Rhine",
        "Thames",
        "Mekong",
        "Ganges"
      ]),
      q("tgeo2", "Mount Everest lies on the border of Nepal and which country?", 1, [
        "India",
        "China",
        "Bhutan",
        "Pakistan",
        "Bangladesh",
        "Myanmar",
        "Tibet only (historic)",
        "Afghanistan",
        "Laos"
      ]),
      q("tgeo3", "Which is the smallest continent?", 1, [
        "Europe",
        "Australia",
        "Antarctica",
        "South America",
        "Africa",
        "Asia",
        "North America",
        "Greenland",
        "Oceania is not a continent"
      ]),
      q("tgeo4", "Which country has the largest land area?", 2, [
        "USA",
        "China",
        "Russia",
        "Canada",
        "Brazil",
        "Australia",
        "India",
        "Argentina",
        "Kazakhstan"
      ]),
      q("tgeo5", "The Sahara is primarily located on which continent?", 2, [
        "Asia",
        "Europe",
        "Africa",
        "Australia",
        "South America",
        "Antarctica",
        "North America",
        "Oceania",
        "Arctic"
      ]),
      q("tgeo6", "Which city is the capital of Japan?", 2, [
        "Osaka",
        "Kyoto",
        "Tokyo",
        "Seoul",
        "Beijing",
        "Bangkok",
        "Manila",
        "Hanoi",
        "Taipei"
      ]),
      q("tgeo7", "Which sea is the Dead Sea?", 2, [
        "Atlantic",
        "Pacific",
        "Landlocked salt lake",
        "Indian Ocean",
        "Arctic Ocean",
        "Caribbean",
        "Mediterranean",
        "Baltic",
        "Caspian only"
      ]),
      q("tgeo8", "Which country is both in Europe and Asia (transcontinental)?", 2, [
        "Italy",
        "Spain",
        "Turkey",
        "Portugal",
        "Greece",
        "Poland",
        "Sweden",
        "Ireland",
        "Belgium"
      ])
    ]
  end

  defp food_culture do
    [
      q("tf1", "Traditional Japanese fermented soybeans are called?", 1, [
        "Miso",
        "Natto",
        "Tempeh",
        "Kimchi",
        "Tofu",
        "Soy sauce",
        "Edamame",
        "Sake",
        "Wasabi"
      ]),
      q("tf2", "Which country is the largest producer of coffee beans?", 2, [
        "Vietnam",
        "Colombia",
        "Brazil",
        "Ethiopia",
        "Indonesia",
        "USA",
        "Italy",
        "France",
        "Japan"
      ]),
      q("tf3", "Pho is most associated with the cuisine of?", 1, [
        "Thailand",
        "Vietnam",
        "China",
        "Japan",
        "Korea",
        "Laos",
        "Cambodia",
        "Malaysia",
        "Philippines"
      ]),
      q("tf4", "Sushi traditionally uses which staple grain?", 2, [
        "Wheat",
        "Corn",
        "Rice",
        "Barley",
        "Oats",
        "Quinoa",
        "Rye",
        "Millet",
        "Buckwheat"
      ]),
      q("tf5", "Which cheese is Italian and often used on pizza?", 2, [
        "Cheddar",
        "Brie",
        "Mozzarella",
        "Gouda",
        "Feta",
        "Swiss",
        "Blue Stilton",
        "Camembert",
        "Parmesan only for dessert"
      ]),
      q("tf6", "Champagne is named after a region in which country?", 2, [
        "Italy",
        "Spain",
        "France",
        "Germany",
        "USA",
        "Australia",
        "Chile",
        "Portugal",
        "Greece"
      ]),
      q("tf7", "Which spice is derived from dried bark?", 2, [
        "Pepper",
        "Cumin",
        "Cinnamon",
        "Turmeric",
        "Paprika",
        "Oregano",
        "Basil",
        "Thyme",
        "Nutmeg only from nut"
      ]),
      q("tf8", "Matcha is a powdered form of which drink base?", 2, [
        "Coffee",
        "Cocoa",
        "Green tea",
        "Black tea",
        "Herbal mint",
        "Rooibos",
        "Chai spice mix",
        "Espresso",
        "Oolong only"
      ])
    ]
  end

  defp sports_lite do
    [
      q("tsp1", "How many players per team are on the court in basketball?", 1, [
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
      q("tsp2", "The FIFA World Cup is held every …", 2, [
        "2 years",
        "3 years",
        "4 years",
        "5 years",
        "1 year",
        "6 years",
        "8 years",
        "10 years",
        "12 years"
      ]),
      q("tsp3", "Tennis scores use 'love' to mean …", 2, [
        "Advantage",
        "Deuce",
        "Zero",
        "Match point",
        "Tiebreak",
        "Fault",
        "Ace",
        "Let",
        "Set point"
      ]),
      q("tsp4", "How long is a standard marathon (approx.)?", 2, [
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
      q("tsp5", "Which sport uses a puck?", 2, [
        "Soccer",
        "Basketball",
        "Ice hockey",
        "Tennis",
        "Golf",
        "Cricket",
        "Rugby",
        "Volleyball",
        "Badminton"
      ]),
      q("tsp6", "The Olympics symbol has how many interlocking rings?", 3, [
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
      q("tsp7", "In soccer, a hat-trick means a player scored …", 2, [
        "1 goal",
        "2 goals",
        "3 goals",
        "4 goals",
        "5 goals",
        "An own goal",
        "A penalty only",
        "A header only",
        "No goals"
      ]),
      q("tsp8", "Which country invented modern judo?", 2, [
        "China",
        "Korea",
        "Japan",
        "Brazil",
        "USA",
        "Russia",
        "France",
        "UK",
        "Mongolia"
      ])
    ]
  end

  defp technology do
    [
      q("tt1", "HTTP stands for …", 0, [
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
      q("tt2", "Which company created the Linux kernel?", 0, [
        "Torvalds (personal project)",
        "Microsoft",
        "IBM",
        "Apple",
        "Google",
        "Intel",
        "Oracle",
        "Adobe",
        "SAP"
      ]),
      q("tt3", "What does CPU stand for?", 0, [
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
      q("tt4", "Which language runs in the browser alongside HTML/CSS?", 2, [
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
      q("tt5", "RAM is generally …", 1, [
        "Permanent storage",
        "Volatile memory",
        "Optical disk",
        "Magnetic tape",
        "Network cable",
        "GPU shader",
        "Power supply",
        "Cooling fan",
        "Motherboard screw"
      ]),
      q("tt6", "Git is primarily used for …", 2, [
        "Image editing",
        "Video streaming",
        "Version control",
        "Email hosting",
        "DNS routing",
        "3D printing",
        "Music mixing",
        "Spreadsheets",
        "Antivirus scans"
      ]),
      q("tt7", "HTTPS adds which layer on top of HTTP?", 2, [
        "FTP",
        "SMTP",
        "TLS/SSL encryption",
        "ICMP",
        "ARP",
        "UDP only",
        "Telnet",
        "SNMP",
        "POP3"
      ]),
      q("tt8", "A URL's domain name is resolved using …", 2, [
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
