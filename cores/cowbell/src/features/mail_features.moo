object MAIL_FEATURES
  name: "Mail Features"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Provides mail commands (mail, send, compose) for players.";
  override import_export_id = "mail_features";
  override import_export_hierarchy = {"features"};

  verb mail (none none none) owner: ARCH_WIZARD flags: "rxd"
    "HINT: -- Check your mailbox for letters.";
    mailbox = player:find_mailbox();
    if (!valid(mailbox))
      "Create mailbox in mail room";
      mailbox = create($mailbox, player);
      mailbox.name = player.name + "'s mailbox";
      move(mailbox, $mail_room);
      player:inform_current($event:mk_info(player, "A new mailbox has been set up for you in the Mail Room."));
    endif
    mailbox:mail();
  endverb

  verb compose (any any any) owner: ARCH_WIZARD flags: "rxd"
    "HINT: [<subject>] [to <player>] -- Create a new letter for writing.";
    letter = create($letter, player);
    "Set subject if provided";
    if (dobjstr && dobjstr != "")
      letter.name = dobjstr;
    else
      letter.name = "letter";
    endif
    "Set addressee if 'to' preposition used with valid player";
    if (prepstr == "to" && valid(iobj) && is_player(iobj))
      letter.addressee = iobj;
      letter.author = player;
    endif
    move(letter, player);
    "Build confirmation message";
    if (valid(letter.addressee))
      if (letter.name != "letter")
        player:inform_current($event:mk_info(player, "You have a letter titled '", letter.name, "' addressed to ", letter.addressee.name, ". Write on it to compose your message."));
      else
        player:inform_current($event:mk_info(player, "You have a letter addressed to ", letter.addressee.name, ". Write on it to compose your message."));
      endif
    else
      player:inform_current($event:mk_info(player, "You have a fresh letter ready to write on."));
    endif
  endverb

  verb send (any any any) owner: ARCH_WIZARD flags: "rxd"
    "HINT: <letter> [to <player>] -- Send a letter to someone.";
    if (!valid(dobj) || !isa(dobj, $letter))
      player:inform_current($event:mk_error(player, "Send what letter?"));
      return;
    endif
    if (dobj.location != player)
      player:inform_current($event:mk_error(player, "You're not holding that letter."));
      return;
    endif
    "Determine recipient - explicit or from letter";
    recipient = #-1;
    if (prepstr == "to" && valid(iobj) && is_player(iobj))
      recipient = iobj;
    elseif (valid(dobj.addressee) && is_player(dobj.addressee))
      recipient = dobj.addressee;
    else
      player:inform_current($event:mk_error(player, "Send the letter to whom? Use: send <letter> to <player>"));
      return;
    endif
    "Find recipient's mailbox";
    recipient_mailbox = recipient:find_mailbox();
    if (!valid(recipient_mailbox))
      player:inform_current($event:mk_error(player, recipient.name, " doesn't have a mailbox."));
      return;
    endif
    "Address and seal the letter";
    dobj.addressee = recipient;
    dobj.sealed = true;
    dobj.sent_at = time();
    if (!valid(dobj.author))
      dobj.author = player;
    endif
    "Deposit in their mailbox";
    move(dobj, recipient_mailbox);
    player:inform_current($event:mk_info(player, "You send ", dobj.name, " to ", recipient.name, "."));
    "Notify recipient if online";
    if (recipient in connected_players() && recipient != player)
      event = $event:mk_info(recipient, "*You have new mail from ", player.name, ".*");
      event = event:with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot});
      `recipient:tell(event) ! ANY';
    endif
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for mail commands.";
    {for_player, ?topic = ""} = args;
    "Main overview topic";
    overview = $help:mk("mail", "Mail commands", "Send and receive letters from other players:\n\n`mail` - Check your mailbox\n`compose` - Create a new letter\n`send` - Send a letter to someone\n\nLetters can be written on, sealed, and delivered to mailboxes.", {"letters", "mailbox"}, 'mail, {});
    "If asking for all topics, just return overview";
    topic == "" && return {overview};
    "Check if topic matches overview";
    overview:matches(topic) && return overview;
    "Try to generate help from verb HINT tags";
    verb_help = `$help_utils:verb_help_from_hint(this, topic, 'mail) ! ANY => 0';
    typeof(verb_help) != INT && return verb_help;
    return 0;
  endverb
endobject
