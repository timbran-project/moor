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
  property drop_msg (owner: HACKER, flags: "rc") = {<SUB, .capitalize = true, .type = 'actor>, " dropped ", <SUB, .capitalize = false, .type = 'dobj>, "."};
  property get_msg (owner: HACKER, flags: "rc") = {<SUB, .capitalize = true, .type = 'actor>, " picked up ", <SUB, .capitalize = false, .type = 'dobj>, "."};

  property get_rule (owner: HACKER, flags: "rc") = 0;
  property get_denied_msg (owner: HACKER, flags: "rc") = {"You can't pick that up."};
  property drop_rule (owner: HACKER, flags: "rc") = 0;
  property drop_denied_msg (owner: HACKER, flags: "rc") = {"You can't drop that."};

  override description = "Generic thing prototype that is the basis for most items in the world.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "thing";

  override object_documentation = {
    "# Generic Things",
    "",
    "## Overview",
    "",
    "Things are the base class for most items in the world. They can be picked up, dropped, and moved around. Things form the foundation for more specialized items like containers and wearables.",
    "",
    "## Properties",
    "",
    "### pronouns",
    "",
    "Grammatical properties for this object (pronouns, plurality, noun type).",
    "",
    "- Default: it/its pronouns, singular, countable",
    "- Can be customized per item or use preset pronoun objects",
    "",
    "### is_plural_noun",
    "",
    "Whether this object should be treated as grammatically plural.",
    "",
    "- Default: `false`",
    "",
    "### is_countable_noun",
    "",
    "Whether this object can use articles like 'a' or 'the'.",
    "",
    "- Default: `true`",
    "",
    "### is_proper_noun_name",
    "",
    "Whether this object is a proper noun (like a name) that doesn't need articles.",
    "",
    "- Default: `false`",
    "",
    "### integrated_description",
    "",
    "Text that appears in the room description when this thing is present.",
    "",
    "- Default: empty string (not integrated)",
    "- Can be set to add flavor text about the item to the room description",
    "",
    "### get_msg and drop_msg",
    "",
    "Customizable messages shown when the item is picked up or dropped.",
    "",
    "Customize using the `@set-message` command:",
    "",
    "```",
    "@set-message sword.get_msg {nc} {grasp|grasps} {d} firmly.",
    "@set-message sword.drop_msg {nc} {release|releases} {d} carefully.",
    "```",
    "",
    "Template tokens:",
    "- `{nc}` - Actor name (capitalized)",
    "- `{grasp|grasps}` - Self-alternation verb",
    "- `{d}` - Direct object (the item)",
    "",
    "## Commands",
    "",
    "### get / take",
    "",
    "```",
    "get <item>",
    "take <item>",
    "```",
    "",
    "Picks up an item and adds it to inventory.",
    "",
    "### drop",
    "",
    "```",
    "drop <item>",
    "```",
    "",
    "Removes an item from inventory and places it in the current location.",
    "",
    "## Verbs",
    "",
    "### pronouns()",
    "",
    "Returns the pronoun set for this object.",
    "",
    "### is_plural()",
    "",
    "Returns whether this object is grammatically plural.",
    "",
    "### is_countable()",
    "",
    "Returns whether this object is countable (can use articles).",
    "",
    "### is_proper_noun()",
    "",
    "Returns whether this object is a proper noun.",
    "",
    "### integrate_description()",
    "",
    "Returns the integrated description if set, or `false` otherwise.",
    "",
    "## Example: Creating a Sword",
    "",
    "```moo",
    "sword = create($thing);",
    "sword:set_name(\"a gleaming sword\");",
    "sword.description = \"A well-crafted sword with a sharp blade.\";",
    "sword.integrated_description = \"a sword lies here, glinting in the light\";",
    "```"
  };

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

  verb can_get (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if actor can pick up this object. Returns true/false.";
    {?who = player} = args;
    "No rule means always allowed";
    this.get_rule == 0 && return true;
    "Evaluate rule with context";
    context = ['Actor -> who, 'This -> this];
    result = $rule_engine:evaluate(this.get_rule, context);
    return result['success];
  endverb

  verb can_drop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if actor can drop this object. Returns true/false.";
    {?who = player} = args;
    "No rule means always allowed";
    this.drop_rule == 0 && return true;
    "Evaluate rule with context";
    context = ['Actor -> who, 'This -> this];
    result = $rule_engine:evaluate(this.drop_rule, context);
    return result['success];
  endverb

  verb do_get (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Move item to actor's inventory. Returns true. Optional silent flag.";
    {who, ?silent = false} = args;
    old_location = this.location;
    this:moveto(who);
    if (!silent && isa(old_location, $room))
      event = $event:mk_moved(who, @this.get_msg):with_dobj(this):with_iobj(who);
      old_location:announce(event);
    endif
    return true;
  endverb

  verb do_drop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Drop item from actor to their location. Returns true. Optional silent flag.";
    {who, ?silent = false} = args;
    new_location = who.location;
    this:moveto(new_location);
    if (!silent)
      event = $event:mk_moved(who, @this.drop_msg):with_dobj(this):with_iobj(who);
      new_location:announce(event);
    endif
    return true;
  endverb

  verb get (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Get/take an object - command handler";
    set_task_perms(caller_perms());
    if (this.location == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!this:can_get(player))
      event = $event:mk_error(player, @this.get_denied_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!player:acceptable(this))
      event = $event:mk_no_accept(player, $sub:nc(), " can't put ", $sub:d(), " in ", $sub:ic(), "."):with_dobj(this):with_iobj(player);
      player:inform_current(event);
      return;
    endif
    try
      this:do_get(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to take that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
    endtry
  endverb

  verb drop (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Drop an object from inventory - command handler";
    set_task_perms(caller_perms());
    if (this.location != player)
      event = $event:mk_error(player, "You don't have ", $sub:d(), " to drop."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!this:can_drop(player))
      event = $event:mk_error(player, @this.drop_denied_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    if (!player.location:acceptable(this))
      event = $event:mk_error(player, "You can't drop ", $sub:d(), " here."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    try
      this:do_drop(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to drop that.";
      event = $event:mk_error(player, msg):with_dobj(this);
      player:inform_current(event);
    endtry
  endverb

  verb acceptable (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return false;
  endverb

  verb "action_get action_take" (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler for reactions: make actor pick up this item.";
    {who, context} = args;
    this.location == who && return false;
    !this:can_get(who) && return false;
    !who:acceptable(this) && return false;
    return this:do_get(who);
  endverb

  verb action_drop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler for reactions: make actor drop this item.";
    {who, context} = args;
    this.location != who && return false;
    !this:can_drop(who) && return false;
    !who.location:acceptable(this) && return false;
    return this:do_drop(who);
  endverb

  verb action_put (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler for reactions: put this item into a container.";
    {who, context, dest} = args;
    this.location != who && return false;
    "Check container's put rule if it has one";
    if (`dest:can_put_into(who, this) ! E_VERBNF => ['allowed -> true]'['allowed] == false)
      return false;
    endif
    !dest:acceptable(this) && return false;
    this:moveto(dest);
    return true;
  endverb

endobject