object DM
  name: "Direct Message"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for direct messages. DMs are lightweight, ephemeral player-to-player messages that follow the same protocol as letters (from, to, sent, text) but are stored as flyweights rather than full objects.";
  override import_export_hierarchy = {"messaging"};
  override import_export_id = "dm";

  verb mk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a DM flyweight.";
    "Args: sender, recipient, text";
    {sender, recipient, msg_text} = args;
    loc = valid(sender) ? sender.location | #-1;
    return toflyweight(this, ['from -> sender, 'to -> recipient, 'sent -> time(), 'text -> msg_text, 'location -> loc]);
  endverb

  verb from (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the sender of this DM.";
    return this.from;
  endverb

  verb to (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the recipient of this DM.";
    return this.to;
  endverb

  verb sent (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the timestamp when this DM was sent.";
    return this.sent;
  endverb

  verb text (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the text content of this DM.";
    return this.text;
  endverb

  verb location (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the location where the sender was when they sent this DM.";
    return this.location;
  endverb

  verb subject (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return subject (empty for DMs, for protocol compatibility with letters).";
    return "";
  endverb

  verb display (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Render this DM for display to the recipient.";
    {?for_player = this.to} = args;
    sender = this.from;
    sender_name = valid(sender) ? sender.name | "(unknown)";
    loc = this.location;
    age = time() - this.sent;
    age_str = age < 60 ? "just now" | age:format_time_seconds() + " ago";
    "Build colorized version";
    colored_sender = $ansi:colorize(sender_name, 'bright_cyan);
    colored_loc = valid(loc) ? " (in " + $ansi:colorize(loc.name, 'dim) + ")" | "";
    colored_time = $ansi:colorize("[" + age_str + "]", 'yellow);
    return colored_sender + colored_loc + " " + colored_time + ": " + this.text;
  endverb

  verb display_short (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Short display for listings.";
    sender = this.from;
    sender_name = valid(sender) ? sender.name | "???";
    age = time() - this.sent;
    age_str = age < 60 ? "now" | age:format_time_seconds();
    text = this.text;
    if (length(text) > 40)
      text = text[1..37] + "...";
    endif
    return sender_name + " (" + age_str + "): " + text;
  endverb

  verb display_tts (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return plain text version for screen readers (no ANSI codes).";
    {?for_player = this.to} = args;
    sender = this.from;
    sender_name = valid(sender) ? sender.name | "unknown";
    loc = this.location;
    loc_str = valid(loc) ? " in " + loc.name | "";
    age = time() - this.sent;
    age_str = age < 60 ? "just now" | age:format_time_seconds() + " ago";
    return "Direct message from " + sender_name + loc_str + ", " + age_str + ": " + this.text;
  endverb

  verb display_event (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return a fully-formed event for displaying this DM to the recipient.";
    "Includes colorized display, TTS, metadata, and grouping.";
    {recipient} = args;
    display_str = this:display(recipient);
    tts_str = this:display_tts(recipient);
    group = tosym("dm_" + $url_utils:to_curie_str(this.from));
    event = $event:mk_dm(recipient, display_str);
    event = event:with_presentation_hint('inset);
    event = event:with_group(group);
    event = event:with_tts(tts_str);
    event = event:with_metadata('dm_from, this.from);
    event = event:with_metadata('dm_location, this.location);
    event = event:with_metadata('dm_content, this.text);
    event = event:with_metadata('dm_timestamp, this.sent);
    return event;
  endverb

  verb sender_echo_event (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return event confirming DM was sent, shown to the sender.";
    "Format: You (in Location) \u2192 Target: message";
    sender = this.from;
    recipient = this.to;
    loc = this.location;
    recipient_name = valid(recipient) ? recipient.name | "???";
    "Build colorized display";
    loc_str = valid(loc) ? " (in " + $ansi:colorize(loc.name, 'dim) + ")" | "";
    arrow = $ansi:colorize(" \u2192 ", 'bright_black);
    colored_you = $ansi:colorize("You", 'bright_cyan);
    colored_target = $ansi:colorize(recipient_name, 'bright_magenta);
    display_str = colored_you + loc_str + arrow + colored_target + ": " + this.text;
    "Build TTS version";
    tts_loc = valid(loc) ? " in " + loc.name | "";
    tts_str = "Message sent to " + recipient_name + tts_loc + ": " + this.text;
    "Build event";
    group = tosym("dm_" + $url_utils:to_curie_str(recipient));
    event = $event:mk_dm(sender, display_str);
    event = event:with_audience('utility);
    event = event:with_presentation_hint('inset);
    event = event:with_group(group);
    event = event:with_tts(tts_str);
    event = event:with_metadata('dm_to, recipient);
    event = event:with_metadata('dm_location, loc);
    event = event:with_metadata('dm_content, this.text);
    event = event:with_metadata('dm_timestamp, this.sent);
    return event;
  endverb
endobject