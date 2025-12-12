object LETTER
  name: "Generic Letter"
  parent: NOTE
  location: PROTOTYPE_BOX
  owner: TEST_PLAYER
  fertile: true
  readable: true

  property addressee (owner: TEST_PLAYER, flags: "rc") = #-1;
  property author (owner: TEST_PLAYER, flags: "rc") = #-1;
  property read_at (owner: TEST_PLAYER, flags: "rc") = 0;
  property sealed (owner: TEST_PLAYER, flags: "rc") = 0;
  property sent_at (owner: TEST_PLAYER, flags: "rc") = 0;
  override aliases = {"letter"};
  override object_documentation = "A letter is a note with communication metadata: author, addressee, timestamps, and sealing. When sealed, only the addressee can read it.";
  override import_export_hierarchy = {"messaging"};
  override import_export_id = "letter";

  verb can_read (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if accessor can read this letter. Sealed letters are addressee-only.";
    {accessor} = args;
    "If not sealed, use parent's logic";
    if (!this.sealed)
      return pass(@args);
    endif
    "Sealed: only addressee (or author) can read";
    if (accessor == this.addressee || accessor == this.author)
      return ['allowed -> true, 'reason -> {}];
    endif
    return ['allowed -> false, 'reason -> "This letter is sealed and addressed to someone else."];
  endverb

  verb action_read (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor reads this letter. Always silent for privacy.";
    set_task_perms(this.owner);
    {who, context} = args;
    !this:can_read(who)['allowed] && return false;
    return this:do_read(who, true);
  endverb

  verb do_read (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display the letter with metadata and record when it was read.";
    caller != this && raise(E_PERM, "do_read must be called by this object");
    {who, ?silent = false} = args;
    "Record first read time";
    if (this.read_at == 0)
      this.read_at = time();
    endif
    "Build letter display";
    parts = {};
    "Title/subject";
    subject = this.name != "letter" ? this.name | "(no subject)";
    parts = {@parts, $format.title:mk(subject)};
    "From/To metadata";
    meta_lines = {};
    if (valid(this.author))
      meta_lines = {@meta_lines, "From: " + this.author.name};
    endif
    if (valid(this.addressee))
      meta_lines = {@meta_lines, "To: " + this.addressee.name};
    endif
    if (this.sent_at > 0)
      meta_lines = {@meta_lines, "Sent: " + ctime(this.sent_at)};
    endif
    if (length(meta_lines) > 0)
      parts = {@parts, meta_lines:join(" | ")};
      parts = {@parts, ""};
    endif
    "Content";
    text = this.text;
    if (length(text) == 0)
      parts = {@parts, "(blank)"};
    else
      parts = {@parts, text:join("\n")};
    endif
    "Display";
    content = $format.block:mk(@parts);
    event = $event:mk_info(who, content):with_presentation_hint('inset);
    event = event:with_metadata('preferred_content_types, {this.content_type});
    who:inform_current(event);
    "Announce to room";
    if (!silent && valid(who.location))
      room_event = $event:mk_info(who, @this.read_msg):with_dobj(this):with_this(who.location);
      `who.location:announce(room_event) ! E_VERBNF';
    endif
    this:fire_trigger('on_read, ['Actor -> who]);
    return true;
  endverb

  verb seal (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Seal this letter so only the addressee can read it.";
    "Only author or owner can seal";
    if (valid(this.author) && this.author != player && this.owner != player)
      event = $event:mk_error(player, "You didn't write this letter.");
      player:inform_current(event);
      return;
    endif
    if (this.sealed)
      event = $event:mk_info(player, "The letter is already sealed.");
      player:inform_current(event);
      return;
    endif
    this.sealed = true;
    event = $event:mk_info(player, "You seal the letter.");
    player:inform_current(event);
  endverb

  verb "unseal open" (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Unseal this letter, making it readable by anyone.";
    "Only author, addressee, or owner can unseal";
    if (valid(this.author) && this.author != player && this.addressee != player && this.owner != player)
      event = $event:mk_error(player, "This letter isn't yours to open.");
      player:inform_current(event);
      return;
    endif
    if (!this.sealed)
      event = $event:mk_info(player, "The letter is already open.");
      player:inform_current(event);
      return;
    endif
    this.sealed = false;
    event = $event:mk_info(player, "You break the seal on the letter.");
    player:inform_current(event);
  endverb

  verb action_write (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor writes on this letter. Always silent for privacy.";
    set_task_perms(this.owner);
    {who, context, line} = args;
    !this:can_write(who)['allowed] && return false;
    return this:do_write(who, line, true);
  endverb

  verb do_write (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Write to the letter and set author if not yet set.";
    {who, text, ?silent = false} = args;
    "Set author on first write";
    if (!valid(this.author))
      this.author = who;
    endif
    "Call parent to do the actual write";
    return pass(who, text, silent);
  endverb

  verb address (this any any) owner: ARCH_WIZARD flags: "rxd"
    "Address this letter to someone, sealing it for their eyes only.";
    "Usage: address <letter> to <player>";
    if (!valid(iobj) || !is_player(iobj))
      event = $event:mk_error(player, "Address the letter to whom?");
      player:inform_current(event);
      return;
    endif
    "Only author or owner can address";
    if (valid(this.author) && this.author != player && this.owner != player)
      event = $event:mk_error(player, "You didn't write this letter.");
      player:inform_current(event);
      return;
    endif
    this.addressee = iobj;
    this.sealed = true;
    this.sent_at = time();
    "Set author if not yet set";
    if (!valid(this.author))
      this.author = player;
    endif
    event = $event:mk_info(player, "You address the letter to ", iobj.name, " and seal it.");
    player:inform_current(event);
  endverb

  verb look_self (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Show the letter with its metadata.";
    set_task_perms(caller_perms());
    "Build description parts";
    parts = {};
    "Sealed status";
    if (this.sealed)
      parts = {@parts, "It is sealed."};
    else
      parts = {@parts, "It is open."};
    endif
    "Author";
    if (valid(this.author))
      parts = {@parts, "From: " + this.author.name};
    endif
    "Addressee";
    if (valid(this.addressee))
      parts = {@parts, "To: " + this.addressee.name};
    endif
    "Get parent description";
    description = this.description;
    if (length(this.text) > 0)
      description = description + " There appears to be some writing on it.";
    endif
    "Add metadata";
    if (length(parts) > 0)
      meta = parts:join(" ");
      description = description + "\n" + meta;
    endif
    return <$look, .what = this, .title = this:name(), .description = description>;
  endverb

  verb reply (none any this) owner: ARCH_WIZARD flags: "rxd"
    "Create a new letter addressed to this letter's author.";
    "Usage: reply to <letter>";
    if (!valid(this.author))
      event = $event:mk_error(player, "This letter has no author to reply to.");
      player:inform_current(event);
      return;
    endif
    "Create new letter";
    new_letter = create($letter, player);
    new_letter.name = "letter";
    new_letter.addressee = this.author;
    new_letter.author = player;
    "Move to player";
    move(new_letter, player);
    event = $event:mk_info(player, "You prepare a reply to ", this.author.name, ". Write on it to compose your response.");
    player:inform_current(event);
  endverb

  verb edit (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Open text editor to edit this letter.";
    check = this:can_write(player);
    if (!check['allowed])
      player:inform_current($event:mk_error(player, check['reason]));
      return;
    endif
    conn = connection();
    session_id = player:start_edit_session(this, "receive_edit", {conn});
    editor_title = "Edit: " + this.name;
    current_body = this.text:join("\n");
    present(player, session_id, "text/djot", "text-editor", current_body, {
      {"object", this:to_curie_str()},
      {"verb", "receive_edit"},
      {"title", editor_title},
      {"text_mode", "string"},
      {"session_id", session_id}
    });
  endverb

  verb receive_edit (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback for text-editor when editing this letter.";
    {session_id, content} = args;
    if (content == 'close)
      player:end_edit_session(session_id);
      return;
    endif
    session = player:get_edit_session(session_id);
    conn = session['args][1];
    this.text = content:split("\n");
    if (!valid(this.author))
      this.author = player;
    endif
    player:inform_connection(conn, $event:mk_info(player, "Letter saved."));
  endverb
endobject