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
  property topic_drop (owner: ARCH_WIZARD, flags: "rc") = {
    "drop",
    "Put something down",
    "Use `drop <thing>` to remove something from your inventory and leave it in the current room.",
    {},
    "basics",
    {"get", "inventory"}
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
  property topic_quit (owner: ARCH_WIZARD, flags: "rc") = {
    "@quit",
    "Disconnect",
    "Use `@quit` to disconnect from the game.\n\nYour character stays in the world but goes to sleep.",
    {"quit", "logout"},
    "basics",
    {}
  };
  property topic_say (owner: ARCH_WIZARD, flags: "rc") = {
    "say",
    "Speak to others",
    "Use `say <message>` or `\"<message>` to speak aloud. Everyone in the room hears you.\n\n`say Hello everyone!`\n`\"Hi there!`",
    {"talk", "speak", "\""},
    "social",
    {"emote", "communicating"}
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