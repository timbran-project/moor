object SOCIAL_FEATURES
  name: "Social Features"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Provides common social action verbs (nod, wave, bow, etc.) that can be added to a player's features to extend their ambient command environment.";
  override import_export_hierarchy = {"features"};
  override import_export_id = "social_features";

  verb nod (any none none) owner: HACKER flags: "rd"
    "Nod at someone or just nod.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (dobjstr && dobjstr != "")
      "Try to match the target";
      try
        target = $match:match_object(dobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Nod at whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != OBJ)
        event = $event:mk_error(player, "Nod at whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("nod", "nods"), " at ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("nod", "nods"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb wave (any at this) owner: HACKER flags: "rd"
    "Wave at someone or just wave.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "")
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Wave at whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != OBJ)
        event = $event:mk_error(player, "Wave at whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("wave", "waves"), " at ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("wave", "waves"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb bow (any at this) owner: HACKER flags: "rd"
    "Bow to someone or just bow.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "")
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Bow to whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != OBJ)
        event = $event:mk_error(player, "Bow to whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bow", "bows"), " to ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bow", "bows"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb bonk (any none none) owner: HACKER flags: "rd"
    "Bonk someone (playfully).";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Bonk whom?");
      player:inform_current(event);
      return;
    endif
    try
      target = $match:match_object(dobjstr, player);
    except e (ANY)
      event = $event:mk_error(player, "Bonk whom?");
      player:inform_current(event);
      return;
    endtry
    if (!valid(target) || typeof(target) != OBJ)
      event = $event:mk_error(player, "Bonk whom?");
      player:inform_current(event);
      return;
    endif
    if (target == player)
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bonk", "bonks"), " ", $sub:self_alt("yourself", "themselves"), "."):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bonk", "bonks"), " ", $sub:d(), "."):with_dobj(target):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb smile (any at this) owner: HACKER flags: "rd"
    "Smile at someone or just smile.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "")
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Smile at whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != OBJ)
        event = $event:mk_error(player, "Smile at whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("smile", "smiles"), " at ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("smile", "smiles"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb frown (any none none) owner: HACKER flags: "rd"
    "Frown, showing displeasure.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("frown", "frowns"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb laugh (any none none) owner: HACKER flags: "rd"
    "Laugh out loud.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("laugh", "laughs"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb dance (any none none) owner: HACKER flags: "rd"
    "Dance joyfully.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("dance", "dances"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb shrug (any none none) owner: HACKER flags: "rd"
    "Shrug your shoulders.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("shrug", "shrugs"), " ", $sub:self_alt("your", $sub:p()), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb think (any any any) owner: HACKER flags: "rd"
    "Express a thought visibly.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (!argstr || argstr == "")
      event = $event:mk_error(player, "Think what?");
      player:inform_current(event);
      return;
    endif
    event = $event:mk_social(player, player:name(), " . o O ( ", argstr, " )"):with_this(player.location);
    player.location:announce(event);
  endverb

  verb ponder (any none none) owner: HACKER flags: "rd"
    "Ponder thoughtfully.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("ponder", "ponders"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb "applaud a*pplaud clap c*lap" (any none none) owner: HACKER flags: "rd"
    "Applaud or clap your hands.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("clap", "claps"), " ", $sub:self_alt("your", $sub:p()), " hands."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb cheer (any none none) owner: HACKER flags: "rd"
    "Cheer enthusiastically.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("cheer", "cheers"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb sigh (any none none) owner: HACKER flags: "rd"
    "Sigh deeply.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("sigh", "sighs"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb yawn (any none none) owner: HACKER flags: "rd"
    "Yawn tiredly.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("yawn", "yawns"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb stretch (any none none) owner: HACKER flags: "rd"
    "Stretch your body.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("stretch", "stretches"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb "|*" (any any any) owner: HACKER flags: "rxd"
    "Paste a single line of content.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    content = verb[2..$] + " " + argstr;
    event = $event:mk_pasteline(player, $sub:nc(), " | ", content);
    player.location:announce(event);
  endverb

  verb "http://* https://*" (any any any) owner: HACKER flags: "rxd"
    "Paste a URL to share";
    if (!valid(player.location))
      return;
    endif
    url = verb + argstr;
    "TODO: link markup";
    event = $event:mk_url_share(player, $sub:nc(), " shares: ", url):with_metadata('url, url);
    player.location:announce(event);
  endverb

  verb "@paste paste" (any any any) owner: HACKER flags: "rxd"
    "Paste multiline content to the room";
    if (!valid(player.location))
      return;
    endif
    content = player:read_multiline("Enter content to @paste");
    if (content == "@abort" || typeof(content) != STR)
      player:inform_current($event:mk_info(player, "Paste aborted."));
      return;
    endif
    lines = content:split("\n");
    if (length(lines) > 25)
      player:inform_current(player, $event:mk_error(player, "Paste content is greater than 25 lines, too long."));
      return;
    endif
    event = $event:mk_paste(player, $format.title:mk({$sub:nc(), " ", $sub:self_alt("paste", "pastes")}, 4), $format.code:mk(content)):with_presentation_hint('inset);
    player.location:announce(event);
  endverb
endobject