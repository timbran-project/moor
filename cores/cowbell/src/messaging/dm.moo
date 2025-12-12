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
    loc_str = valid(loc) ? " (in " + loc.name + ")" | "";
    age = time() - this.sent;
    age_str = age < 60 ? "just now" | age:format_time_seconds() + " ago";
    return sender_name + loc_str + " [" + age_str + "]: " + this.text;
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
endobject
