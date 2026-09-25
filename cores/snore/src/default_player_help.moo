object DEFAULT_PLAYER_HELP [
  import_export_id -> "default_player_help"
]
  name: "Default Player Help"
  parent: GENERIC_HELP
  owner: HACKER
  readable: true

  property "@adddict" (owner: #2, flags: "r") = {"*forward*", "@addword"};
  property "@addroom" (owner: HACKER, flags: "rc") = {"*forward*", "@rooms"};
  property "@addsubmitted" (owner: #2, flags: "r") = {"*forward*", "@submitted"};
  property "@addword" (owner: HACKER, flags: "rc") = {
    "Syntax: @addword <word or words>",
    "        @addword object.property",
    "        @addword object:verb",
    "",
    "Will add all words found and unknown into your personal dictionary.",
    "Your dictionary is stored in a property named \".dict\"."
  };
  property "@at" (owner: HACKER, flags: "rc") = {
    " '@at' - Find out where everyone is.",
    " '@at <player>' - Find out where <player> is, and who else is there.",
    " '@at <obj>' - Find out who else is at the same place as <obj>.",
    " '@at <place>' - Find out who is at the place.",
    " The place can be given by number, or it can be a name from your @rooms list.",
    " '@at #-1' - Find out who is at #-1.",
    " '@at me' - Find out who is in the room with you.",
    " '@at home' - Find out who is at your home.",
    "Each occupied location is sent as one complete line. Your client controls word wrapping."
  };
  property "@complete" (owner: HACKER, flags: "rc") = {
    "Syntax:  @complete prefix",
    "",
    "This verb is part of the MOO spelling checker.  It will show you all the words in the dictionary that start with the prefix letters you specify.  You should be specific as to what you're looking for (for example, you might use @complete comput, rather than @complete co) in order to avoid getting an excessive number of words output.",
    "",
    "Refer to help spelling for more information."
  };
  property "@cspell" (owner: HACKER, flags: "rc") = {
    "Syntax: @cspell <any number of words>",
    "        @cspell object.property",
    "        @cspell object:verb",
    "",
    "Like @spell, but attempts to guess at correct spellings for words it believes are spelled incorrectly.   This verb can be quite slow, so correcting large chunks of text may not be a good idea.",
    "",
    "Refer to help spelling and help @spell for more information."
  };
  property "@find" (owner: HACKER, flags: "rc") = {
    "  @find #<object>   - locate an object by number",
    "  @find <player>    - locate a player",
    "  @find :<verb>     - locate a verb on an object in your vicinity",
    "  @find .<property> - locate a property on objects in your vicinity.",
    "  @find ?<topic>    - locate a help topic on a help database.",
    "",
    "For example, '@find frand' shows Frand's number and location. '@find :jump' lists every object in the same room as you (including you and the room itself) which has a 'jump' verb.  For properties and verbs, output is a list of pairs of objects: each object on which the property or verb exists, and the ancestor that actually defines it."
  };
  property "@go" (owner: HACKER, flags: "rc") = {"*forward*", "@move"};
  property "@join" (owner: HACKER, flags: "rc") = {"*forward*", "@move"};
  property "@move" (owner: HACKER, flags: "rc") = {
    "  @move <obj> to <location>  - teleport an object to a given location",
    "  @go <location>             - teleport yourself to a given location",
    "  @join <player>             - teleport yourself to a player's location",
    "",
    "You can teleport an object (if it allows this) to any location that will accept it. For example, `@move rock to #11' will teleport the rock to the closet. `@move #123 to here' will move object #123 to your location. `@go home' will teleport you home. `@join yduj' will teleport you to yduJ's location. You can also teleport an object to #-1, which is nowhere.",
    "",
    "See help teleport-messages for information on customizing the text that appears",
    "(both to you and to others in the vicinity) when you teleport.",
    "See also help @rooms for information on naming rooms for convenient movement.",
    "If @move doesn't work and you own the place where the object is located, try using @eject instead."
  };
  property "@rmdict" (owner: #2, flags: "r") = {"*forward*", "@rmword"};
  property "@rmroom" (owner: HACKER, flags: "rc") = {"*forward*", "@rooms"};
  property "@rmsubmitted" (owner: #2, flags: "r") = {"*forward*", "@submitted"};
  property "@rmword" (owner: HACKER, flags: "rc") = {
    "Usage: @rmword <word or words>",
    "",
    "Will remove all words found from your personal dictionary, stored in player property \".dict\"."
  };
  property "@rooms" (owner: HACKER, flags: "rc") = {
    "When you aren't in the same room with an object, you have to refer to it by number. When teleporting, that means you usually have to give your destination as a number. To avoid this, the default player class provides a way for you to store a database of rooms by name. If the library is in your list of rooms, you can just '@go library' to teleport there. Or '@move book to lib' to teleport an object there.",
    "",
    "  @rooms                     - see a list of the rooms you know by name",
    "  @addr*oom <name> <number>  - remember a room by name",
    "  @rmr*oom  <name>           - forget about a room's name",
    "",
    "For example, to add the kitchen to your database of rooms, type '@addr Kitchen #24'. To remove it, type '@rmr kitchen'."
  };
  property "@spell" (owner: HACKER, flags: "rc") = {
    "Syntax: @spell <any number of words>",
    "           - will check the words from the command line.",
    "        @spell object.property",
    "           - will spellcheck the contents of a prop. Must be a string or",
    "             list of strings.",
    "        @spell object:verb",
    "           - will check everything within quoted strings in a verb. E.g.,",
    "             only the quoted part of player:tell(\"Spellchecking is fun.\");",
    "             will be examined for errors.",
    "",
    "Refer to Help Spelling for general information about the spell checker."
  };
  property "@spellmessages" (owner: HACKER, flags: "rc") = {
    "Syntax: @spellproperties <object>",
    "        @spellmessages <object>",
    "These commands will spellcheck all properties or messages, respectively, on an object.  The object must be owned or readable by the user.  Messages and properties will be spellchecked if they contain a string or a list of strings; others will be ignored.",
    "",
    "Refer to help spelling for general information about the spellchecker."
  };
  property "@spellproperties" (owner: HACKER, flags: "rc") = {"*forward*", "@spellmessages"};
  property "@submitted" (owner: #2, flags: "r") = {
    "@submitted lists words awaiting approval for the main spelling dictionary.",
    "@addsubmitted reviews and adds words. @rmsubmitted removes a word from the pending list.",
    "These commands require wizard status or membership in $spell.trusted.",
    "Bulk review uses the list present when you start. Clearing that batch preserves words submitted later.",
    "If you lose permission while answering a prompt, the command stops. Earlier completed changes can remain."
  };
  property "@ways" (owner: HACKER, flags: "rc") = {
    "'@ways', '@ways <room>' - List any obvious exits from the given room (or this room, if none is given)."
  };
  property "default-player-index" (owner: HACKER, flags: "rc") = {"*index*", "Default Player Help Topics"};
  property spelling (owner: HACKER, flags: "rc") = {
    "The MOO has a built in spelling checker and dictionary.  There are several player commands which access the database, as well as some programming features available.  Additional documentation is available under individual commands.",
    "",
    "The current dictionary only contains about 20,000 words, and thus is somewhat incomplete.  Words may be added to a personal dictionary, as well as to the main dictionary (only a few people can add to the main dictionary).",
    "",
    "@spell a word or phrase - Spell check a word or phrase.",
    "@spell thing.prop - Spell check a property. The value must be a string or a list of strings.",
    "@spell thing:verb - Spell check a verb. Only the quoted strings in the verb are checked.",
    "@spellproperties object - Spell check all text properties of an object.",
    "@spellmessages object - Spell check only message properties of an object.",
    "@cspell word - Spell check a word, and if it is not in the dictionary, offers suggestions about what the right spelling might be. This actually works with thing.prop and thing:verb too, but it is too slow to be useful--it takes maybe 30 seconds per unknown word.",
    "@complete prefix - List all the word in the dictionary which begin with the given prefix. For example, '@complete zoo' lists zoo, zoologist, zoology, and zoom.",
    "@addword word - Add a word to your personal dictionary.",
    "@rmword word - Remove a word from your personal dictionary.",
    "@adddict word - Add a word to the global dictionary.",
    "@rmdict word - Remove a word from the global dictionary.",
    "",
    "For programmers, the verb $spell:random() is available -- returns a word, at random, from the dictionary.",
    "",
    "Ask the administrators of this MOO about local feature policies."
  };
  property "teleport-messages" (owner: HACKER, flags: "rc") = {
    "Teleporting using @go, @move, or @join causes various messages to appear. The messages are defined on you as properties. Here are the messages, who sees them, and when.",
    "",
    " when you teleport -  yourself      a player        a thing",
    "",
    "           you see -  self_port     player_port     thing_port",
    "        others see -  oself_port    oplayer_port    othing_port",
    "  destination sees -  self_arrive   player_arrive   thing_arrive",
    "   teleportee sees -                victim_port     object_port",
    "",
    "When you @join a player, your join message is printed to you.",
    "",
    "You can set the messages with commands like '@oself_port me is \"vanishes in a shimmering haze.\"', '@join me is \"You visit %n.\"', and so on.",
    "",
    "The messages to you are printed as they stand. The messages to others are printed after your name. If you set a message to \"\", the null string, nothing will print for that message. But if you have a non-empty message which does not include your name, then your name will be added in front of the message. You can use the usual pronoun substitutions, like '%n' to refer to the object you are teleporting. You can also use the special substitutions %<from room> and %<to room> to refer to the original and destination rooms for the teleport.",
    "",
    "If you are leaving your name out of the messages, and relying on its being inserted automatically, you have to be careful about the substitutions you use. If Frand has an oself_port message \"jumps to %<to room>.\", for example, and Frand teleports to Frand's MOOhome, the message printed will be \"jumps to Frand's MOOhome.\" My name is there, so it isn't added in. If you want to include your name as a substitution, the one to use is %t, 'this'. \"%t jumps to %<to room>.\" will work."
  };

  override aliases (owner: HACKER, flags: "rc") = {"Default Player Help"};
  override index_cache (owner: HACKER, flags: "r") = {"default-player-index"};
  override object_size (owner: HACKER, flags: "r") = {26603, 1084848672};
endobject
