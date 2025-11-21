object THING
  name: "Generic Thing"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  property integrated_description (owner: HACKER, flags: "rc") = "";
  property pronouns (owner: HACKER, flags: "rc") = <#28, .verb_be = "is", .verb_have = "has", .display = "it/its", .ps = "it", .po = "it", .pp = "its", .pq = "its", .pr = "itself", .is_plural = false>;
  property is_plural_noun (owner: HACKER, flags: "rc") = false;
  property is_countable_noun (owner: HACKER, flags: "rc") = true;
  property is_proper_noun_name (owner: HACKER, flags: "rc") = false;

  override description = "Generic thing prototype that is the basis for most items in the world.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "thing";

  verb pronouns (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the pronoun set for this object (object or flyweight).";
    set_task_perms(caller_perms());
    return this.pronouns;
  endverb

  verb is_plural (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns whether this object should be treated as a plural noun.";
    "Things are singular by default but can be set to plural.";
    return this.is_plural_noun;
  endverb

  verb is_countable (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns whether this object is countable in English grammar.";
    "Things are countable by default (can use 'a' or 'the').";
    return this.is_countable_noun;
  endverb

  verb is_proper_noun (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns whether this object should be treated as a proper noun.";
    "Things are common nouns by default, not proper nouns.";
    return this.is_proper_noun_name;
  endverb

  verb integrate_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return integrated description if set, or false. Integrated descriptions become part of the room description.";
    set_task_perms(caller_perms());
    desc = this.integrated_description;
    if (desc && desc != "")
      return desc;
    endif
    return false;
  endverb

  verb "pronoun_*" (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get pronoun from either preset object or custom flyweight.";
    set_task_perms(caller_perms());
    ptype = tosym(verb[9..length(verb)]);
    p = this:pronouns();
    ptype == 'subject && return p.ps;
    ptype == 'object && return p.po;
    ptype == 'possessive && args[1] == 'adj && return p.pp;
    ptype == 'possessive && args[2] == 'noun && return p.pq;
    ptype == 'reflexive && return p.pr;
    raise(E_INVARG);
  endverb

  verb get (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Get/take an object";
    set_task_perms(caller_perms());
    if (this.location == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    accept_to = player:acceptable(this);
    if (!accept_to)
      event = $event:mk_no_accept(player, $sub:nc(), " can't put ", $sub:d(), " in ", $sub:ic(), "."):with_dobj(this):with_iobj(player);
      player:inform_current(event);
      return;
    endif
    old_location = this.location;
    try
      this:moveto(player);
    except e (E_PERM)
      "Handle permission errors with friendly message";
      msg = length(e) > 2 ? e[2] | "You don't have permission to take that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
      return;
    endtry
    if (isa(old_location, $room))
      event = $event:mk_moved(player, $sub:nc(), " picked up ", $sub:d(), "."):with_dobj(this):with_iobj(player);
      old_location:announce(event);
    endif
  endverb

  verb drop (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Drop an object from inventory";
    set_task_perms(caller_perms());
    if (this.location != player)
      event = $event:mk_error(player, "You don't have ", $sub:d(), " to drop."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    new_location = player.location;
    if (!new_location:acceptable(this))
      event = $event:mk_error(player, "You can't drop ", $sub:d(), " here."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    try
      this:moveto(new_location);
    except e (E_PERM)
      "Handle permission errors with friendly message";
      msg = length(e) > 2 ? e[2] | "You don't have permission to drop that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
      return;
    endtry
    event = $event:mk_moved(player, $sub:nc(), " dropped ", $sub:d(), "."):with_dobj(this):with_iobj(player);
    new_location:announce(event);
  endverb

  verb acceptable (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return false;
  endverb
endobject