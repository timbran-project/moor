object HELP_TOPICS
  name: "Global Help Topics"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property topic_basics (owner: ARCH_WIZARD, flags: "rc") = {
    "basics",
    "Getting started",
    "Welcome to Cowbell! Use `look` to see where you are, move with directions like `north` or `n`, and `inventory` to see what you're carrying.\n\nTalk with `say <message>` or `\"<message>`, and express actions with `emote <action>` or `:<action>`.\n\nType `help` anytime to see available topics.",
    {"start", "newbie", "begin", "intro"},
    "basics",
    {"look", "movement", "inventory", "communicating"}
  };
  property topic_bite (owner: ARCH_WIZARD, flags: "rc") = {
    "bite",
    "Take a bite of food",
    "Use `bite <food>` to take a small bite of food. Takes less than eating the whole thing.\n\nSee also `nibble` for even smaller portions.",
    {},
    "basics",
    {"eat", "nibble"}
  };
  property topic_communicating (owner: ARCH_WIZARD, flags: "rc") = {
    "communicating",
    "Talking and expressing yourself",
    "There are several ways to interact with others:\n\n`say` - Speak aloud for everyone in the room to hear.\n\n`emote` - Describe an action with your name at the start.\n\n`think` - Show a thought bubble.\n\nSocial gestures like `wave`, `nod`, `smile` let you interact without typing descriptions. See `help socializing` for the full list.",
    {"communication", "talking", "speaking"},
    "social",
    {"say", "emote", "socializing"}
  };
  property topic_describe (owner: ARCH_WIZARD, flags: "rc") = {
    "@describe",
    "Describe yourself",
    "Use `@describe me as <description>` to set how others see you when they look at you.",
    {"@desc"},
    "basics",
    {"look"}
  };
  property topic_drink (owner: ARCH_WIZARD, flags: "rc") = {
    "drink",
    "Drink a beverage",
    "Use `drink <beverage>` to drink from a vessel you're holding.\n\nRelated commands:\n- `sip <beverage>` - take a small sip\n- `gulp <beverage>` or `quaff <beverage>` - drink quickly\n- `refill <vessel> from <source>` - refill from a tap or fountain",
    {},
    "basics",
    {"eat", "sip"}
  };
  property topic_drop (owner: ARCH_WIZARD, flags: "rc") = {
    "drop",
    "Put something down",
    "Use `drop <thing>` to remove something from your inventory and leave it in the current room.",
    {},
    "basics",
    {"get", "inventory"}
  };
  property topic_eat (owner: ARCH_WIZARD, flags: "rc") = {
    "eat",
    "Eat food",
    "Use `eat <food>` to consume food you're holding or that's nearby. Eating consumes the whole portion.\n\nRelated commands:\n- `bite <food>` - take a smaller bite\n- `nibble <food>` - nibble delicately",
    {"consume"},
    "basics",
    {"drink", "bite"}
  };
  property topic_emote (owner: ARCH_WIZARD, flags: "rc") = {
    "emote",
    "Express actions",
    "Use `emote <action>` or `:<action>` to describe what you're doing. Your name appears at the start.\n\n`emote waves hello` \u2192 _YourName waves hello_\n\n`:laughs` \u2192 _YourName laughs_",
    {"pose", ":"},
    "social",
    {"say", "communicating", "socializing"}
  };
  property topic_examine (owner: ARCH_WIZARD, flags: "rc") = {
    "examine",
    "Examine something closely",
    "Use `examine <thing>` to get detailed information about an object or person.\n\nOften reveals details not visible with just `look`.",
    {"ex", "x"},
    "basics",
    {"look"}
  };
  property topic_exits (owner: ARCH_WIZARD, flags: "rc") = {
    "exits",
    "See available exits",
    "Use `exits` or `ways` to see a list of directions you can travel from the current room.",
    {"ways", "directions"},
    "basics",
    {"movement", "look"}
  };
  property topic_gag (owner: ARCH_WIZARD, flags: "rc") = {
    "@gag",
    "Ignore output from a player or object",
    "Use `@gag <player|object>` to add someone (or something) to your gag lists.\n\nExamples:\n\n- `@gag Alice` (gag a player by name)\n- `@gag #123` (gag an object by object number)\n\nNotes:\n\n- Players are matched globally by name.\n- Objects are matched in your current scope; use `#<id>` to gag a specific object anywhere.\n- Gagging is local to you and does not notify the other party.",
    {"gag", "mute", "block"},
    "communicating",
    {"gagging", "@ungag", "@listgag"}
  };
  property topic_gagging (owner: ARCH_WIZARD, flags: "rc") = {
    "gagging",
    "Hide output from a player/object",
    "Gagging lets you hide output that originates from a specific player or object.\n\nWhen someone is gagged, their speech, direct messages, and other output that they initiate will be suppressed on *your* client. This is a personal preference and abuse-avoidance tool.\n\n### What gagging does\n\n- Hides output that originates from the gagged player/object.\n- Works for both players and non-player objects.\n- Affects only what *you* see; it does not stop them from seeing you.\n- Does not notify the other party.\n\n### What gagging does not do\n\n- It is not a ban.\n- It does not prevent the other party from interacting with the world.\n- It does not remove them from public spaces.\n\n### If you're dealing with harassment or abuse\n\n- Use `@gag <name>` immediately to reduce exposure.\n- Preserve context if you can (room name, time, what happened).\n- Contact staff/moderators/administrators for help.\n- If you feel unsafe, disconnect and reach out out-of-band.\n\n### Related commands\n\n- `@gag <player|object>`\n- `@ungag <player|object>` (or `@ungag everyone`)\n- `@listgag`",
    {"gag", "mute", "block", "harassment", "abuse", "spam"},
    "communicating",
    {"@gag", "@ungag", "@listgag", "communicating", "mail"}
  };
  property topic_get (owner: ARCH_WIZARD, flags: "rc") = {
    "get",
    "Pick something up",
    "Use `get <thing>` or `take <thing>` to pick up an object and add it to your inventory.",
    {"take", "pick"},
    "basics",
    {"drop", "inventory"}
  };
  property topic_give (owner: ARCH_WIZARD, flags: "rc") = {
    "give",
    "Give something to someone",
    "Use `give <thing> to <person>` to hand an object to another person.",
    {"hand"},
    "social",
    {"get", "drop"}
  };
  property topic_inventory (owner: ARCH_WIZARD, flags: "rc") = {
    "inventory",
    "See what you're carrying",
    "Use `inventory` or `i` to list everything you're holding.\n\nItems you're wearing are marked.",
    {"i", "inv"},
    "basics",
    {"get", "drop"}
  };
  property topic_listgag (owner: ARCH_WIZARD, flags: "rc") = {
    "@listgag",
    "Show your gag lists",
    "Use `@listgag` to see which players and objects you currently have gagged.\n\nWhen run as a command, it also reports who has gagged you (if anyone).",
    {"listgag", "gaglist"},
    "communicating",
    {"gagging", "@gag", "@ungag"}
  };
  property topic_look (owner: ARCH_WIZARD, flags: "rc") = {
    "look",
    "Look at your surroundings",
    "Use `look` to see the room you're in, including exits and people present.\n\nUse `look <thing>` to examine something specific in more detail.",
    {"l"},
    "basics",
    {"examine", "exits"}
  };
  property topic_movement (owner: ARCH_WIZARD, flags: "rc") = {
    "movement",
    "Moving around",
    "Move using compass directions: `north`, `south`, `east`, `west` (or `n`, `s`, `e`, `w`).\n\nSome places have other exits like `up`, `down`, `in`, `out`.\n\nUse `exits` to see available directions.",
    {"go", "walk", "move", "travel"},
    "basics",
    {"exits", "look"}
  };
  property topic_privacy (owner: ARCH_WIZARD, flags: "rc") = {
    "privacy",
    "Privacy policy and data practices",
    "## Timbran Hotel Privacy Policy\n\n*Your privacy is respected at the Timbran Hotel.*\n\n### What We Collect\n\nWhen you register as a guest, we store:\n- Your chosen name\n- Your password (securely encrypted)\n- Your personal event history (encrypted with your encryption passphrase)\n\n### What We Don't Do\n\n- We do **not** algorithmically profile or target you\n- We do **not** sell or share your data with advertisers or data brokers\n- We do **not** read your encrypted event history\u2014only you can decrypt it\n\n### Public Spaces\n\nThe Timbran Hotel has many public rooms\u2014the lobby, corridors, common areas. Conversations and actions in public spaces are naturally visible to other guests present. This is the nature of a shared world, not data collection.\n\nIf you wish for privacy, seek out private rooms or communicate through the mail system.\n\n### Mail & Direct Messages\n\nMail and direct messages between guests are currently stored unencrypted. We plan to add encryption in the future.\n\nWhile administrators technically have access, we maintain a strict policy against reading private correspondence. Treat these as you would a postcard\u2014private in practice, but not cryptographically secured.\n\n### User Creations\n\nObjects you create, customizations you make, and programs you write are stored in the world database. Even if you mark them as private, administrators can view them for maintenance and moderation purposes.\n\n### AI & LLM Agents\n\nCertain areas of the hotel feature AI-powered characters\u2014such as Mr. Welcome in the lobby or staff at the front desk. These agents use large language models to interact with guests.\n\nWhen you interact in rooms with these agents:\n\n- Your actions and speech in that room may be processed by external AI services\n- We prioritize open-weight models and may run self-hosted models in the future\n- We transmit only what's necessary for the interaction\n\nAI-powered items (like the Architect's Compass or Data Visor) work similarly\u2014using them sends your input to AI services.\n\nWe plan to offer an opt-out so your direct actions aren't shared with room-based agents. However, if other guests mention you or have conversations about you, that content may still be processed.\n\n### Data Retention\n\nYour account and encrypted history remain as long as you're a guest. You may request deletion of your account and all associated data at any time by contacting the management.\n\n### Contact\n\nFor privacy concerns, speak with the hotel management or contact the server administrator.",
    {"privacy policy", "data", "gdpr"},
    "basics",
    {}
  };
  property topic_quit (owner: ARCH_WIZARD, flags: "rc") = {
    "@quit",
    "Disconnect",
    "Use `@quit` to disconnect from the game.\n\nYour character stays in the world but goes to sleep.",
    {"quit", "logout"},
    "basics",
    {}
  };
  property topic_refill (owner: ARCH_WIZARD, flags: "rc") = {
    "refill",
    "Refill a drink vessel",
    "Use `refill <vessel> from <source>` to refill an empty or partially empty drink vessel from a source like a fountain, tap, or dispenser.",
    {},
    "basics",
    {"drink"}
  };
  property topic_say (owner: ARCH_WIZARD, flags: "rc") = {
    "say",
    "Speak to others",
    "Use `say <message>` or `\"<message>` to speak aloud. Everyone in the room hears you.\n\n`say Hello everyone!`\n`\"Hi there!`",
    {"talk", "speak", "\""},
    "social",
    {"emote", "communicating"}
  };
  property topic_sip (owner: ARCH_WIZARD, flags: "rc") = {
    "sip",
    "Sip a drink",
    "Use `sip <beverage>` to take a small, delicate sip from a drink.\n\nSee also `gulp` or `quaff` for larger drinks.",
    {},
    "basics",
    {"drink", "gulp"}
  };
  property topic_ungag (owner: ARCH_WIZARD, flags: "rc") = {
    "@ungag",
    "Remove someone from your gag list",
    "Use `@ungag <player|object>` to remove someone (or something) from your gag lists.\n\nExamples:\n\n- `@ungag Alice`\n- `@ungag #123`\n- `@ungag everyone` (clear both gag lists)\n\nTip:\n\n- `@listgag` shows what is currently gagged.",
    {"ungag", "unmute", "unblock"},
    "communicating",
    {"gagging", "@gag", "@listgag"}
  };
  property topic_who (owner: ARCH_WIZARD, flags: "rc") = {
    "who",
    "See who's online",
    "Use `who` to see a list of connected players and how long they've been idle.",
    {"players", "online"},
    "social",
    {}
  };

  override description = "Global help topics available everywhere in the system.";
  override import_export_hierarchy = {"help"};
  override import_export_id = "help_topics";

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return global help topics for players.";
    "Topics are stored as topic_* properties: {name, summary, content, aliases, category, see_also}";
    {for_player, ?topic = ""} = args;
    my_topics = {};
    for prop in (properties(this))
      if (index(prop, "topic_") == 1)
        data = this.(prop);
        {name, summary, content, aliases, category, see_also} = data;
        t = $help:mk(name, summary, content, aliases, tosym(category), see_also);
        if (topic == "")
          my_topics = {@my_topics, t};
        elseif (t:matches(topic))
          return t;
        endif
      endif
    endfor
    return topic == "" ? my_topics | 0;
  endverb
endobject