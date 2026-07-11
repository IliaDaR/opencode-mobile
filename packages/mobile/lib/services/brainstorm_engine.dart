import "dart:math" as math;
import "package:http/http.dart" as http;
import "dart:convert";

/// 88 generative manipulation engines for creative ideation.
/// Each applies a real algorithmic transformation to the problem text.
class BrainstormEngine {
  static final _rand = math.Random();

  static String get prompt => "You are in creative ideation mode. Apply lateral thinking, SCAMPER, oblique strategies, and cross-domain analogies. Break conventional patterns. Prioritize novel combinations over incremental improvements. Every idea must be unexpected."; 

  static String manipulate(String problem, int index) {
    final engines = _engines;
    if (index < 0 || index >= engines.length) {
      return engines[0](problem);
    }
    return engines[index](problem);
  }

  static List<String> generateIdeas(String problem) {
    return _engines.map((fn) => fn(problem)).toList();
  }

  static List<String> generateAll(String problem) => generateIdeas(problem);

  static List<String> pickRandom(String problem, int count) {
    final indices = List.generate(_engines.length, (i) => i)..shuffle();
    return indices.take(count).map((i) => _engines[i](problem)).toList();
  }

  // ─── Random vocab pools ─────────────────────────────────────────

  static final _domains = [
    "biology", "music", "architecture", "cooking", "military",
    "sports", "gaming", "finance", "space", "oceanography",
    "psychology", "linguistics", "chess", "origami", "quantum_physics",
    "gardening", "blacksmithing", "navigation", "alchemy", "weaving",
    "baking", "archery", "beekeeping", "cartography", "pottery",
  ];

  static final _adjectives = [
    "invisible", "liquid", "fractal", "frozen", "elastic",
    "hollow", "transparent", "living", "sleeping", "floating",
    "crystalline", "magnetic", "orbital", "autophagic", "elastic",
    "molten", "gaseous", "woven", "blooming", "fading",
    "recursive", "swarming", "anchored", "leaping", "shifting",
  ];

  static final _nouns = [
    "garden", "mirror", "river", "library", "bazaar",
    "cathedral", "spiral", "network", "swarm", "clock",
    "labyrinth", "bridge", "market", "engine", "crystal",
    "forge", "tide", "storm", "seed", "membrane",
    "lantern", "fountain", "telescope", "compass", "loom",
  ];

  static final _eras = [
    "1995 — dial-up internet, no smartphones, no cloud",
    "2050 — AI is 100x smarter than humans, energy is free",
    "1920 — no computers, no electricity in half the world",
    "Ancient Rome — no technology, but a vast empire",
    "Stone Age — only fire, stone tools, and cave walls",
    "Victorian Era — steam power, telegraph, strict social rules",
    "Feudal Japan — swords, honor, and isolation",
    "Year 3000 — quantum internet, nanobots, space colonies",
    "Bronze Age — first cities, writing is brand new",
    "Renaissance — printing press, scientific revolution begins",
    "1980s — arcades, analog, cold war, no world wide web",
    "Paleolithic — nomadic tribes, oral tradition only",
  ];

  static final _users = [
    "A blind octogenarian with 3 seconds of patience",
    "A genius 4-year-old with adult vocabulary but zero context",
    "A cyborg who can process at 10x human speed but has no emotions",
    "A Luddite who has never touched a screen",
    "A power user who wants 1000 features and CLI access",
    "A monk who wants absolute silence and zero cognitive load",
    "A panicked user in an emergency — fine motor skills gone",
    "A billionaire who will pay anything but demands perfection",
    "A 7-year-old with a tablet and zero reading ability",
    "A 90-year-old with cataracts and arthritis",
    "A deaf-blind user who communicates via touch only",
    "A hyper-distracted teenager with a 2-second attention span",
    "An alien who just arrived on Earth and understands nothing",
  ];

  static final _constraints = [
    "No text allowed — zero words, zero code",
    "Only works for left-handed people on Tuesdays",
    "Powered exclusively by potatoes",
    "Must be built from a single sheet of paper",
    "Only uses the digit 0 — no other characters",
    "Must function in complete darkness, silence, and vacuum",
    "User can only blink — no other input",
    "Everything must be explained by a 3-year-old",
    "Runs on a tamagotchi battery — 72 hours, no recharge",
    "ALL code is written by randomly mashing keyboard",
    "No moving parts. Zero mechanical or electronic motion.",
    "Must work without electricity, batteries, or any power source",
    "Only one button. ONE. You choose what it does.",
    "User can never see the same screen twice",
    "All interactions happen in 5 seconds or less — total",
    "Everything is done through a single text message",
    "No screens, no audio, no vibration — zero feedback channels",
    "Must obey all laws of a fictional universe (choose one)",
  ];

  static final _industries = [
    "fast food (McDonald's kitchen efficiency)",
    "space (NASA's failure-tolerant engineering)",
    "gaming (Fortnite's engagement loops)",
    "finance (high-frequency trading algorithms)",
    "biology (ant colony optimization)",
    "music (Spotify's recommendation engine)",
    "logistics (Amazon's warehouse robotics)",
    "dating (Tinder's friction-free matching)",
    "aerospace (Boeing's modular assembly)",
    "film (Disney's storytelling mechanics)",
    "agriculture (permaculture closed-loop design)",
    "education (Montessori self-directed learning)",
    "military (helicopter pilot checklists under fire)",
    "sports (Michael Phelps' deliberate practice regime)",
    "religion (ritual design for habit formation)",
    "theatre (improvisational 'yes and' rules)",
    "circus (rehearsal with no safety net mentality)",
    "publishing (serendipitous discovery in bookstores)",
  ];

  static final _paradoxes = [
    "Faster AND cheaper AND higher quality — all three",
    "More features AND simpler to use",
    "More secure AND more accessible",
    "Cheaper for users AND more profitable for you",
    "Works offline AND has real-time collaboration",
    "Massively personalized AND completely private",
    "Zero learning curve AND infinitely powerful",
    "Completely open AND perfectly safe from abuse",
    "Handles every edge case AND ships next week",
    "Works everywhere AND is deeply integrated",
  ];

  static final _biomimicry = [
    "Slime mold: optimizes networks without a brain — decentralized routing",
    "Ant colony: stigmergy — simple rules produce complex results",
    "Neuron: sparse activation, massive parallel processing",
    "Immune system: distributed detection, memory cells, adaptive response",
    "Mycelium: underground networks that connect, communicate, trade",
    "Evolution: mutation, selection, crossover — billion-year optimization",
    "Bee swarm: consensus without leadership, collective intelligence",
    "Coral reef: ecosystem of mutual benefit, recycling waste as resource",
    "Octopus: distributed intelligence — each arm has its own brain",
    "Bird flock: local rules produce global coherence",
    "Tree root network: resource sharing, colony-level resilience",
    "Firefly synchronization: emergent timing from simple coupling",
    "Slime mold: shortest path without centralized planning",
    "Leaf vein: fractal distribution for optimal transport",
    "Spider web: structural monitoring via tension feedback",
  ];

  static final _shocks = [
    "Server crashes every day",
    "Hackers attack constantly",
    "99% of users leave every month",
    "Budget cut by 90%",
    "Regulation makes your core feature illegal",
    "Your best employee gets hired by competitor",
    "All existing users delete their accounts",
    "A new technology makes your stack obsolete",
    "A global pandemic halves the market overnight",
    "A competitor launches your exact product for free",
    "Your main revenue stream is outlawed",
    "Every feature must work without internet — forever",
  ];

  static final _oblique = [
    "Use an unacceptable color. Now rationalize it.",
    "What would your GRANDPARENTS think? Now do the opposite.",
    "Steal the structure of a haiku. Apply it.",
    "What if the medium IS the message? McLuhan the problem.",
    "Replace every noun with a different random noun. Find meaning.",
    "What does 'done' look like? Not done — DONE. Truly finished.",
    "If this were a religion, what would the rituals be?",
    "Remove the most important feature. What fills the void?",
    "What if your user is an AI, not a human?",
    "Design for the smell. How does it feel to hold?",
    "What's the secret that everyone in the industry knows but no one says?",
    "Imagine the product is a person. Describe their personality. Now break it.",
    "What would this look like in a dream? Illogical but feels right.",
    "Translate the problem into binary. Solve in binary. Translate back.",
    "What if the product had to teach you something?",
  ];

