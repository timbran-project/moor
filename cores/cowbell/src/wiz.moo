object WIZ
  name: "Generic Wizard"
  parent: PROG
  location: FIRST_ROOM
  owner: ARCH_WIZARD

  property test (owner: WIZ, flags: "r") = {};

  override description = "Generic wizard, parent of all wizards";
  override import_export_id = "wiz";

  verb "@programmer" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    "Grant programmer bit to a player";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can grant programmer privileges.");
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @programmer <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    if (dobj.programmer)
      player:inform_current($event:mk_error(player, dobj:name() + " is already a programmer."));
      return;
    endif
    "Check if player has a description";
    desc = `dobj:description() ! ANY => ""';
    if (!desc || desc == "")
      "Get pronouns for proper grammar";
      pronouns = `dobj:pronouns() ! E_VERBNF => $pronouns:mk('they, 'them, 'their, 'theirs, 'themself, false)';
      possessive = `pronouns.possessive ! ANY => "their"';
      question = "Grant " + dobj:name() + " programmer bit despite " + possessive + " lack of description?";
      "Use read() for confirmation";
      metadata = {{"input_type", "confirm"}, {"prompt", question}};
      response = read(player, metadata);
      if (typeof(response) != STR || response:lowercase() != "yes")
        player:inform_current($event:mk_error(player, "Programmer bit not granted."));
        return;
      endif
    endif
    "Grant programmer bit and reparent to $prog";
    dobj.programmer = true;
    chparent(dobj, $prog);
    "Create personal tools for the new programmer";
    owner_name = dobj:name();
    compass = create($architects_compass, dobj);
    compass.owner = dobj;
    compass.name = owner_name + "'s " + $architects_compass.name;
    compass.aliases = $architects_compass.aliases;
    compass:moveto(dobj);
    visor = create($data_visor, dobj);
    visor.owner = dobj;
    visor.name = owner_name + "'s " + $data_visor.name;
    visor.aliases = $data_visor.aliases;
    visor:moveto(dobj);
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted programmer privileges and ", $sub:verb_have(), " been reparented to $prog."):with_this(dobj.location);
      dobj.location:announce(event);
      "Announce tools being granted";
      tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass and a Data Visor."):with_this(dobj.location);
      dobj.location:announce(tools_event);
    endif
    "Send private instructional message to new programmer";
    dobj:tell($event:mk_info(dobj, "In your inventory there are now an Architect's Compass and a Data Visor - powerful instruments bonded to you alone. Wear them to activate their capabilities: the Compass for building and spatial construction, the Visor for analyzing, writing code, creating objects, adding properties, and shaping the world's logic. Guard them carefully, as they grant significant power over the world."));
    "Confirm to wizard";
    player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " programmer privileges and reparented them to $prog."));
  endverb

  verb "@builder" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    "Grant builder status to a player";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can grant builder status.");
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @builder <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    if (isa(dobj, $builder))
      player:inform_current($event:mk_error(player, dobj:name() + " is already a builder (or descendant of $builder)."));
      return;
    endif
    "Check if player has a description";
    desc = `dobj:description() ! ANY => ""';
    if (!desc || desc == "")
      "Get pronouns for proper grammar";
      pronouns = `dobj:pronouns() ! E_VERBNF => $pronouns:mk('they, 'them, 'their, 'theirs, 'themself, false)';
      possessive = `pronouns.possessive ! ANY => "their"';
      question = "Grant " + dobj:name() + " builder status despite " + possessive + " lack of description?";
      "Use read() for confirmation";
      metadata = {{"input_type", "confirm"}, {"prompt", question}};
      response = read(player, metadata);
      if (typeof(response) != STR || response:lowercase() != "yes")
        player:inform_current($event:mk_error(player, "Builder status not granted."));
        return;
      endif
    endif
    "Reparent to $builder";
    chparent(dobj, $builder);
    "Create personal compass for the new builder";
    owner_name = dobj:name();
    compass = create($architects_compass, dobj);
    compass.owner = dobj;
    compass.name = owner_name + "'s " + $architects_compass.name;
    compass.aliases = $architects_compass.aliases;
    compass:moveto(dobj);
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted builder privileges and ", $sub:verb_have(), " been reparented to $builder."):with_this(dobj.location);
      dobj.location:announce(event);
      "Announce tool being granted";
      tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass."):with_this(dobj.location);
      dobj.location:announce(tools_event);
    endif
    "Send private instructional message to new builder";
    dobj:tell($event:mk_info(dobj, "In your inventory there is now an Architect's Compass - a powerful instrument bonded to you alone. Wear it to activate its capabilities for building and spatial construction. Guard it carefully, as it grants significant power over the world."));
    "Confirm to wizard";
    player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " builder privileges and reparented them to $builder."));
  endverb
endobject