object SITTABLE
  name: "Sittable"
  parent: THING
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  override description = "A prototype for objects that can be sat upon. Set .seats to control capacity, .squeeze for extra squeezable spots (-1 for rigid furniture), .sitting_verb and .sitting_prep for customization.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "sittable";

  override aliases = {"sittable"};

  override object_documentation = {
    "# Sittable Objects",
    "",
    "## Overview",
    "",
    "Sittable objects are furniture that players can sit on. They track who is sitting and manage capacity with optional squeeze mechanics. Inherits from Thing.",
    "",
    "## Properties",
    "",
    "### seats",
    "",
    "Maximum number of players who can sit comfortably (default: 2).",
    "",
    "### squeeze",
    "",
    "Extra spots that can be squeezed in beyond capacity. When exceeded, the first sitter is dumped.",
    "",
    "- `0`: No squeezing allowed (default)",
    "- `-1`: Rigid furniture, no one can exceed capacity",
    "- `N`: Allow N extra players before squeezing someone off",
    "",
    "### sitting_verb and sitting_prep",
    "",
    "Customize how sitting is described:",
    "",
    "- `sitting_verb`: Verb used in description (default: \"sitting\")",
    "- `sitting_prep`: Preposition used (default: \"on\")",
    "",
    "Examples: \"perched on\", \"lounging in\", \"curled up on\"",
    "",
    "### Message Properties",
    "",
    "All messages use $sub template substitution and can be customized via @set-message:",
    "",
    "- `sit_msg`: Shown when sitting (default: \"Alice sits on the couch.\")",
    "- `stand_msg`: Shown when standing (default: \"Alice stands up from the couch.\")",
    "- `already_sitting_msg`: Error when already sitting",
    "- `not_sitting_msg`: Error when not sitting",
    "- `no_room_msg`: Error when furniture is full",
    "- `cant_reach_msg`: Error when not in same room",
    "- `squeezed_msg`: Shown when someone is squeezed off",
    "- `dumped_msg`: Shown when someone is dumped off (furniture moves)",
    "",
    "## Commands",
    "",
    "### sit on <furniture>",
    "",
    "```",
    "sit on couch",
    "```",
    "",
    "Sit on the furniture. You must be in the same room.",
    "",
    "### stand from <furniture>",
    "",
    "```",
    "stand from couch",
    "```",
    "",
    "Stand up from the furniture.",
    "",
    "## Behavior",
    "",
    "- Sitters are dumped when furniture moves to a different room",
    "- Sitters are removed from the list when they leave the room",
    "- The description automatically shows who is sitting",
    "- Fires `'on_sit` and `'on_stand` triggers for reactions",
    "",
    "## Example: Creating a Cozy Armchair",
    "",
    "```moo",
    "chair = create($sittable);",
    "chair:set_name(\"a cozy armchair\");",
    "chair.description = \"A worn leather armchair with plush cushions.\";",
    "chair.seats = 1;",
    "chair.squeeze = -1;  // Rigid - only one person fits",
    "chair.sitting_verb = \"curled up\";",
    "chair.sitting_prep = \"in\";",
    "```"
  };

  property sitting (owner: HACKER, flags: "r") = {};
  property seats (owner: HACKER, flags: "r") = 2;
  property squeeze (owner: HACKER, flags: "rc") = 0;
  property sitting_verb (owner: HACKER, flags: "rc") = "sitting";
  property sitting_prep (owner: HACKER, flags: "rc") = "on";

  property sit_msg (owner: HACKER, flags: "rc") = {
    <SUB, .type = 'actor, .capitalize = true>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "sit", .for_others = "sits", .capitalize = false>,
    " on ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property stand_msg (owner: HACKER, flags: "rc") = {
    <SUB, .type = 'actor, .capitalize = true>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "stand", .for_others = "stands", .capitalize = false>,
    " up from ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property already_sitting_msg (owner: HACKER, flags: "rc") = {
    "You're already sitting on ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property not_sitting_msg (owner: HACKER, flags: "rc") = {
    "You aren't sitting on ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property no_room_msg (owner: HACKER, flags: "rc") = {
    "There's no room on ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property cant_reach_msg (owner: HACKER, flags: "rc") = {
    "You can't reach ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    " from here."
  };
  property squeezed_msg (owner: HACKER, flags: "rc") = {
    <SUB, .type = 'dobj, .capitalize = true>,
    " ",
    <SUB, .type = 'verb_be, .capitalize = false>,
    " squeezed off ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };
  property dumped_msg (owner: HACKER, flags: "rc") = {
    <SUB, .type = 'dobj, .capitalize = true>,
    " ",
    <SUB, .type = 'verb_be, .capitalize = false>,
    " dumped off ",
    <SUB, .binding_name = 'This, .type = 'article_the, .capitalize = false>,
    "."
  };

  verb sit (any on this) owner: HACKER flags: "rxd"
    "Handle 'sit on <furniture>' command.";
    if (player in this.sitting)
      event = $event:mk_error(player, @this.already_sitting_msg):with_this(this);
      player:inform_current(event);
      return;
    endif
    if (player.location != this.location)
      event = $event:mk_error(player, @this.cant_reach_msg):with_this(this);
      player:inform_current(event);
      return;
    endif
    "Check capacity";
    if (this.squeeze < 0 && length(this.sitting) >= this.seats)
      event = $event:mk_error(player, @this.no_room_msg):with_this(this);
      player:inform_current(event);
      return;
    endif
    "Add player to sitting list";
    this.sitting = {@this.sitting, player};
    "Announce to room";
    event = $event:mk_act(player, @this.sit_msg):with_this(this);
    this.location:announce(event);
    "Fire trigger for reactions (after announcement)";
    this:fire_trigger('on_sit, ['Actor -> player]);
    "Squeeze check - if over capacity, dump the first person";
    if (length(this.sitting) > this.seats + max(0, this.squeeze))
      victim = this.sitting[1];
      this:dump_sitter(victim);
    endif
  endverb

  verb stand (any from this) owner: HACKER flags: "rxd"
    "Handle 'stand from <furniture>' command.";
    if (!(player in this.sitting))
      event = $event:mk_error(player, @this.not_sitting_msg):with_this(this);
      player:inform_current(event);
      return;
    endif
    "Remove from sitting list";
    pos = player in this.sitting;
    this.sitting = listdelete(this.sitting, pos);
    "Announce to room";
    event = $event:mk_act(player, @this.stand_msg):with_this(this);
    this.location:announce(event);
    "Fire trigger for reactions (after announcement)";
    this:fire_trigger('on_stand, ['Actor -> player]);
  endverb

  verb add_sitter (this none this) owner: HACKER flags: "rxd"
    "Programmatically add an actor to sit. Returns true if successful.";
    {who, ?silent = false} = args;
    if (who in this.sitting)
      return false;
    endif
    if (who.location != this.location)
      return false;
    endif
    if (this.squeeze < 0 && length(this.sitting) >= this.seats)
      return false;
    endif
    this.sitting = {@this.sitting, who};
    this:fire_trigger('on_sit, ['Actor -> who]);
    if (!silent && valid(this.location))
      event = $event:mk_act(who, @this.sit_msg):with_this(this);
      this.location:announce(event);
    endif
    "Squeeze check";
    if (length(this.sitting) > this.seats + max(0, this.squeeze))
      victim = this.sitting[1];
      this:dump_sitter(victim);
    endif
    return true;
  endverb

  verb remove_sitter (this none this) owner: HACKER flags: "rxd"
    "Programmatically remove an actor from sitting. Returns true if successful.";
    {who, ?silent = false} = args;
    pos = who in this.sitting;
    if (!pos)
      return false;
    endif
    this.sitting = listdelete(this.sitting, pos);
    this:fire_trigger('on_stand, ['Actor -> who]);
    if (!silent && valid(this.location))
      event = $event:mk_act(who, @this.stand_msg):with_this(this);
      this.location:announce(event);
    endif
    return true;
  endverb

  verb has_room (this none this) owner: HACKER flags: "rxd"
    "Check if furniture has room for another sitter.";
    if (this.squeeze < 0)
      return length(this.sitting) < this.seats;
    endif
    return true;
  endverb

  verb is_sitting (this none this) owner: HACKER flags: "rxd"
    "Check if a specific actor is sitting on this furniture.";
    {who} = args;
    return who in this.sitting;
  endverb

  verb action_sit (this none this) owner: HACKER flags: "rxd"
    "Action handler for reactions: make actor sit on this furniture.";
    {who, context} = args;
    this:add_sitter(who);
  endverb

  verb action_stand (this none this) owner: HACKER flags: "rxd"
    "Action handler for reactions: make actor stand from this furniture.";
    {who, context} = args;
    this:remove_sitter(who);
  endverb

  verb dump_sitter (none none none) owner: HACKER flags: "rxd"
    "Remove a sitter and announce they were squeezed off.";
    {who, ?use_dumped = false} = args;
    pos = who in this.sitting;
    !pos && return;
    this.sitting = listdelete(this.sitting, pos);
    "Fire trigger for reactions";
    trigger_name = use_dumped ? 'on_sittable_dump | 'on_sittable_squeeze;
    this:fire_trigger(trigger_name, ['Actor -> who]);
    "Announce";
    msg = use_dumped ? this.dumped_msg | this.squeezed_msg;
    event = $event:mk_info(who, @msg):with_dobj(who):with_this(this);
    this.location:announce(event);
  endverb

  verb dump_all_sitters (none none none) owner: HACKER flags: "rxd"
    "Dump all sitters when furniture moves.";
    length(this.sitting) == 0 && return;
    "Fire trigger and announce for each sitter being dumped";
    for who in (this.sitting)
      this:fire_trigger('on_sittable_dump, ['Actor -> who]);
      event = $event:mk_info(who, @this.dumped_msg):with_dobj(who):with_this(this);
      this.location:announce(event);
    endfor
    this.sitting = {};
  endverb

  verb sitters_string (none none none) owner: HACKER flags: "rxd"
    "Return a string describing who is sitting, or empty if nobody.";
    length(this.sitting) == 0 && return "";
    names = { sitter:name() for sitter in (this.sitting) };
    name_list = $list_proto:english_list(names);
    verb = length(this.sitting) == 1 ? "is" | "are";
    return name_list + " " + verb + " " + this.sitting_verb + " " + this.sitting_prep + " it.";
  endverb

  verb description (none none none) owner: HACKER flags: "rxd"
    "Return description, appending sitter info if any.";
    desc = pass(@args);
    sitters = this:sitters_string();
    length(sitters) == 0 && return desc;
    typeof(desc) == LIST && return {@desc, sitters};
    return desc + " " + sitters;
  endverb

  verb moveto (none none none) owner: HACKER flags: "rxd"
    "Dump all sitters when furniture moves.";
    {dest} = args;
    "Only dump if actually moving to a different location";
    if (valid(this.location) && dest != this.location)
      this:dump_all_sitters("dumped");
    endif
    return pass(@args);
  endverb

  verb exitfunc (none none none) owner: HACKER flags: "rxd"
    "Remove departing player from sitting list.";
    {who} = args;
    pos = who in this.sitting;
    pos && (this.sitting = listdelete(this.sitting, pos));
    return pass(@args);
  endverb

  verb test_sitting (none none none) owner: HACKER flags: "rxd"
    "Test basic sitting functionality.";
    test_obj = this:create(false);
    test_obj.name = "test bench";
    test_obj.seats = 2;
    test_obj.squeeze = 0;
    "Initially empty";
    length(test_obj.sitting) == 0 || raise(E_ASSERT, "Should start empty");
    "Add a sitter directly";
    test_obj.sitting = {player};
    length(test_obj.sitting) == 1 || raise(E_ASSERT, "Should have 1 sitter");
    "Check sitters_string";
    sitter_desc = test_obj:sitters_string();
    index(sitter_desc, "sitting on it") || raise(E_ASSERT, "Should mention sitting: " + sitter_desc);
    "Remove sitter";
    test_obj.sitting = {};
    test_obj:sitters_string() == "" || raise(E_ASSERT, "Should be empty string");
    "Clean up";
    test_obj:destroy();
    return true;
  endverb

endobject