  static final _catastrophes = [
    "Make every user cry in frustration",
    "Destroy all data every 5 minutes",
    "Charge \$10,000 per click",
    "Require a PhD in cryptography to open",
    "Randomly delete features every day",
    "Only works on a ZX Spectrum from 1982",
    "Bursts into flames if you make a typo",
    "Sends a love letter to your ex every time you log in",
    "Requires a blood sacrifice to start",
    "Plays Nickelback on infinite loop until task is done",
    "Sends all your data to a random stranger every hour",
    "Works perfectly EXCEPT on the day you need it most",
  ];

  static final _scales = [
    "Time: solve in 10 seconds vs 10 years",
    "Users: 1 user vs 1 billion users",
    "Cost: zero budget vs unlimited budget",
    "Team: 1 person vs 10,000 people",
    "Data: zero data vs infinite data",
    "Complexity: kindergarten vs PhD level",
    "Speed: instant vs glacial",
    "Scope: one molehill vs Mount Everest",
    "Reliability: works 1% of the time vs 99.99999%",
    "Latency: 10-year delay vs 1 microsecond",
  ];

  static final _mashupNouns = [
    "pressure cooker", "mousetrap", "kaleidoscope", "pendulum",
    "periscope", "accordion", "seesaw", "gyroscope",
    "trampoline", "amusement park", "submarine", "windmill",
    "trapeze", "pinball machine", "jukebox", "vending machine",
    "elevator", "escalator", "conveyor belt", "roulette wheel",
    "treadmill", "jigsaw puzzle", "rubik's cube", "theremin",
  ];

  static final _emotions = [
    "pure joy", "quiet satisfaction", "awe and wonder",
    "relief from anxiety", "deep curiosity", "triumph over adversity",
    "serene calm", "playful delight", "pride of mastery",
    "gratitude", "childlike excitement", "melancholic beauty",
    "surprise of discovery", "feeling understood", "cathartic release",
  ];

  static final _patterns = [
    "chain", "star", "mesh", "ring", "tree",
    "hub-and-spoke", "peer-to-peer", "layered", "spiral", "fractal",
    "diamond", "ladder", "web", "mosaic", "circuit",
    "bubble", "cascade", "ripple", "wave", "pulse",
  ];

  // ─── 88 engines ─────────────────────────────────────────────────

