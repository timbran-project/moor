object MSG_BAG
  name: "Message Bag"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property entries (owner: ARCH_WIZARD, flags: "rc") = {};

  override description = "Container for lists of message templates. Supports {sub} templates and random selection.";
  override import_export_hierarchy = {"events"};
  override import_export_id = "msg_bag";

  verb add (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Add a message template to the bag.";
    set_task_perms(caller_perms());
    {text} = args;
    this.entries = {@this.entries, text};
    return length(this.entries);
  endverb

  verb remove (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove a message by 1-based index.";
    set_task_perms(caller_perms());
    {idx} = args;
    typeof(idx) == INT || raise(E_TYPE);
    idx < 1 || idx > length(this.entries) && raise(E_RANGE);
    this.entries = {@(this.entries)[1..idx - 1], @(this.entries)[idx + 1..$]};
    return length(this.entries);
  endverb

  verb list (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the entries as stored.";
    set_task_perms(caller_perms());
    return this.entries;
  endverb

  verb pick (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Pick a random entry (or return E_RANGE if empty).";
    set_task_perms(caller_perms());
    if (!length(this.entries))
      return E_RANGE;
    endif
    return this.entries[random(length(this.entries))];
  endverb

  verb set_entry (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Replace entry at index with new text.";
    set_task_perms(caller_perms());
    {idx, text} = args;
    typeof(idx) == INT || raise(E_TYPE);
    idx < 1 || idx > length(this.entries) && raise(E_RANGE);
    this.entries[idx] = text;
    return text;
  endverb

  verb entries (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the entries as-is for display.";
    set_task_perms(caller_perms());
    return this.entries;
  endverb
endobject