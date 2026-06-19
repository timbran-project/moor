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

  method add owner: ARCH_WIZARD
    "Add a message template. Returns new flyweight or entry count for objects.";
    set_task_perms(caller_perms());
    {text} = args;
    if (typeof(this) == TYPE_FLYWEIGHT)
      return toflyweight($msg_bag, flyslots(this), {@flycontents(this), text});
    endif
    this.entries = {@this.entries, text};
    return length(this.entries);
  endmethod

  method remove owner: ARCH_WIZARD
    "Remove a message by 1-based index. Returns new flyweight or entry count for objects.";
    set_task_perms(caller_perms());
    {idx} = args;
    typeof(idx) == TYPE_INT || raise(E_TYPE);
    entries = typeof(this) == TYPE_FLYWEIGHT ? flycontents(this) | this.entries;
    idx < 1 || idx > length(entries) && raise(E_RANGE);
    new_entries = listdelete(entries, idx);
    if (typeof(this) == TYPE_FLYWEIGHT)
      return toflyweight($msg_bag, flyslots(this), new_entries);
    endif
    this.entries = new_entries;
    return length(this.entries);
  endmethod

  method list owner: ARCH_WIZARD
    "Return the entries.";
    set_task_perms(caller_perms());
    return typeof(this) == TYPE_FLYWEIGHT ? flycontents(this) | this.entries;
  endmethod

  method pick owner: ARCH_WIZARD
    "Pick a random entry (or return E_RANGE if empty).";
    set_task_perms(caller_perms());
    entries = typeof(this) == TYPE_FLYWEIGHT ? flycontents(this) | this.entries;
    !length(entries) && return E_RANGE;
    return entries[random(length(entries))];
  endmethod

  method set_entry owner: ARCH_WIZARD
    "Replace entry at index. Returns new flyweight or the text for objects.";
    set_task_perms(caller_perms());
    {idx, text} = args;
    typeof(idx) == TYPE_INT || raise(E_TYPE);
    entries = typeof(this) == TYPE_FLYWEIGHT ? flycontents(this) | this.entries;
    idx < 1 || idx > length(entries) && raise(E_RANGE);
    if (typeof(this) == TYPE_FLYWEIGHT)
      new_entries = listset(entries, text, idx);
      return toflyweight($msg_bag, flyslots(this), new_entries);
    endif
    this.entries[idx] = text;
    return text;
  endmethod

  method entries owner: ARCH_WIZARD
    "Return the entries.";
    set_task_perms(caller_perms());
    return typeof(this) == TYPE_FLYWEIGHT ? flycontents(this) | this.entries;
  endmethod

  verb mk (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Create a flyweight message bag from a list of compiled templates.";
    "Usage: $msg_bag:mk(template1, template2, ...) or $msg_bag:mk(@list_of_templates)";
    return toflyweight($msg_bag, [], args);
  endverb

  verb is_msg_bag (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Check if a value is a message bag (object or flyweight).";
    {value} = args;
    return typeof(value) == TYPE_OBJ && isa(value, $msg_bag) || (typeof(value) == TYPE_FLYWEIGHT && value.delegate == $msg_bag);
  endverb
endobject
