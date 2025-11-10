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
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, dobj:name(), " has been granted programmer privileges and has been reparented to $prog.");
      dobj.location:announce(event);
    endif
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
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, dobj:name(), " has been granted builder privileges and has been reparented to $builder.");
      dobj.location:announce(event);
    endif
    "Confirm to wizard";
    player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " builder privileges and reparented them to $builder."));
  endverb
endobject