  static List<String Function(String)> get _engines => [

    // 1
    (p) {
      final sentences = p.split(RegExp(r'(?<=[.!?])\s+'));
      final flipped = sentences.map((s) {
        if (s.contains("should")) return s.replaceAll("should", "should NOT");
        if (s.contains("need")) return s.replaceAll("need", "must avoid");
        if (s.contains("problem")) return s.replaceAll("problem", "solution");
        if (s.contains("difficult")) return s.replaceAll("difficult", "trivial");
        if (s.contains("users")) return s.replaceAll("users", "non-users");
        return "Reverse: ${s.split(' ').reversed.join(' ')}";
      }).join(" ");
      return "**INVERSION** — Flip every assumption\n\nOriginal: $p\n\nFlipped: $flipped\n\nWhat anti-solution emerges when you do the exact opposite of what's expected?";
    },

    // 2
    (p) {
      final domain = _domains[_rand.nextInt(_domains.length)];
      return "**ANALOGY_BORROW** — How $domain solves this\n\nReframe: Instead of $p, imagine this were a problem in $domain.\n\nWhat mechanisms from $domain map to this space? What $domain principles violate your current assumptions?";
    },

    // 3
    (p) {
      final pair = _scales[_rand.nextInt(_scales.length)];
      return "**EXTREME_SCALING** — $pair\n\nProblem: $p\n\nDesign two versions: one for the minimum extreme, one for the maximum extreme. What convergences appear at both poles?";
    },

    // 4
    (p) {
      final constraint = _constraints[_rand.nextInt(_constraints.length)];
      return "**CONSTRAINT_INJECTION** — $constraint\n\nProblem: $p\n\nSolve under this constraint. What creative workaround becomes the core innovation?";
    },

    // 5
    (p) {
      final adj = _adjectives[_rand.nextInt(_adjectives.length)];
      final noun = _nouns[_rand.nextInt(_nouns.length)];
      return "**COMBINATION** — Merge with $adj $noun\n\nProblem: $p\n\nHow does a $adj $noun work? What $adj $noun principles apply to $p?\n\nForce a connection. What emerges at the intersection?";
    },

    // 6
    (p) {
      final worst = _catastrophes[_rand.nextInt(_catastrophes.length)];
      return "**WORST_IDEA** — Anti-pattern: $worst\n\nProblem: $p\n\nDesign the ABSOLUTE WORST solution. Make it maximally painful.\n\nNow invert every property: what's the opposite of each terrible decision? That's your brilliant insight.";
    },

    // 7
    (p) {
      return "**FIRST_PRINCIPLES** — Strip to fundamentals\n\nProblem: $p\n\n1. What are the TRUEST statements? (Things you KNOW, not assume)\n2. Decompose into irreducible components:\n   - Actors: who/what participates?\n   - Actions: what MUST happen?\n   - Constraints: what CANNOT change?\n3. Rebuild from zero: if you had no legacy, no existing solutions, no habits — what structure emerges?";
    },

    // 8
    (p) {
      final era = _eras[_rand.nextInt(_eras.length)];
      return "**TIME_TRAVEL** — Transport to $era\n\nProblem: $p\n\nHow would people in that era solve this with their tools, knowledge, and constraints? What would they invent that we're too blind to see?";
    },

    // 9
    (p) {
      final user = _users[_rand.nextInt(_users.length)];
      return "**USER_EXTREME** — Design for $user\n\nProblem: $p\n\nDesign SPECIFICALLY for this user. Their needs are extreme and unforgiving.\n\nNow: what feature that helps THEM would also help everyone?";
    },

    // 10
    (p) {
      return "**MORPHOLOGICAL_MATRIX** — Systematic permutations\n\nProblem: $p\n\nIdentify 3 orthogonal dimensions of the problem:\n  A: ___ (e.g., distribution: centralized / decentralized / peer-to-peer)\n  B: ___ (e.g., timing: real-time / batch / scheduled)\n  C: ___ (e.g., interface: voice / text / gesture)\n\nNow list 3 values for each dimension (A1,A2,A3 × B1,B2,B3 × C1,C2,C3).\nPick 3 random permutations that DON'T exist today.";
    },

    // 11
    (p) {
      final cIdx = _rand.nextInt(6);
      final competitors = ["Google", "a startup with 3 people", "an open-source community", "a monopoly", "a dictator", "a swarm of amateurs"];
      return "**COMPETITION_SABOTAGE** — ${competitors[cIdx]} wants you dead\n\nProblem: $p\n\n${competitors[cIdx]} has infinite resources and one goal: make your solution irrelevant.\n\nWhat would they do? What angle would they attack from?\n\nNow: do that FIRST, before they can. Make yourself irrelevant on YOUR terms.";
    },

    // 12
    (p) {
      final industry = _industries[_rand.nextInt(_industries.length)];
      return "**HIJACK_LEADER** — Steal from $industry\n\nProblem: $p\n\n$industry has already solved a FUNDAMENTAL problem that maps to yours.\n\nExtract the core principle from $industry (not the implementation — the WHY).\n\nApply it directly. What changes?";
    },

    // 13
    (p) {
      return "**NEGATIVE_SPACE** — Power of absence\n\nProblem: $p\n\nList EVERYTHING a typical solution includes. Every feature, every screen, every button.\n\nNow: subtract 80% of it. Keep only the ONE thing that cannot be removed.\n\nWhat if the solution is defined by what it DELIBERATELY OMITS?";
    },

    // 14
    (p) {
      final paradox = _paradoxes[_rand.nextInt(_paradoxes.length)];
      return "**PARADOX_RESOLUTION** — Achieve: $paradox\n\nProblem: $p\n\nConvention says you can't have both. Break the trade-off.\n\nWhat technology, model, or perspective makes this contradiction IRRELEVANT?\n\nNot compromise — transcend.";
    },

    // 15
    (p) {
      final pattern = _biomimicry[_rand.nextInt(_biomimicry.length)];
      return "**BIOMIMICRY** — $pattern\n\nProblem: $p\n\nNature has been R&D-ing for 3.8 billion years. This pattern works.\n\nMap the biological principle to your problem domain.\n\nWhat does nature's version look like?";
    },

    // 16
    (p) {
      return "**SECOND_ORDER** — Beyond first-order thinking\n\nProblem: $p\n\nFirst-order: the direct solution everyone sees.\n\nSecond-order: What happens AFTER the solution is adopted?\n  - New problems it creates\n  - Who loses? Who wins unexpectedly?\n  - What behaviors does it incentivize?\n\nThird-order: How does the world change 5 years after this exists?\n\nFind the idea that creates POSITIVE second-order effects.";
    },

    // 17
    (p) {
      final shock = _shocks[_rand.nextInt(_shocks.length)];
      return "**ANTIFRAGILE** — Design that thrives on $shock\n\nProblem: $p\n\nDon't just survive this shock — design so this shock makes you STRONGER.\n\nHow does $shock become a signal you can exploit?\n\nWhat would need to be true for $shock to be the BEST thing that could happen?";
    },

    // 18
    (p) {
      final prompt = _oblique[_rand.nextInt(_oblique.length)];
      return "**OBLIQUE_STRATEGIES** — Random prompt: $prompt\n\nProblem: $p\n\nApply this oblique constraint. Don't force logic — let the contradiction spark something new.\n\nThe best ideas come from unexpected collisions. Find yours.";
    },

    // 19 — MASHUP: force-merge with a physical object
    (p) {
      final obj = _mashupNouns[_rand.nextInt(_mashupNouns.length)];
      return "**MASHUP** — Problem × $obj\n\nProblem: $p\n\nForce-merge with a $obj.\n\nHow does a $obj work? What are its physical principles — tension, leverage, rotation, pressure, oscillation?\n\nTranslate those PHYSICAL principles into your abstract domain. What mechanism do you discover?";
    },

    // 20 — EMOTIONAL_ANCHOR: attach to a specific emotion
    (p) {
      final emotion = _emotions[_rand.nextInt(_emotions.length)];
      return "**EMOTIONAL_ANCHOR** — Design for $emotion\n\nProblem: $p\n\nForget features. Forget users. Forget technology.\n\nThe ONLY goal is to make someone feel $emotion.\n\nWhat single interaction would evoke $emotion?\n\nNow build the smallest possible thing that delivers that feeling.";
    },

    // 21 — CROSS_POLLINATION: replace a key term with domain jargon
    (p) {
      final jargonMap = {
        "biology": "symbiosis, homeostasis, tropism, metamorphosis",
        "music": "counterpoint, resonance, syncopation, modulation",
        "chess": "gambit, fork, zugzwang, discovered attack",
        "cooking": "mise en place, reduction, emulsion, maceration",
        "military": "flanking, logistics, camouflage, shock and awe",
      };
      final entries = jargonMap.entries.toList();
      final entry = entries[_rand.nextInt(entries.length)];
      return "**CROSS_POLLINATION** — $entry.key jargon\n\nProblem: $p\n\nReframe using $entry.key concepts: ${entry.value}.\n\nReplace one key term in the problem with each concept. How does the problem change?\n\nWhat solution becomes visible only through this lens?";
    },

    // 22 — USER_JOURNEY_INVERT: design the worst journey, then flip
    (p) {
      return "**USER_JOURNEY_INVERT** — Worst possible user flow\n\nProblem: $p\n\nMap the most frustrating, inefficient, rage-inducing user journey possible.\n  Step 1: ___ (make them wait)\n  Step 2: ___ (lose their data)\n  Step 3: ___ (ask them to repeat themselves)\n  Step 4: ___ (charge them for the privilege)\n\nNow run the SAME journey backwards. Each pain point becomes a delight.\n\nWhat's the resulting flow?";
    },

    // 23 — MINIMAL_VIABLE: what's the smallest test?
    (p) {
      return "**MINIMAL_VIABLE** — The FAKEST possible test\n\nProblem: $p\n\nWhat's the cheapest, ugliest, most hacky way to test if this idea has merit?\n\nNot an MVP — a PRETOTYPE. A fake button. A manual process that looks automated. A concierge service that feels like software.\n\nDesign the test that fits on a napkin. Run it this week.\n\nIf it works: build. If it fails: learn and pivot. Either way: you win.";
    },

    // 24 — GAMIFICATION: design as a game
    (p) {
      final gameMechanics = ["points", "levels", "leaderboards", "achievements", "streaks", "unlocks", "trading", "combos", "power-ups", "boss battles"];
      final mech1 = gameMechanics[_rand.nextInt(gameMechanics.length)];
      final mech2 = gameMechanics[_rand.nextInt(gameMechanics.length)];
      return "**GAMIFICATION** — Game mechanics: $mech1 + $mech2\n\nProblem: $p\n\nRedesign as a game using $mech1 and $mech2.\n\nWhat's the core loop? What's the 'fun' part?\n\nWhat happens when someone masters it?\n\nNow: remove the game layer but KEEP the engagement mechanics as the real product.";
    },

    // 25 — RITUAL_DESIGN: frame as a daily ritual
    (p) {
      return "**RITUAL_DESIGN** — Ceremony, not feature\n\nProblem: $p\n\nA feature is used. A ritual is ANTICIPATED.\n\nDesign a daily ritual around this solution:\n  - When does it happen? (fixed time / trigger)\n  - What's the preparation? (lighting, posture, breathing)\n  - What's the core moment? (the 'sacred' action)\n  - What's the closing? (a sign of completion)\n  - What's the reward? (dopamine, not data)\n\nThe solution IS the ritual. The technology is just props.";
    },

    // 26 — JCVD (JOBS TO BE DONE): what job is the user hiring for?
    (p) {
      return "**JOBS_TO_BE_DONE** — Hire the solution to do a JOB\n\nProblem: $p\n\nA user doesn't 'buy' a product. They HIRE it to do a job.\n\n1. What's the EXACT moment they realize they need this? (the struggle)\n2. What's the 'job' they're trying to get done? (functional + emotional + social)\n3. What are they CURRENTLY hiring? (the workaround)\n4. How do they FIRE the current solution?\n\nDesign FOR the job, not the feature set. What changes?";
    },

    // 27 — BLUE_OCEAN: eliminate-reduce-raise-create grid
    (p) {
      return "**BLUE_OCEAN** — Value innovation canvas\n\nProblem: $p\n\nDraw a 2×2 grid:\n\n| ELIMINATE (what does the industry compete on that's useless?) | REDUCE (what's over-engineered? below standard?) |\n| RAISE (what's under-delivered? above industry standard?) | CREATE (what's never been offered?) |\n\nFill each cell for $p.\n\nThe intersection of RAISE + CREATE is your blue ocean.";
    },

    // 28 — REVERSE_OUTCOME: start from desired end, prove it's inevitable
    (p) {
      return "**REVERSE_OUTCOME** — Pre-living the success\n\nProblem: $p\n\nFast-forward 3 years. Your solution is THE standard. Everyone uses it. It's obvious in hindsight.\n\nWrite the Wikipedia article for your solution as it exists 3 years from now:\n  - What does it do?\n  - Who uses it?\n  - How did it win?\n\nNow work backwards: what's the FIRST thing that had to be true for this future to exist?\n\nDo that first.";
    },

    // 29 — FAILURE_PRE_MORTEM: it failed, why?
    (p) {
      return "**FAILURE_PRE_MORTEM** — Autopsy before birth\n\nProblem: $p\n\nIt's one year later. The project failed completely. No one uses it.\n\nList 5 specific reasons it died:\n  1. ___\n  2. ___\n  3. ___\n  4. ___\n  5. ___\n\nNow: for each reason, design a PREVENTATIVE that makes that failure IMPOSSIBLE.\n\nYour solution survives by design, not luck.";
    },

    // 30 — PLATFORM_SHIFT: product → platform
    (p) {
      return "**PLATFORM_SHIFT** — Don't solve it. Enable others to solve it.\n\nProblem: $p\n\nInstead of building a solution, build a platform where OTHER people build solutions.\n\n- What's the atomic unit they create?\n- What's the constraint that makes their creativity flourish?\n- What's the marketplace / discovery mechanism?\n- How does each creation make the platform more valuable?\n\nStop building products. Start building ecosystems.";
    },

    // 31 — NETWORK_EFFECT_ENGINEERING: make it better with every user
    (p) {
      return "**NETWORK_EFFECT_ENGINEERING** — The 10th user makes it better for the 1st\n\nProblem: $p\n\nDesign so every new user increases value for ALL existing users.\n\nTypes of network effects:\n  - Direct: more users = more utility (telephone)\n  - Data: more usage = smarter system (maps)\n  - Platform: more users = more creators (app store)\n  - Social: more users = more identity value (instagram)\n\nWhich type fits? How do you ENGINEER the first 100 users to create value for each other?";
    },

    // 32 — CALM_TECH: zero attention design
    (p) {
      return "**CALM_TECHNOLOGY** — Invisible when working, visible only when needed\n\nProblem: $p\n\nDesign so the user's attention is NEVER required unless something is wrong.\n\nPrinciples:\n  - No notifications by default\n  - The periphery handles everything\n  - A glance communicates the state\n  - Trust, don't verify\n\nWhat does the solution look like when it demands ZERO cognitive load?\n\nHow does it earn trust through reliability, not engagement?";
    },

    // 33 — DISINTERMEDIATION: cut every middleman
    (p) {
      return "**DISINTERMEDIATION** — Remove every layer between creator and consumer\n\nProblem: $p\n\nMap EVERY entity between the source and the end user:\n  Creator → Platform A → Aggregator B → Distributor C → Retailer D → User\n\nRemove each layer one by one. What breaks? What survives?\n\nWhat happens when the creator and user are DIRECTLY connected?\n\nHow does eliminating the middleman change the value proposition?";
    },

    // 34 — SUBSCRIPTION_INVERT: flip the payment model
    (p) {
      final models = [
        "one-time purchase", "pay-per-use", "freemium", "open-source + donations",
        "subscription", "outcome-based pricing", "pay-what-you-want",
        "barter: users pay with data instead of money",
        "insurance model: pay small, get big when needed",
        "reverse subscription: platform pays YOU for using it",
      ];
      final model = models[_rand.nextInt(models.length)];
      return "**SUBSCRIPTION_INVERT** — Switch to $model\n\nProblem: $p\n\nForce the business model to $model.\n\nHow does this change what you build? Who becomes the customer?\n\nWhat features become irrelevant? What becomes CRITICAL?\n\nThe business model IS the product. Redesign from money backwards.";
    },

    // 35 — PROVOCATION: make a deliberately absurd statement
    (p) {
      final provocations = [
        "The solution is invisible. You never 'use' it. It just works.",
        "The user doesn't need to know it exists. Ever.",
        "It's illegal to use. Black market only.",
        "It works by doing NOTHING. The solution is inaction.",
        "It's powered by human boredom. The more bored, the better it works.",
        "Every use makes it worse. It degrades gracefully.",
        "It's destroyed after one use. Single-use, high-impact.",
        "It costs \$0.01 per use. You have to pay to use it.",
      ];
      final provocation = provocations[_rand.nextInt(provocations.length)];
      return "**PROVOCATION** — Absurd statement: $provocation\n\nProblem: $p\n\nAssume this is true. Find the useful kernel.\n\nDon't argue with it. EXPLOIT it.\n\nWhat's the VERSION of the solution that makes this statement wise, not absurd?";
    },

    // 36 — CHILD_VIEW: radical simplicity
    (p) {
      return "**CHILD_VIEW** — Explain it to a 5-year-old\n\nProblem: $p\n\nA 5-year-old asks:\n  - Why? (keep asking until you hit bedrock)\n  - How? (only the simplest mechanism)\n  - What if? (no concept of 'impossible')\n\nYour answers must use: toys, animals, food, and games as analogies.\n\nNow: design the solution using ONLY the concepts you just explained.\n\nIf a 5-year-old can understand it, ANYONE can use it.";
    },

    // 37 — ALIEN_VIEW: fresh eyes, zero context
    (p) {
      return "**ALIEN_VIEW** — An alien just landed. They see this for the first time.\n\nProblem: $p\n\nThe alien has no context. No assumptions. No industry knowledge.\n\nThey look at the problem and notice:\n  - What's WEIRD about it?\n  - What's ASSUMED that they would never assume?\n  - What's COMPLICATED that could be simple?\n  - What's MISSING that seems obvious?\n\nThe alien doesn't know what's 'impossible'. Design from their naivety.";
    },

    // 38 — HISTORICAL: solve it centuries ago
    (p) {
      final historical = [
        "Ancient Greece (agora, philosophy, democracy)",
        "Ming Dynasty China (bureaucracy, printing, trade routes)",
        "Islamic Golden Age (algebra, optics, hospitals)",
        "Mongol Empire (postal relay, rapid communication, multicultural)",
        "Mayan civilization (astronomy, zero, calendar systems)",
        "Venetian Republic (maritime trade, diplomacy, double-entry bookkeeping)",
        "Silk Road (long-distance trade, cultural exchange, caravanserai)",
        "Inca Empire (quipu, road network, terraced agriculture)",
      ];
      final civ = historical[_rand.nextInt(historical.length)];
      return "**HISTORICAL** — Solved by $civ\n\nProblem: $p\n\nThis civilization had NO technology as we know it.\n\nBut they had: social structures, rituals, workarounds, and deep wisdom.\n\nHow would $civ approach this problem?\n\nWhat solution would they build that's elegant, resourceful, and enduring?";
    },

    // 39 — ROLE_PLAY: extreme stakeholder perspective
    (p) {
      final roles = [
        "the CEO (maximize shareholder value, 5-year vision)",
        "the HACKER (find the exploit, break every rule)",
        "the REGULATOR (minimize risk, ensure compliance)",
        "the INVESTOR (ROI, scalability, exit strategy)",
        "the JOURNALIST (skeptical, looking for the angle)",
        "the LAWYER (liability, contracts, worst-case scenarios)",
        "the DESIGNER (beauty, delight, pixel-perfect execution)",
        "the SUPPORT AGENT (hear complaints all day, know what breaks)",
      ];
      final role = roles[_rand.nextInt(roles.length)];
      return "**ROLE_PLAY** — You are $role\n\nProblem: $p\n\nAdopt this perspective completely.\n\nWhat do you SEE that others miss? What do you PRIORITIZE?\n\nWhat's the ONE thing you would change or demand?\n\nThe best solutions serve ALL stakeholders. Find the intersection.";
    },

    // 40 — TREND_EXTREME: amplify a trend to its logical extreme
    (p) {
      final trends = [
        "Remote work ➔ no offices, no fixed hours, no physical presence ever",
        "AI automation ➔ everything is AI, no humans involved at all",
        "Privacy regulation ➔ zero data collection, no cookies, no tracking",
        "Decentralization ➔ no companies, no platforms, pure peer-to-peer",
        "Sustainability ➔ zero waste, zero carbon, fully circular economy",
        "Personalization ➔ every instance is completely unique per user",
        "No-code ➔ no developers, no code, no technical skills needed",
        "Subscription ➔ everything is a subscription, even light switches",
      ];
      final trend = trends[_rand.nextInt(trends.length)];
      return "**TREND_EXTREME** — Push '$trend' to its logical extreme\n\nProblem: $p\n\nTake this trend not to 10% adoption or 50% — push it to 100%.\n\nThe world has fully transformed. There's no going back.\n\nHow does $p work in this world?\n\nWhat becomes possible that's impossible today?\n\nNow: what's the V1 that starts moving in this direction?";
    },

    // 41 — SELF_HEALING: resilience by design
    (p) {
      return "**SELF_HEALING** — The solution diagnoses and fixes itself\n\nProblem: $p\n\nDesign so the system can:\n  - Detect when something is wrong (without being told)\n  - Diagnose the root cause (not just symptom)\n  - Repair itself (or escalate gracefully)\n  - Learn from the incident (never repeat)\n\nWhat sensors, feedback loops, and recovery mechanisms exist?\n\nA self-healing system is trusted. A manual system is tolerated.";
    },

    // 42 — QUANTITY_FIRST: 50 ideas, no filter
    (p) {
      return "**QUANTITY_FIRST** — 50 ideas in 5 minutes\n\nProblem: $p\n\nSet a timer for 5 minutes.\n\nGenerate as MANY ideas as possible:\n  - No judging. No filtering. No 'that won't work'.\n  - Bad ideas welcome. Terrible ideas ENCOURAGED.\n  - Quantity > quality at this stage.\n  - Steal, twist, mutate, combine.\n\nAfter 5 minutes: pick the top 3 most surprising ideas.\n\nIterate each one. The best idea is HIDING among the bad ones. Find it.";
    },

    // 43 — ECOSYSTEM: design for the whole system, not just the user
    (p) {
      return "**ECOSYSTEM** — Every solution creates ripple effects\n\nProblem: $p\n\nWho else is affected beyond the direct user?\n  - Suppliers (get squeezed? empowered?)\n  - Competitors (race to bottom? forced to innovate?)\n  - Regulators (new laws needed? banned?)\n  - Society (positive externality? negative externality?)\n  - Environment (resource consumption? waste?)\n  - Future generations (debt? gift?)\n\nDesign a solution that makes the ENTIRE ecosystem healthier, not just one part.";
    },

    // 44 — PARETO: find the 20% that delivers 80%
    (p) {
      return "**PARETO_PRINCIPLE** — 20% of effort, 80% of value\n\nProblem: $p\n\nList every feature, every component, every step.\n\nFor each: estimate the VALUE it delivers and the EFFORT to build it.\n\nIdentify the SMALL set (≈20%) that delivers MOST of the value (≈80%).\n\nNow: build ONLY that. Ship it in 1 week.\n\nThe rest might not even be needed. Find out.";
    },

    // 45 — GENERATIONAL: design for grandchildren
    (p) {
      return "**GENERATIONAL** — Your grandchildren inherit this\n\nProblem: $p\n\nImagine you're designing this for people born 50 years from now.\n\nThey will look back at your decisions and either THANK you or CURSE you.\n\nWhat decisions would they thank you for?\n  - Is it sustainable?\n  - Is it learnable?\n  - Is it adaptable?\n  - Does it create more problems than it solves?\n\nDesign with generational gratitude. Not quarterly profits.";
    },

    // 46 — CONTRAST: make one dimension huge, another tiny
    (p) {
      final dimensions = [
        "Input (1 byte) vs Output (100 GB)",
        "Speed (1 ms) vs Memory (1 byte)",
        "Cost (\$1 trillion) vs Users (3 people)",
        "Complexity (quantum mechanics) vs Interface (one button)",
        "Scale (global) vs Team (1 person)",
        "Storage (infinite) vs Bandwidth (1 bit/hour)",
        "Reliability (99.99999%) vs Budget (\$100)",
      ];
      final contrast = dimensions[_rand.nextInt(dimensions.length)];
      return "**CONTRAST** — Extreme asymmetry: $contrast\n\nProblem: $p\n\nDesign under this absurd asymmetry.\n\nThe constraint is so extreme it breaks conventional thinking.\n\nWhat architecture, model, or paradigm makes this possible?\n\nFind the idea that THRIVES on this imbalance.";
    },

    // 47 — METAPHOR_FORCE: force a metaphor
    (p) {
      final metaphors = [
        "This problem is a GARDEN. Weeds, seasons, pruning, cross-pollination.",
        "This problem is a WAR. Territory, ammunition, alliances, surrender.",
        "This problem is a DANCE. Rhythm, lead/follow, improvisation, floorcraft.",
        "This problem is a FEAST. Courses, ingredients, presentation, hunger.",
        "This problem is a JOURNEY. Terrain, companions, baggage, destination.",
        "This problem is a DETECTIVE STORY. Clues, suspects, red herrings, reveal.",
        "This problem is an ORCHESTRA. Sections, conductor, score, resonance.",
        "This problem is a TRADE ROUTE. Goods, tariffs, bandits, marketplaces.",
      ];
      final meta = metaphors[_rand.nextInt(metaphors.length)];
      return "**METAPHOR_FORCE** — $meta\n\nProblem: $p\n\nEXTEND the metaphor. Every element of the problem maps to the metaphor.\n\nWhat does the metaphor SHOW you about the problem?\n\nWhat solution emerges from the logic of the metaphor?\n\nMetaphors are models. Good models reveal hidden structure.";
    },

    // 48 — DARK_SIDE: what's the evil twin?
    (p) {
      return "**DARK_SIDE** — The malicious version\n\nProblem: $p\n\nDesign the version that's used for EVIL:\n  - Manipulates users\n  - Extracts maximum data\n  - Creates addiction\n  - Locks users in\n  - Discriminates by design\n  - Maximizes short-term profit at any cost\n\nNow: list everything the dark side does.\n\nNow: do the OPPOSITE for EACH item.\n\nYour ethical design is a mirror of the dark side. Study the darkness to perfect the light.";
    },

    // 49 — SOUND_DESIGN: design by auditory metaphor
    (p) {
      final sounds = [
        "a perfectly tuned guitar string",
        "rain on a tin roof",
        "a grandfather clock chiming midnight",
        "waves crashing on a rocky shore",
        "a library's silence — anticipatory, sacred",
        "the hum of a city at 4 AM",
        "a single bell in an empty cathedral",
        "static on a radio — noise full of potential",
      ];
      final sound = sounds[_rand.nextInt(sounds.length)];
      return "**SOUND_DESIGN** — Sound as solution: $sound\n\nProblem: $p\n\nIf this problem had a SOUND, it would be $sound.\n\nDescribe the sound in detail. What's the rhythm? Timbre? Dynamics?\n\nNow: map acoustic properties to solution properties:\n  - Harmony → integration of parts\n  - Resonance → amplification of effect\n  - Silence → what's not there\n  - Rhythm → timing and cadence\n\nThe right solution has the right 'sound'. Engineer the resonance.";
    },

    // 50 — ONE_BUTTON: absolute minimal interface
    (p) {
      return "**ONE_BUTTON** — The entire interface is a single button\n\nProblem: $p\n\nThe solution has exactly ONE interactive element.\n\nWhat does the button DO?\n  - When pressed once?\n  - When held?\n  - When double-pressed?\n  - When not pressed for a long time?\n\nEverything else is automatic, implicit, or inferred.\n\nIf ONE button solves this, you've found the CORE action.\n\nEverything else is noise. Remove it.";
    },

    // 51 — OPPOSITE_MEDIUM: what if it's not software?
    (p) {
      final mediums = [
        "a physical card deck", "a wall poster", "a board game",
        "a tattoo", "a letter sent by post", "a secret handshake",
        "a garden maze", "a vending machine", "a bus shelter ad",
        "a public bench", "a locked diary", "a clock face",
      ];
      final medium = mediums[_rand.nextInt(mediums.length)];
      return "**OPPOSITE_MEDIUM** — Not an app. It's $medium.\n\nProblem: $p\n\nForget software entirely. The solution is PHYSICAL.\n\nHow does $medium solve the problem?\n\nWhat constraints does physicality impose? (no updates, no analytics, no screens)\n\nWhat SUPERPOWERS does physicality give? (always there, tactile, shareable, hackable)\n\nNow: what's the DIGITAL version of that physical solution?";
    },

    // 52 — ZERO_TO_ONE: what's the thing that doesn't exist but should?
    (p) {
      return "**ZERO_TO_ONE** — Peter Thiel's question\n\nProblem: $p\n\nAsk: What IMPORTANT truth do very few people agree with you on?\n\nIf the problem is $p, what's the one thing that:\n  - Doesn't exist yet\n  - SHOULD exist\n  - Everyone would benefit from\n  - But NO ONE is building\n\nWhy isn't it built yet? (technical? regulatory? cultural? nobody thought of it?)\n\nIf you can name the thing that's missing, you've found the opportunity.";
    },

    // 53 — SIX_HATS: parallel thinking framework
    (p) {
      final hats = [
        "WHITE: just the facts. What do we KNOW? What data exists?",
        "RED: gut feeling. No justification. What's your INSTINCT?",
        "BLACK: devil's advocate. Why will this fail? What are the risks?",
        "YELLOW: optimist. What's the BEST case scenario? What's the value?",
        "GREEN: creative. What's a WILD possibility? What haven't we considered?",
        "BLUE: process. How are we thinking about this? What's the meta-view?",
      ];
      final hat = hats[_rand.nextInt(hats.length)];
      return "**SIX_HATS** — De Bono's $hat\n\nProblem: $p\n\nWear this hat COMPLETELY. No other perspective allowed.\n\nUsing ONLY this mode, what insights emerge?\n\nNow: switch to a different hat. What conflicts? What complement?\n\nThe best solutions survive ALL six perspectives.";
    },

    // 54 — SCAMPER: checklist for innovation
    (p) {
      final scamper = [
        "SUBSTITUTE: replace a component with something else. What if X were Y?",
        "COMBINE: merge with another function. What if it also did Z?",
        "ADAPT: what existing solution can be TWEAKED to fit?",
        "MODIFY: change a dimension — size, shape, color, speed, material",
        "PUT TO USE: what OTHER problem does this solve?",
        "ELIMINATE: remove a component. What breaks? What simplifies?",
        "REVERSE: do the opposite. Swap cause and effect. Flip inside out.",
      ];
      final prompt = scamper[_rand.nextInt(scamper.length)];
      return "**SCAMPER** — $prompt\n\nProblem: $p\n\nSystematically apply this prompt. Force specific answers.\n\nDon't describe the concept — PRODUCE the modified version.\n\nWhat concrete change emerges?";
    },

    // 55 — IKIGAI: four-circle intersection
    (p) {
      return "**IKIGAI** — Reason for being\n\nProblem: $p\n\nMap to four circles:\n  1. What you LOVE (passion)\n  2. What the WORLD NEEDS (mission)\n  3. What you can be PAID FOR (profession)\n  4. What you're GOOD AT (vocation)\n\nFor each circle, list 3-5 things related to $p.\n\nThe solution lives at the CENTER of all four.\n\nIf even one circle is empty, it's incomplete. Find the intersection.";
    },

    // 56 — NUDGE: behavioral economics
    (p) {
      final nudges = [
        "Default effect: what's the PRE-SELECTED option? Make it the desired behavior.",
        "Loss aversion: frame as 'what you'll LOSE' not 'what you'll gain'.",
        "Social proof: show that OTHERS are doing it.",
        "Scarcity: limited time, limited quantity, limited access.",
        "Anchoring: show a higher number first, then the real one.",
        "Choice architecture: how options are ORDERED changes what's chosen.",
        "Commitment device: make a small pledge that's hard to break.",
        "Salience: make the desired option VISUALLY dominant.",
      ];
      final nudge = nudges[_rand.nextInt(nudges.length)];
      return "**NUDGE** — $nudge\n\nProblem: $p\n\nApply this behavioral economics principle to the problem.\n\nHow can a small change in presentation dramatically change behavior?\n\nDesign the choice architecture, not the features.";
    },

    // 57 — FEYNMAN_TECHNIQUE: explain in simple terms, find gaps
    (p) {
      return "**FEYNMAN_TECHNIQUE** — If you can't explain it simply, you don't understand it\n\nProblem: $p\n\nWrite a one-paragraph explanation of $p using ONLY:\n  - Words a 12-year-old knows\n  - No jargon, no acronyms, no technical terms\n  - One analogy that carries the whole explanation\n\nNow: where did you struggle to simplify?\n\nTHAT's where the assumptions hide.\n\nTHAT's where the innovation opportunity is.";
    },

    // 58 — KEPNER_TREGOE: decision analysis
    (p) {
      return "**KEPNER_TREGOE** — Rational decision framework\n\nProblem: $p\n\n1. Situation Appraisal: What EXACTLY needs to change? (not symptoms — root)\n2. Problem Analysis: What IS vs what SHOULD BE? (gap analysis)\n3. Decision Analysis: List 3 options. For each:\n   - MUST criteria (non-negotiable)\n   - WANT criteria (weighted 1-10)\n   - Risks (probability × impact)\n4. Potential Problem Analysis: What could go WRONG with the best option?\n\nScore each option. The highest score ISN'T always right — check your gut.";
    },

    // 59 — FORCE_FIELD: driving vs restraining forces
    (p) {
      return "**FORCE_FIELD** — Lewin's change model\n\nProblem: $p\n\nList DRIVING forces that push toward the solution:\n  - (e.g., user demand, technology maturity, regulation tailwind)\n\nList RESTRAINING forces that hold back:\n  - (e.g., cost, risk, inertia, existing habits)\n\nStrategies:\n  - Strengthen driving forces (but can create resistance)\n  - WEAKEN restraining forces (more effective, less backlash)\n\nIdentify the ONE restraining force that, if removed, releases the most energy.\n\nRemove it. Everything else follows.";
    },

    // 60 — CYNE_FRAME: classify problem type, choose approach
    (p) {
      final frames = [
        "SIMPLE: known solution, known method. JUST DO IT.",
        "COMPLICATED: known solution, unknown method. HIRE AN EXPERT.",
        "COMPLEX: unknown solution, unknown method. EXPERIMENT.",
        "CHAOTIC: unknown everything. ACT FIRST, then figure out.",
        "DISORDER: don't know which frame. BREAK IT DOWN.",
      ];
      final frame = frames[_rand.nextInt(frames.length)];
      return "**CYNE_FRAME** — This problem is $frame\n\nProblem: $p\n\nClassify according to Cynefin:\n\nIf $frame, then the RIGHT approach is:\n  Simple → sense, categorize, respond\n  Complicated → sense, analyze, respond\n  Complex → probe, sense, respond\n  Chaotic → act, sense, respond\n\nWhat's the CORRECT method for this frame?\n\nMost failures come from applying the WRONG method to the frame.";
    },

    // 61 — SECOND_ORDER_CONSEQUENCES
    (p) {
      return "**SECOND_ORDER_CONSEQUENCES** — Unintended effects\n\nProblem: $p\n\nFor the obvious solution, list:\n  First-order: the DIRECT effect (what everyone expects)\n  Second-order: what happens AFTER the first order (ignored by most)\n  Third-order: long-term systemic change (ignored by almost everyone)\n\nExample:\n  Order 1: Build a road (faster travel)\n  Order 2: Suburbs expand, car dependency grows (traffic increases)\n  Order 3: Public transit decays, urban sprawl (more roads needed)\n\nFind the solution whose 3rd-order effects are POSITIVE.";
    },

    // 62 — IDEOGRAM: solve with one symbol
    (p) {
      final symbols = ["∞", "○", "△", "⬡", "⧖", "♾️", "⚡", "🌀", "✦", "⏣", "♻️", "⌘", "⚙️", "◇", "⬟"];
      final symbol = symbols[_rand.nextInt(symbols.length)];
      return "**IDEOGRAM** — The solution is a $symbol\n\nProblem: $p\n\nIf the ENTIRE solution were represented by a single symbol ($symbol), what would that symbol mean?\n\n- What's the shape of the solution?\n- What's the motion or transformation?\n- What's the relationship between parts?\n\nDescribe the solution in terms of the symbol's geometry and meaning.\n\nThe symbol is the ABSTRACTION. The implementation follows.";
    },

    // 63 — TEN_TYPES: innovation beyond product
    (p) {
      final types = [
        "PROFIT MODEL: how you make money (not what you sell)",
        "NETWORK: who you connect (not who you sell to)",
        "STRUCTURE: how you organize talent (not who you hire)",
        "PROCESS: how you operate (not what you build)",
        "PRODUCT PERFORMANCE: features and quality",
        "PRODUCT SYSTEM: complementary products (ecosystem)",
        "SERVICE: how you support (not what you deliver)",
        "CHANNEL: how you reach users (not where you advertise)",
        "BRAND: what you stand for (not what you say)",
        "CUSTOMER ENGAGEMENT: how they interact (not just UI)",
      ];
      final type = types[_rand.nextInt(types.length)];
      return "**TEN_TYPES** — Innovate on $type\n\nProblem: $p\n\nEvery startup competes on PRODUCT. But innovation can happen in 10 dimensions.\n\nFocus EXCLUSIVELY on $type.\n\nWhat's the most innovative version of $type for $p?\n\nMost breakthroughs come from non-product innovation. Product is just the delivery mechanism.";
    },

    // 64 — SUNK_COST: ignore everything already invested
    (p) {
      return "**SUNK_COST** — Forget everything you've already done\n\nProblem: $p\n\nImagine you have:\n  - Zero code written\n  - Zero users acquired\n  - Zero investors convinced\n  - Zero reputation on the line\n  - Zero commitments made\n\nYou have a fresh notebook and this problem.\n\nWhat would you build RIGHT NOW?\n\nIf the answer is different from what you're CURRENTLY building, you're a victim of sunk cost.\n\nStop. Build the right thing.";
    },

    // 65 — CHARETTE: 48-hour design sprint
    (p) {
      return "**CHARETTE** — 48-hour design sprint\n\nProblem: $p\n\nYou have 48 hours. No extensions. Ship or scrap.\n\nHour 0-6: Research & Frame\n  - Understand the problem, talk to 3 users, define success\n\nHour 6-24: Ideate & Prototype\n  - Generate solutions, pick one, build the FAKEST prototype\n\nHour 24-44: Build & Iterate\n  - Make it work (barely), test with 5 users, fix the critical bugs\n\nHour 44-48: Polish & Ship\n  - Make it presentable, write the docs, SHIP\n\nWhat emerges from extreme time pressure? What's CORE vs NICE-TO-HAVE?";
    },

    // 66 — FISHBONE: root cause analysis
    (p) {
      return "**FISHBONE** — Ishikawa root cause analysis\n\nProblem: $p\n\nCategories of potential causes:\n  - PEOPLE: skills, motivation, communication\n  - PROCESS: steps, handoffs, bottlenecks\n  - TECHNOLOGY: tools, infrastructure, dependencies\n  - DATA: quality, availability, format\n  - ENVIRONMENT: regulations, culture, market conditions\n  - MEASUREMENT: what's tracked, what's invisible\n\nFor each category, list 3 potential root causes.\n\nThe REAL cause is a combination — not one thing.\n\nFix the SYSTEM, not the symptom.";
    },

    // 67 — DESIGN_THINKING: human-centered process
    (p) {
      return "**DESIGN_THINKING** — Empathize → Define → Ideate → Prototype → Test\n\nProblem: $p\n\nEMPATHIZE: what's the USER feeling? (not thinking — feeling)\n  - Frustration? Anxiety? Excitement? Boredom?\n\nDEFINE: reframe the problem from their perspective:\n  'How might we ___ so that the user feels ___?'\n\nIDEATE: 3 radically different approaches (don't pick yet — diverge)\n\nPROTOTYPE: the CHEAPEST way to test each approach\n\nTEST: with ONE user. What surprised you?\n\nDesign thinking is a CIRCLE. After TEST, go back to EMPATHIZE with new knowledge.";
    },

    // 68 — SYSTEMS_THINKING: leverage points
    (p) {
      return "**SYSTEMS_THINKING** — Meadows' leverage points\n\nProblem: $p\n\nLeverage points (least to most effective):\n  1. Numbers (parameters, subsidies, taxes) — WEAKEST\n  2. Buffers (inventories, reserves)\n  3. Stock-and-flow structures (physical layout)\n  4. Delays (response times)\n  5. Feedback loops (balancing vs reinforcing)\n  6. Information flows (who knows what when)\n  7. Rules (incentives, constraints, permissions)\n  8. Self-organization (ability to evolve)\n  9. Goals (the PURPOSE of the system)\n  10. Paradigm (the MINDSET from which the system arises) — STRONGEST\n\nFind the HIGHEST leverage point you can shift. Change THAT. Everything else follows.";
    },

    // 69 — OCCAM_RAZOR: simplest explanation that fits all facts
    (p) {
      return "**OCCAM_RAZOR** — The simplest solution is usually correct\n\nProblem: $p\n\nDescribe the simplest possible solution. NO unnecessary complexity:\n  - Can it be one file? One function? One rule?\n  - Can it work without configuration?\n  - Can it be explained in one sentence?\n  - Can it be built in one day?\n\nComplexity is ADDED, not inherent. Every feature beyond the CORE is a bet.\n\nWhat's the solution so simple it feels WRONG?\n\nTry it. It might be right.";
    },

    // 70 — CIRCLES: comprehensive problem framing
    (p) {
      return "**CIRCLES** — Complete problem framing\n\nC — Comprehend the situation:\n  What's the CONTEXT? Who cares? Why now?\n\nI — Identify the user:\n  WHO specifically? Not 'everyone' — ONE archetype.\n\nR — Report the user's needs:\n  What do they NEED? (not want — need)\n\nC — Cut through and list priorities:\n  What's the ONE thing that matters most?\n\nL — List solutions:\n  3 different approaches. Don't optimize yet.\n\nE — Evaluate trade-offs:\n  What does each solution cost? (time, money, complexity, risk)\n\nS — Summarize your recommendation:\n  Pick one. Defend it. Execute.\n\nApply CIRCLES to $p.";
    },

    // 71 — DIXIT: narrative framing
    (p) {
      return "**DIXIT** — The story IS the solution\n\nProblem: $p\n\nEvery solution comes with a STORY. The best solution has the BEST story.\n\nWhat's the story of $p?\n  - Who's the hero? (the user, not you)\n  - What's the villain? (the old way, the frustration)\n  - What's the mentor? (your solution)\n  - What's the transformation? (before/after)\n  - What's the moral? (why this matters)\n\nDesign the story FIRST. Let the features serve the narrative.\n\nPeople don't buy products. They buy better versions of themselves.";
    },

    // 72 — PRICE_SIGNALING: price as a feature
    (p) {
      final prices = [
        "Free (ad-supported or open source)", "\$0.99", "\$9.99/month",
        "\$999 one-time", "\$49,999 enterprise license",
        "Pay what you want", "Free + tips", "Freemium (basic free, pro \$29)",
        "Outcome-based (pay per result)", "Lifetime access \$199",
      ];
      final price = prices[_rand.nextInt(prices.length)];
      return "**PRICE_SIGNALING** — Priced at $price\n\nProblem: $p\n\nPrice is NOT just revenue. It's a SIGNAL.\n\nWhat does $price signal about your product?\n  - Free = mass adoption, low barrier, ads or donations\n  - \$999 = premium, exclusive, high quality\n  - Pay what you want = trust, community, accessible\n\nDesign the product to MATCH the price signal.\n\nWhat features does $price demand? What's included? What's excluded?";
    },

    // 73 — DISTRIBUTION_FIRST: how it spreads > what it does
    (p) {
      final channels = [
        "viral referral (every user invites 3)", "embed in existing platforms",
        "API-first (developers distribute for you)", "physical retail (shelf space)",
        "government mandate (regulation requires it)", "school curriculum (teach the next generation)",
        "bundled with hardware", "viral social challenge (TikTok loop)",
        "enterprise sales (top-down)", "community-led (Slack, Discord, GitHub)",
      ];
      final channel = channels[_rand.nextInt(channels.length)];
      return "**DISTRIBUTION_FIRST** — Distribution via $channel\n\nProblem: $p\n\nGreat product × bad distribution = failure.\nOK product × great distribution = success.\n\nDesign the product so $channel is its NATURAL distribution mechanism.\n\nThe product IS the distribution channel. How does every usage spread it?";
    },

    // 74 — ONBOARDING_AS_PRODUCT: first 10 seconds
    (p) {
      return "**ONBOARDING_AS_PRODUCT** — The first 10 seconds ARE the product\n\nProblem: $p\n\nMost users never get past onboarding. The onboarding IS the product for most users.\n\nDesign a 10-second experience that delivers 80% of the value.\n  Second 1-2: show the core insight (a single visual)\n  Second 3-5: let them do THE thing (no signup)\n  Second 6-8: show the result (immediate feedback)\n  Second 9-10: ask ONE question\n\nIf they get value in 10 seconds, they'll invest 10 minutes.\n\nIf they don't, nothing else matters.";
    },

    // 75 — INVERSE_CONWAY: design org structure, not product
    (p) {
      return "**INVERSE_CONWAY** — Conway's Law: org structure produces product structure\n\nProblem: $p\n\nConway's Law: organizations design systems that mirror their communication structure.\n\nInverse Conway: design the DESIRED system architecture first. Then restructure the team to MATCH.\n\nFor $p:\n  - What's the ideal system architecture? (microservices? monolith? peer-to-peer?)\n  - What team structure NATURALLY produces this architecture?\n  - How do you reorganize to make the architecture inevitable?\n\nChange the org. The product follows.";
    },

    // 76 — AMBIGUITY_SANDBOX: embrace ambiguity
    (p) {
      return "**AMBIGUITY_SANDBOX** — Define, then violate the definition\n\nProblem: $p\n\nSTEP 1: Define the problem in EXACT terms. No ambiguity.\n  \"The problem is EXACTLY: ___.\"\n\nSTEP 2: Now, deliberately MISINTERPRET the problem in 3 different ways.\n  \"Actually, the problem is: ___\" (wrong on purpose)\n\nSTEP 3: Solve each MISINTERPRETATION.\n\nSTEP 4: What's COMMON across all solutions?\n\nAmbiguity is a resource, not a bug. The best solutions work for the WRONG interpretations too.";
    },

    // 77 — DEADLINE_ACCELERATOR: time machine
    (p) {
      final deadlines = ["1 hour", "24 hours", "1 week", "1 month", "1 quarter", "1 year", "10 years"];
      final d1 = deadlines[_rand.nextInt(deadlines.length)];
      final d2 = deadlines.where((d) => d != d1).toList()..shuffle();
      return "**DEADLINE_ACCELERATOR** — Ship in $d1 vs $d2\n\nProblem: $p\n\nTwo versions:\n\nVERSION A: Must ship in $d1. What do you build? What do you CUT?\n  - No time for perfection. What's the hacky prototype that proves the concept?\n\nVERSION B: You have $d2. What do you build with PATIENCE?\n  - Time for elegance, scale, and quality.\n\nThe differences between A and B reveal what's ESSENTIAL vs what's LUXURY.\n\nShip A today. Ship B next year.";
    },

    // 78 — LIQUID_INTERFACE: no fixed UI
    (p) {
      return "**LIQUID_INTERFACE** — The interface adapts to the context, not the device\n\nProblem: $p\n\nThe interface is NOT fixed. It morphs based on:\n  - Who's using it (beginner vs expert)\n  - Where they are (desk vs walking vs driving)\n  - What they're doing (focused vs multitasking)\n  - What device they have (watch vs phone vs wall)\n  - Their state (calm vs stressed vs tired)\n\nThe SAME core functionality, radically different interfaces.\n\nDesign the CORE first. The interface is just a skin."
    },

    // 79 — OPEN_CORE: commoditize the complement
    (p) {
      return "**OPEN_CORE** — Give away what's complementary, sell what's scarce\n\nProblem: $p\n\nStrategy: open-source the part that ENABLES your business model.\n\n- What's the complement? (the thing people need to USE your product)\n   → Make it open/free/commodity\n- What's the core? (the thing that makes you unique)\n   → Sell it\n\nExamples:\n  - Red Hat: free Linux, paid support\n  - GitHub: free public repos, paid private + enterprise\n  - Docker: free engine, paid orchestration\n\nWhat can you commoditize to make your core indispensable?"
    },

    // 80 — MEME_DESIGN: ideas that spread
    (p) {
      return "**MEME_DESIGN** — Design for replication, not consumption\n\nProblem: $p\n\nThe best solutions spread like memes. They're:\n  - SIMPLE: one sentence, no jargon\n  - SURPRISING: violates an expectation\n  - CONCRETE: specific, not abstract\n  - CREDIBLE: self-evident truth\n  - EMOTIONAL: makes you feel something\n  - STORY: nested in a narrative\n\nDesign the MEME of your solution. If it's not memeable, it's not spreadable.\n\nWhat's the one-liner that makes someone say 'Wait, say that again?'"
    },

    // 81 — CUSTOMER_JOB_MAP: the 8-step job
    (p) {
      return "**CUSTOMER_JOB_MAP** — The universal job map\n\nProblem: $p\n\nEvery job has 8 universal steps:\n  1. DEFINE: what needs to happen?\n  2. LOCATE: where are the inputs?\n  3. PREPARE: set up the environment\n  4. CONFIRM: verify readiness\n  5. EXECUTE: do the core work\n  6. MONITOR: track progress\n  7. MODIFY: adjust as needed\n  8. CONCLUDE: finish and clean up\n\nMap $p to these 8 steps. Which steps are PAINFUL?\n\nThe innovation is in the PAINFUL steps, not the easy ones."
    },

    // 82 — CAPABILITIES_MATRIX: what can it DO?
    (p) {
      final capabilities = [
        "SENSE (detect a state change)", "TRANSLATE (convert between formats)",
        "PREDICT (forecast an outcome)", "REMEMBER (store and recall)",
        "COMPARE (evaluate options)", "CONNECT (link disparate things)",
        "TRANSFORM (change state)", "SIMULATE (model a scenario)",
        "DECIDE (choose an action)", "LEARN (improve from feedback)",
        "EXPLAIN (justify a result)", "ALERT (notify when necessary)",
      ];
      final cap = capabilities[_rand.nextInt(capabilities.length)];
      return "**CAPABILITIES_MATRIX** — Core capability: $cap\n\nProblem: $p\n\nIF the solution could ONLY do ONE thing — $cap — and do it PERFECTLY, what would it be?\n\nDesign the solution around this single capability.\n\nEverything else is a wrapper around the core capability.\n\nMaster ONE thing. The rest is plumbing."
    },

    // 83 — CULTURAL_FIT: design for a specific culture
    (p) {
      final cultures = [
        "Japanese (wa-harmony, kaizen-continuous improvement, omotenashi-hospitality)",
        "Scandinavian (lagom-enough, hygge-coziness, Jante Law-humility)",
        "Indian (jugaad-frugal innovation, jugaad-flexible, family-first)",
        "Brazilian (ginga-flow, improvisation, community)",
        "German (ordnung-order, grundlichkeit-thoroughness, quality)",
        "Silicon Valley (move fast, break things, growth at all costs)",
        "Swiss (precision, privacy, neutrality, quality over quantity)",
        "Kenyan (harambee-pulling together, community resilience)",
      ];
      final culture = cultures[_rand.nextInt(cultures.length)];
      return "**CULTURAL_FIT** — Designed for $culture\n\nProblem: $p\n\nDesign EXCLUSIVELY for this culture's values and constraints.\n\nWhat's acceptable? What's taboo?\n\nWhat features are ESSENTIAL? What's irrelevant?\n\nDesign for THIS culture. Make it perfect for them.\n\nIf it's perfect for THEM, it might have insights for everyone."
    },

    // 84 — ERROR_DRIVEN: make mistakes the feature
    (p) {
      return "**ERROR_DRIVEN** — Every error is a feature request\n\nProblem: $p\n\nDesign where errors are NOT bugs — they're the CORE feedback mechanism.\n\nPrinciples:\n  - Errors are informative, not punishable\n  - Every error reveals a missing affordance\n  - The system learns MORE from errors than successes\n  - The error IS the error message\n\nWhat if the user can't make a MISTAKE?\n\nWhat if every 'wrong' action produces a VALUABLE output?\n\nDesign the system that only works when you fail."
    },

    // 85 — SENSORY_DEPRIVATION: remove one sense
    (p) {
      final senses = [
        "no sight (blind user, audio/touch only)",
        "no hearing (deaf user, visual/tactile only)",
        "no touch (cannot hold or feel, use gestures or voice)",
        "no speech (cannot ask for help, cannot use voice commands)",
        "no sight AND no hearing (deaf-blind, touch only)",
        "no sense of time (no deadlines, no urgency, no clocks)",
        "no context (don't know where you are, what happened before)",
      ];
      final sense = senses[_rand.nextInt(senses.length)];
      return "**SENSORY_DEPRIVATION** — Interface with $sense\n\nProblem: $p\n\nDesign the ENTIRE experience for someone with $sense.\n\nEvery assumption about the interface is WRONG.\n\nHow do you communicate? How do they act? How do they know it's working?\n\nForcing this constraint reveals the TRUE essence of the interaction."
    },

    // 86 — RECIPROCITY_LOOP: give to get
    (p) {
      return "**RECIPROCITY_LOOP** — Give first, ask later\n\nProblem: $p\n\nHuman psychology: when someone gives us something, we feel OBLIGATED to give back.\n\nDesign a reciprocity loop:\n  1. Give IMMEDIATE value (no signup, no commitment)\n  2. Deliver SURPRISING value (more than expected)\n  3. Ask for something SMALL (feedback, share, email)\n  4. Give MORE value (reinforce the loop)\n  5. Ask for the ASK (purchase, upgrade, referral)\n\nThe best sales don't feel like sales. They feel like gratitude."
    },

    // 87 — FEEDBACK_FIRST: measure what matters
    (p) {
      return "**FEEDBACK_FIRST** — What gets measured gets improved\n\nProblem: $p\n\nDesign the feedback system BEFORE the product:\n\n1. What's the SINGLE metric that defines success?\n   (Not vanity metrics — the ONE number that matters)\n\n2. How do you measure it in REAL TIME?\n   (If you can't measure it quickly, you can't steer)\n\n3. What's the CLOSED LOOP?\n   (Action → Measurement → Learning → New Action)\n\n4. How does the system communicate its state?\n   (A glance, not a dashboard)\n\nThe product IS a feedback system. Features are just actuators."
    },

    // 88 — EMERGENCE: local rules, global behavior
    (p) {
      return "**EMERGENCE** — Simple rules, complex outcomes\n\nProblem: $p\n\nComplex systems emerge from SIMPLE local rules.\n\nDesign 3 simple rules that produce the DESIRED global behavior:\n  Rule 1: ___\n  Rule 2: ___\n  Rule 3: ___\n\nNo central control. No global plan. Just local interactions.\n\nExamples:\n  - Birds flock with 3 rules (alignment, separation, cohesion)\n  - Markets with 1 rule (buy low, sell high)\n  - Ants with 2 rules (follow pheromone, leave pheromone)\n\nWhat complex behavior emerges from YOUR 3 rules?"
    },
  ];
}
