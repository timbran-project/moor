object DRINK
  name: "Generic Drink"
  parent: CONSUMABLE
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  property consume_amounts (owner: ARCH_WIZARD, flags: "rc") = ["drink" -> 2, "gulp" -> 3, "quaff" -> 5, "sip" -> 1];
  property contents_name (owner: ARCH_WIZARD, flags: "rc") = "liquid";
  property drink_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "drink", .type = 'self_alt, .for_others = "drinks">,
    " from ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property empty_name (owner: ARCH_WIZARD, flags: "rc") = "";
  property fill_time (owner: ARCH_WIZARD, flags: "rc") = 0;
  property gulp_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "gulp", .type = 'self_alt, .for_others = "gulps">,
    " from ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property quaff_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "quaff", .type = 'self_alt, .for_others = "quaffs">,
    " deeply from ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property refill_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "refill", .type = 'self_alt, .for_others = "refills">,
    " ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property refillable (owner: ARCH_WIZARD, flags: "rc") = true;
  property sip_msg (owner: ARCH_WIZARD, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "take", .type = 'self_alt, .for_others = "takes">,
    " a small sip from ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  property temp_descriptions (owner: ARCH_WIZARD, flags: "rc") = [
    "cold" -> "cold",
    "hot" -> "steaming",
    "icy" -> "ice-cold",
    "room" -> "",
    "warm" -> "warm"
  ];
  property temperature (owner: ARCH_WIZARD, flags: "rc") = "room";

  override consume_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "drink", .type = 'self_alt, .for_others = "drinks">,
    " from ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  override description = "Prototype for drinkable beverages in vessels. Supports sip, drink, gulp, quaff and refill.";
  override finish_msg = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .capitalize = false, .for_self = "drain", .type = 'self_alt, .for_others = "drains">,
    " the last of ",
    <SUB, .capitalize = false, .type = 'article_the, .binding_name = 'd, .capitalize_binding = false>,
    "."
  };
  override import_export_hierarchy = {"items"};
  override import_export_id = "drink";
  override max_portions = 10;
  override object_documentation = {
    "# Drink",
    "",
    "## Overview",
    "",
    "Beverage vessels that players can drink from. Inherits from $consumable. The vessel persists when empty (unlike food) and can be refilled from sources. Supports multiple drinking verbs with different portion sizes.",
    "",
    "## Commands",
    "",
    "- `drink <beverage>` - take a normal drink",
    "- `sip <beverage>` - take a small sip",
    "- `gulp <beverage>` / `quaff <beverage>` - drink quickly",
    "- `refill <vessel> from <source>` - refill from a tap, fountain, etc.",
    "",
    "## Properties",
    "",
    "Inherited from $consumable:",
    "- `portions`: Remaining portions (default: 3)",
    "- `max_portions`: Vessel capacity (default: 3)",
    "- `consume_rule`: Access control rule",
    "- `on_finish`: `\"keep\"` (default) - vessel remains when empty",
    "",
    "Drink-specific:",
    "- `consume_amounts`: Map of verb to portion size (default: drink=1, sip=1, gulp=2, quaff=2)",
    "- `refill_rule`: Rule for what sources can refill this (0 = any)",
    "- `liquid_name`: Name of the liquid for messages (default: \"liquid\")",
    "",
    "## Messages",
    "",
    "Each drinking verb uses its own message property. Customize with `@set-message`:",
    "",
    "- `drink_msg`: Used by `drink` command",
    "- `sip_msg`: Used by `sip` command",
    "- `gulp_msg`: Used by `gulp`/`quaff` commands",
    "- `empty_msg`: When trying to drink from empty vessel",
    "- `finish_msg`: When draining the last drops",
    "- `refill_msg`: When refilling the vessel",
    "- `refill_denied_msg`: When refill source is invalid",
    "- `consume_msg`: Fallback if verb-specific message not found",
    "",
    "**Note:** Use `{nc}` for actor, `{the d}` for the drink, and `{verb|verbs}` for proper grammar.",
    "",
    "### Examples",
    "",
    "```",
    "@set-message mug.sip_msg {nc} {sip|sips} {the d} slowly, savoring the warmth.",
    "@set-message mug.gulp_msg {nc} {gulp|gulps} down {the d} greedily.",
    "@set-message mug.empty_msg {The d} is empty. Perhaps find a refill?",
    "```",
    "",
    "## Rules",
    "",
    "Control drinking and refilling:",
    "",
    "```",
    "@set-rule chalice.consume_rule This owner_is(Accessor)?",
    "@set-rule grail.refill_rule Source is(\"fountain\")?",
    "```",
    "",
    "## Reactions",
    "",
    "Drinks fire these triggers:",
    "",
    "- `'on_consume`: Each sip/drink/gulp, bindings: `['Actor, 'Amount]`",
    "- `'on_empty`: When vessel is drained, bindings: `['Actor]`",
    "- `'on_refill`: When refilled, bindings: `['Actor, 'Source, 'Amount]`",
    "",
    "### Adding Reactions",
    "",
    "For reactions that announce messages:",
    "",
    "1. Create a message property:",
    "```",
    "@property ale.tipsy_msg {} rc",
    "```",
    "",
    "2. Set the message template:",
    "```",
    "@set-message ale.tipsy_msg {nc} {look|looks} a bit unsteady.",
    "```",
    "",
    "3. Add the reaction referencing it by symbol:",
    "```",
    "@add-reaction ale.tipsy_reaction {'when, 'portions, 'le, 1} 0 {{'announce, 'tipsy_msg}}",
    "```",
    "",
    "## Refill Sources",
    "",
    "Any object can be a refill source. The drink's `refill_rule` controls what sources are valid.",
    "",
    "## Creating Drinks",
    "",
    "```moo",
    "mug = $drink:create();",
    "mug:set_name_aliases(\"steaming mug of coffee\", {\"mug\", \"coffee\"});",
    "mug.description = \"Dark roast, still hot.\";",
    "mug.portions = 3;",
    "mug.max_portions = 3;",
    "mug.liquid_name = \"coffee\";",
    "```"
  };
  override on_finish = "keep";
  override portions = 10;

  verb "drink sip gulp quaff" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Handle drinking - command verb for drink/sip/gulp/quaff.";
    "Check if player has access to the drink";
    if (this.location != player && this.location != player.location)
      event = $event:mk_error(player, "You don't have ", $sub:d(), "."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if can consume";
    check = this:can_consume(player);
    if (!check['allowed])
      event = $event:mk_error(player, @check['reason]):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Get amount based on verb used";
    amount = this.consume_amounts[verb] || 1;
    is_finishing = amount >= this.portions;
    if (is_finishing)
      amount = this.portions;
    endif
    "Get verb-specific message";
    msg_prop = verb + "_msg";
    msg = `this.(msg_prop) ! E_PROPNF => this.consume_msg';
    "Cache finish_msg before consumption";
    finish_msg = this.finish_msg;
    location = player.location;
    "Announce the drinking";
    if (valid(location))
      event = $event:mk_social(player, @msg):with_dobj(this):with_audience('narrative);
      location:announce(event);
    endif
    "Announce finish BEFORE consumption if finishing";
    if (is_finishing && valid(location))
      finish_event = $event:mk_social(player, @finish_msg):with_dobj(this):with_audience('narrative);
      location:announce(finish_event);
    endif
    "Do the consumption silently";
    this:do_consume(player, amount, true);
    "Tell player remaining amount if not finished";
    if (!is_finishing)
      player:inform_current($event:mk_info(player, "(" + tostr(this.portions) + " remaining)"));
    endif
  endverb

  verb refill (this none none) owner: ARCH_WIZARD flags: "rd"
    "Handle refilling the drink vessel.";
    "Check if player has the drink";
    if (this.location != player)
      event = $event:mk_error(player, "You need to be holding ", $sub:d(), " to refill it."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if refillable";
    if (!this.refillable)
      event = $event:mk_error(player, $sub:dc(), " can't be refilled."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if already full";
    if (this.portions >= this.max_portions)
      event = $event:mk_error(player, $sub:dc(), " is already full."):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Refill to max";
    this.portions = this.max_portions;
    this.fill_time = time();
    "Announce";
    if (valid(player.location))
      event = $event:mk_social(player, @this.refill_msg):with_dobj(this):with_audience('narrative);
      player.location:announce(event);
    endif
    "Fire trigger";
    this:fire_trigger('on_refill, ['Actor -> player]);
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for drink items.";
    {for_player, ?topic = ""} = args;
    my_topics = {$help:mk("drink", "Drink a beverage", "Use 'drink <beverage>' to drink from a vessel you're holding. Takes a normal swig.", {}, 'commands, {"sip", "gulp"}), $help:mk("sip", "Sip a drink", "Use 'sip <beverage>' to take a small, delicate sip from a drink.", {}, 'commands, {"drink", "gulp"}), $help:mk("gulp", "Gulp down a drink", "Use 'gulp <beverage>' to gulp down a large portion of a drink quickly.", {"quaff"}, 'commands, {"drink", "sip"}), $help:mk("refill", "Refill a vessel", "Use 'refill <vessel> from <source>' to refill an empty or partially empty drink vessel from a source like a fountain, tap, or dispenser.", {}, 'commands, {"drink"})};
    topic == "" && return my_topics;
    for t in (my_topics)
      t:matches(topic) && return t;
    endfor
    return 0;
  endverb
endobject