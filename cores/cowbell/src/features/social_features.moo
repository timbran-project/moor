object SOCIAL_FEATURES
  name: "Social Features"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Provides common social action verbs (nod, wave, bow, etc.) that can be added to a player's features to extend their ambient command environment.";
  override import_export_hierarchy = {"features"};
  override import_export_id = "social_features";

  verb nod (none any any) owner: HACKER flags: "rd"
    "HINT: at <whom> -- Nod at/to someone or just nod.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "" && (prepstr == "at" || prepstr == "to"))
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Nod at/to whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != TYPE_OBJ)
        event = $event:mk_error(player, "Nod at/to whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("nod", "nods"), " ", prepstr, " ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("nod", "nods"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb wave (none any any) owner: HACKER flags: "rd"
    "HINT: at <whom> -- Wave at/to someone or just wave.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "" && (prepstr == "at" || prepstr == "to"))
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Wave at/to whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != TYPE_OBJ)
        event = $event:mk_error(player, "Wave at/to whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("wave", "waves"), " ", prepstr, " ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("wave", "waves"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb bow (none any any) owner: HACKER flags: "rd"
    "HINT: to <whom> -- Bow to/at someone or just bow.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "" && (prepstr == "to" || prepstr == "at"))
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Bow to/at whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != TYPE_OBJ)
        event = $event:mk_error(player, "Bow to/at whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bow", "bows"), " ", prepstr, " ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("bow", "bows"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb bonk (any none none) owner: HACKER flags: "rd"
    "HINT: <whom> -- Bonk someone playfully.";
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
    if (!valid(target) || typeof(target) != TYPE_OBJ)
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

  verb oif (any none none) owner: HACKER flags: "rd"
    "HINT: -- Acknowledge a bonk to maintain cosmic balance.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = player:mk_say_event("Oif!");
    player.location:announce(event);
  endverb

  verb smile (none any any) owner: HACKER flags: "rd"
    "HINT: at <whom> -- Smile at/to someone or just smile.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    if (iobjstr && iobjstr != "" && (prepstr == "at" || prepstr == "to"))
      "Try to match the target";
      try
        target = $match:match_object(iobjstr, player);
      except e (ANY)
        event = $event:mk_error(player, "Smile at/to whom?");
        player:inform_current(event);
        return;
      endtry
      if (!valid(target) || typeof(target) != TYPE_OBJ)
        event = $event:mk_error(player, "Smile at/to whom?");
        player:inform_current(event);
        return;
      endif
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("smile", "smiles"), " ", prepstr, " ", $sub:i(), "."):with_iobj(target):with_this(player.location);
    else
      event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("smile", "smiles"), "."):with_this(player.location);
    endif
    player.location:announce(event);
  endverb

  verb frown (any none none) owner: HACKER flags: "rd"
    "HINT: -- Frown, showing displeasure.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("frown", "frowns"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb laugh (any none none) owner: HACKER flags: "rd"
    "HINT: -- Laugh out loud.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("laugh", "laughs"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb dance (any none none) owner: HACKER flags: "rd"
    "HINT: -- Dance joyfully.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("dance", "dances"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb shrug (any none none) owner: HACKER flags: "rd"
    "HINT: -- Shrug your shoulders.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("shrug", "shrugs"), " ", $sub:self_alt("your", $sub:p()), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb think (any any any) owner: HACKER flags: "rd"
    "HINT: <thought> -- Express a thought visibly.";
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
    "HINT: -- Ponder thoughtfully.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("ponder", "ponders"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb "applaud a*pplaud clap c*lap" (any none none) owner: HACKER flags: "rd"
    "HINT: -- Applaud or clap your hands.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("clap", "claps"), " ", $sub:self_alt("your", $sub:p()), " hands."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb cheer (any none none) owner: HACKER flags: "rd"
    "HINT: -- Cheer enthusiastically.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("cheer", "cheers"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb sigh (any none none) owner: HACKER flags: "rd"
    "HINT: -- Sigh deeply.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("sigh", "sighs"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb yawn (any none none) owner: HACKER flags: "rd"
    "HINT: -- Yawn tiredly.";
    caller != player && return E_PERM;
    if (!valid(player.location))
      return;
    endif
    event = $event:mk_social(player, $sub:nc(), " ", $sub:self_alt("yawn", "yawns"), "."):with_this(player.location);
    player.location:announce(event);
  endverb

  verb stretch (any none none) owner: HACKER flags: "rd"
    "HINT: -- Stretch your body.";
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
    "Paste a URL to share with optional link preview.";
    if (!valid(player.location))
      return;
    endif
    url = verb + argstr;
    "Fetch preview metadata";
    preview = `$url_utils:fetch_preview(url) ! ANY => false';
    event = $event:mk_url_share(player, $sub:nc(), " ", $sub:self_alt("share", "shares"), ": ", url):with_metadata('url, url):with_presentation_hint('inset);
    "Attach preview if we got useful data";
    if (typeof(preview) == TYPE_MAP && (preview["title"] || preview["description"] || preview["image"]))
      event = event:with_metadata('link_preview, preview);
    endif
    player.location:announce(event);
  endverb

  verb "@paste paste" (any any any) owner: HACKER flags: "rxd"
    "Paste multiline content to the room";
    if (!valid(player.location))
      return;
    endif
    content = player:read_multiline("Enter content to @paste");
    if (content == "@abort" || typeof(content) != TYPE_STR)
      player:inform_current($event:mk_info(player, "Paste aborted."));
      return;
    endif
    lines = content:split("\n");
    if (length(lines) > 25)
      player:inform_current($event:mk_error(player, "Paste content is greater than 25 lines, too long."));
      return;
    endif
    event = $event:mk_paste(player, $format.title:mk({$sub:nc(), " ", $sub:self_alt("paste", "pastes")}, 4), $format.code:mk(content)):with_presentation_hint('inset):with_group('paste);
    player.location:announce(event);
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for social actions.";
    {for_player, ?topic = ""} = args;
    my_topics = {$help:mk("socializing", "Social actions and gestures", "Express yourself with gestures and actions that others can see.\n\n`nod`, `wave`, `bow`, `smile`, `frown`, `laugh`, `dance`, `shrug`, `ponder`, `applaud`/`clap`, `cheer`, `sigh`, `yawn`, `stretch`, `bonk`, `oif`, `think`\n\nMost gestures can be directed at someone:\n\n`wave at Henri`\n`bow to Ryan`\n`bonk someone`\n\nThe `think` command shows a visible thought:\n\n`think I wonder what's for dinner` \u2192 _Ryan . o O ( I wonder what's for dinner )_\n\n**The bonk/oif balance**: When someone bonks you, tradition holds that you must say `oif` to acknowledge it. Failing to oif after being bonked is said to upset the cosmic bonk/oif balance, causing much trouble in the universe.", {"socials", "gestures", "actions"}, 'social, {"communicating", "emote"})};
    "If asking for all topics, just return overview";
    topic == "" && return my_topics;
    "Check if topic matches overview";
    for t in (my_topics)
      t:matches(topic) && return t;
    endfor
    "Try to generate help from verb HINT tags";
    verb_help = `$help_utils:verb_help_from_hint(this, topic, 'social) ! ANY => 0';
    typeof(verb_help) != TYPE_INT && return verb_help;
    return 0;
  endverb
endobject