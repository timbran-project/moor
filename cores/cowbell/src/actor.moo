object ACTOR
  name: "Generic Actor"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  property pronouns (owner: ARCH_WIZARD, flags: "rc") = <SCHEDULED_TASK, .is_plural = true, .verb_be = "are", .verb_have = "have", .display = "they/them", .ps = "they", .po = "them", .pp = "their", .pq = "theirs", .pr = "themselves">;

  override description = "Generic actor prototype providing core behavior for NPCs and players including item transfer, communication, and movement.";
  override import_export_id = "actor";

  verb is_actor (this none this) owner: HACKER flags: "rxd"
    "Actors can perform actions in the world.";
    return true;
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Default: actors accept items.";
    return true;
  endverb

  verb put (any in this) owner: HACKER flags: "rd"
    "Reject putting things in an actor";
    event = $event:mk_error(player, $sub:tc(), " ", $sub:verb_be(), " a person, not a container."):with_this(this);
    player:inform_current(event);
  endverb

  verb "give hand" (any at this) owner: HACKER flags: "rd"
    "Give an object to this actor";
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Give what?");
      player:inform_current(event);
      return;
    endif
    "Match the object being given from player's perspective";
    try
      dobj = $match:match_object(dobjstr, player);
    except e (ANY)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endtry
    if (!valid(dobj) || typeof(dobj) != TYPE_OBJ)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endif
    if (dobj.location != player)
      event = $event:mk_error(player, "You don't have ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    if (this == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Check if this recipient can accept the item";
    if (!this:acceptable(dobj))
      event = $event:mk_error(player, $sub:t(), " can't accept ", $sub:d(), "."):with_dobj(dobj):with_this(this);
      player:inform_current(event);
      return;
    endif
    "Move the item";
    try
      dobj:moveto(this);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to give that away.";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
      return;
    endtry
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("give", "gives"), " ", $sub:d(), " to ", $sub:i(), "."):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb "get take steal grab" (any from this) owner: HACKER flags: "rd"
    "Take an object from this actor";
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Take what?");
      player:inform_current(event);
      return;
    endif
    "Match the object from dobjstr - search in this container's contents";
    try
      dobj = $match:match_object(dobjstr, this);
    except e (ANY)
      event = $event:mk_error(player, $sub:t(), " doesn't have that."):with_this(this);
      player:inform_current(event);
      return;
    endtry
    if (!valid(dobj) || typeof(dobj) != TYPE_OBJ)
      event = $event:mk_error(player, $sub:t(), " doesn't have that."):with_this(this);
      player:inform_current(event);
      return;
    endif
    if (dobj.location != this)
      event = $event:mk_error(player, $sub:d(), " isn't with ", $sub:t(), "."):with_dobj(dobj):with_this(this);
      player:inform_current(event);
      return;
    endif
    if (this == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Check if player can accept the item";
    if (!player:acceptable(dobj))
      event = $event:mk_error(player, "You can't carry ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Try to move it";
    try
      dobj:moveto(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You can't take that from " + this:name() + ".";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
      return;
    endtry
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("take", "takes"), " ", $sub:d(), " from ", $sub:i(), "."):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb mk_emote_event (this none this) owner: HACKER flags: "rxd"
    "Emotes always show the actor's name, never 'You'";
    return $event:mk_emote(this, this:name(), " ", args[1]):with_this(this.location);
  endverb

  verb mk_say_event (this none this) owner: HACKER flags: "rxd"
    event = $event:mk_say(this, $sub:nc(), " ", $sub:self_alt("say", "says"), ", \"", args[1], "\""):with_this(this.location);
    event = event:with_metadata('content, args[1]);
    event = event:as_djot():with_presentation_hint('speech_bubble);
    return event;
  endverb

  verb mk_directed_say_event (this none this) owner: HACKER flags: "rxd"
    "Directed say: 'Name [to Target]: message'";
    {target, message} = args;
    return $event:mk_directed_say(this, this:name(), " [to ", $sub:i(), "]: ", message):with_iobj(target):with_this(this.location);
  endverb

  verb mk_think_event (this none this) owner: HACKER flags: "rxd"
    "Thoughts always show the actor's name, never 'You'";
    return $event:mk_think(this, this:name(), " . o O ( ", args[1], " )"):with_this(this.location);
  endverb

  verb mk_connected_event (this none this) owner: HACKER flags: "rxd"
    "Create a connection announcement event.";
    "Args: ?is_new_player = false";
    {?is_new_player = false} = args;
    "Select template based on whether this is a new player";
    if (is_new_player)
      template = `$login.new_player_arrival_template ! E_PROPNF => "{nc} has just arrived."';
    else
      template = `$login.player_wakeup_template ! E_PROPNF => "{nc} {have|has} woken up."';
    endif
    "Compile the template into $sub flyweights";
    content = $sub_utils:compile(template);
    return $event:mk_say(this, @content):with_presentation_hint('inset):with_group('connection, this);
  endverb

  verb mk_disconnected_event (this none this) owner: HACKER flags: "rxd"
    return $event:mk_say(this, $sub:nc(), " ", $sub:self_alt("have", "has"), " goes to sleep."):with_presentation_hint('inset):with_group('connection, this);
  endverb

  verb mk_departure_event (this none this) owner: HACKER flags: "rxd"
    "Create a departure event. Optional departure_phrase overrides default template.";
    {from_room, ?direction = "", ?passage_desc = "", ?to_room = #-1, ?departure_phrase = ""} = args;
    typeof(direction) == TYPE_STR || (direction = "");
    typeof(passage_desc) == TYPE_STR || (passage_desc = "");
    typeof(departure_phrase) == TYPE_STR || (departure_phrase = "");
    parts = {$sub:nc(), " ", $sub:self_alt("head", "heads")};
    if (departure_phrase)
      "Use custom departure phrase if provided";
      parts = {@parts, " ", departure_phrase};
    else
      "Default: construct from direction and passage description";
      if (direction)
        parts = {@parts, " ", direction};
      else
        parts = {@parts, " out"};
      endif
      if (passage_desc)
        passage_desc = $sub:phrase(passage_desc, {'strip_period, 'initial_lowercase});
        parts = {@parts, " through ", passage_desc};
      endif
    endif
    parts = {@parts, "."};
    event = $event:mk_move(this, @parts):as_djot();
    valid(from_room) && (event = event:with_this(from_room));
    valid(to_room) && (event = event:with_iobj(to_room));
    return event;
  endverb

  verb mk_arrival_event (this none this) owner: HACKER flags: "rxd"
    "Create an arrival event. Optional arrival_phrase overrides default template.";
    {to_room, ?direction = "", ?passage_desc = "", ?from_room = #-1, ?arrival_phrase = ""} = args;
    typeof(direction) == TYPE_STR || (direction = "");
    typeof(passage_desc) == TYPE_STR || (passage_desc = "");
    typeof(arrival_phrase) == TYPE_STR || (arrival_phrase = "");
    parts = {$sub:nc(), " ", $sub:self_alt("arrive", "arrives")};
    if (arrival_phrase)
      "Use custom arrival phrase if provided";
      parts = {@parts, " ", arrival_phrase};
    else
      "Default: construct from direction and passage description";
      if (direction)
        "Handle direction grammar - vertical directions need different phrasing";
        if (direction in {"up", "down"})
          parts = {@parts, " from ", direction == "up" ? "below" | "above"};
        elseif (direction in {"in", "out"})
          parts = {@parts, " from ", direction == "in" ? "outside" | "inside"};
        else
          parts = {@parts, " from the ", direction};
        endif
      endif
      if (passage_desc)
        passage_desc = $sub:phrase(passage_desc, {'strip_period, 'initial_lowercase});
        parts = {@parts, ", emerging from ", passage_desc};
      endif
    endif
    parts = {@parts, "."};
    event = $event:mk_move(this, @parts):as_djot();
    valid(to_room) && (event = event:with_this(to_room));
    valid(from_room) && (event = event:with_iobj(from_room));
    return event;
  endverb

  verb pronouns (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return this.pronouns;
  endverb

  verb "pronoun_*" (this none this) owner: ARCH_WIZARD flags: "rxd"
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

  verb fact_is_wizard (this none this) owner: HACKER flags: "rxd"
    "Fact predicate: Is this actor a wizard?";
    {actor} = args;
    return actor.wizard;
  endverb

  verb fact_is_programmer (this none this) owner: HACKER flags: "rxd"
    "Fact predicate: Does this actor have programmer privileges?";
    {actor} = args;
    return actor.programmer;
  endverb

  verb fact_is_builder (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Fact predicate: Does this actor have builder privileges?";
    {?actor = this} = args;
    return `actor.is_builder ! E_PROPNF => false';
  endverb

  verb fact_has_in_inventory (this none this) owner: HACKER flags: "rxd"
    "Fact predicate: Does this actor have thing in their inventory?";
    {actor, thing} = args;
    return thing.location == actor;
  endverb

  verb fact_owns (this none this) owner: HACKER flags: "rxd"
    "Fact predicate: Does this actor own thing?";
    {actor, thing} = args;
    return thing.owner == actor;
  endverb

  verb action_go (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: make this actor go in a direction.";
    set_task_perms(this.owner);
    {who, context, direction} = args;
    who != this && return false;
    !valid(this.location) && return false;
    "Delegate to room's action_go";
    return `this.location:action_go(this, context, direction) ! ANY => false';
  endverb

  verb mk_stagetalk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Stagetalk: directed speech 'Name [to Target]: message'";
    {target, message} = args;
    return $event:mk_stagetalk(this, this:name(), " [to ", $sub:i(), "]: ", message):with_iobj(target):with_this(this.location);
  endverb

  verb inspection (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return structured data for client inspection popover.";
    {?who = player} = args;
    actor_name = `this:name() ! E_VERBNF => this.name';
    this_ref = $url_utils:to_curie_str(this);
    who_ref = $url_utils:to_curie_str(who);
    actions = {};
    actions = {@actions, ["label" -> "Examine", "verb" -> "do_examine", "target" -> who_ref, "args" -> {this_ref}]};
    return ["title" -> actor_name, "description" -> this:description(), "actions" -> actions];
  endverb

  verb pronouns_display (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the display string for the player's pronouns (e.g. 'they/them').";
    {target, perms} = this:check_permissions('pronouns_display);
    set_task_perms(perms);
    return $pronouns:display(target.pronouns);
  endverb
endobject
