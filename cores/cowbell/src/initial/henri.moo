object HENRI
  name: "Henri"
  parent: ACTOR
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property complaints_msg_bag (owner: HACKER, flags: "rc") = HENRI_COMPLAINTS;
  property pet_reactions_grouchy_msg_bag (owner: HACKER, flags: "rc") = HENRI_PET_GROUCHY_MSGS;
  property pet_reactions_sleepy_msg_bag (owner: HACKER, flags: "rc") = HENRI_PET_SLEEPY_MSGS;
  property pet_reactions_default_msg_bag (owner: HACKER, flags: "rc") = HENRI_PET_DEFAULT_MSGS;
  property look_self_msg_bag (owner: HACKER, flags: "rc") = HENRI_LOOK_SELF_MSGS;
  property mood (owner: HACKER, flags: "rc") = "grouchy";
  property pets_received (owner: HACKER, flags: "rc") = 0;
  property scheduled_behaviours (owner: HACKER, flags: "rc") = {};

  override aliases = {"cat", "grouchy cat"};
  override description = "A sleek black cat with piercing green eyes and an air of perpetual annoyance. His fur is immaculately groomed despite the construction dust, and he holds himself with the offended dignity of a creature who knows he deserves better accommodations. He occasionally flicks his tail in irritation, as if to emphasize his displeasure with the current state of affairs.";
  override import_export_id = "henri";

  verb _pick_message (this none this) owner: HACKER flags: "rxd"
    "Pick a message from a bag/string or use a compiled list directly, returning empty string on failure.";
    {source} = args;
    if (valid(source) && isa(source, $msg_bag))
      msg = source:pick();
      return typeof(msg) == ERR ? "" | msg;
    elseif (typeof(source) == LIST)
      "Assume this is a compiled template list; return as-is";
      return source;
    elseif (typeof(source) == STR)
      return source;
    endif
    return "";
  endverb

  verb "pet stroke" (this none none) owner: HACKER flags: "rxd"
    "Handle petting Henri - he's grouchy but might tolerate it occasionally";
    "Announce the action to the room";
    if (valid(this.location))
      this.location:announce($event:mk_emote(player, $sub:nc(), " ", $sub:self_alt("pet", "pets"), " ", $sub:the('dobj), "."):with_dobj(this));
    endif
    "Increment pets counter";
    this.pets_received = this.pets_received + 1;
    "Determine Henri's reaction based on mood, random chance, and interaction history";
    reaction = "";
    "Check if he's becoming slightly more tolerant over time";
    if (this.pets_received > 10 && random(3) == 1)
      "He's been petted a lot - might be slightly more tolerant";
      reaction = this:_pick_message(this.pet_reactions_default_msg_bag);
    elseif (this.mood == "grouchy")
      "Grouchy mood - mostly negative reactions";
      reaction = this:_pick_message(this.pet_reactions_grouchy_msg_bag);
    elseif (this.mood == "sleepy")
      "Sleepy mood - more tolerant but still grumpy";
      reaction = this:_pick_message(this.pet_reactions_sleepy_msg_bag);
    else
      "Default reaction";
      reaction = this:_pick_message(this.pet_reactions_default_msg_bag);
    endif
    "Occasionally mix in a complaint about the construction";
    if (random(3) == 1)
      complaint = this:_pick_message(this.complaints_msg_bag);
      if (complaint && complaint != "")
        "Ensure both reaction and complaint are lists before combining";
        reaction_content = reaction;
        if (typeof(reaction_content) == STR)
          try
            reaction_content = $sub_utils:compile(reaction_content);
          except (ANY)
            reaction_content = {reaction_content};
          endtry
        elseif (typeof(reaction_content) != LIST)
          reaction_content = {reaction_content};
        endif
        complaint_content = complaint;
        if (typeof(complaint_content) == STR)
          try
            complaint_content = $sub_utils:compile(complaint_content);
          except (ANY)
            complaint_content = {complaint_content};
          endtry
        elseif (typeof(complaint_content) != LIST)
          complaint_content = {complaint_content};
        endif
        reaction = $format.block:mk(reaction_content, complaint_content);
      endif
    endif
    "Announce Henri's reaction";
    if (valid(this.location))
      reaction_content = reaction;
      if (typeof(reaction_content) == STR)
        try
          reaction_content = $sub_utils:compile(reaction_content);
        except (ANY)
          reaction_content = {reaction_content};
        endtry
      elseif (typeof(reaction_content) != LIST)
        reaction_content = {reaction_content};
      endif
      event = $event:mk_emote(this, @reaction_content):with_dobj(player):with_audience('narrative);
      this.location:announce(event);
    endif
  endverb

  verb change_mood (none none none) owner: HACKER flags: "rxd"
    "Change Henri's mood state for testing";
    "Available moods";
    moods = {"grouchy", "sleepy", "curious", "playful", "annoyed"};
    "Cycle to next mood";
    current_index = moods:find(this.mood);
    if (current_index == 0)
      new_mood = "grouchy";
    else
      new_index = current_index % length(moods) + 1;
      new_mood = moods[new_index];
    endif
    "Update mood";
    old_mood = this.mood;
    this.mood = new_mood;
    "Provide feedback";
    player:inform_current($event:mk_info(player, "Henri's mood changed from " + old_mood + " to " + new_mood + "."));
    "Announce mood change if in a room";
    if (valid(this.location))
      mood_descriptions = ["grouchy" -> "seems to find a new level of annoyance to express.", "sleepy" -> "looks like he might actually try to nap, despite the construction noise.", "curious" -> "pricks his ears up and seems momentarily interested in his surroundings.", "playful" -> "flicks his tail in a way that suggests he might be considering mischief.", "annoyed" -> "lets out a sigh that conveys profound disappointment with the universe."];
      description = mood_descriptions[new_mood] || "seems to be in a mood.";
      this.location:announce(this:mk_emote_event(description));
    endif
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    look_data = pass(@args);
    base_desc = look_data.description;
    desc_parts = typeof(base_desc) == LIST ? base_desc | {base_desc};
    mood_extra = this:_pick_message(this.look_self_msg_bag);
    if (typeof(mood_extra) != LIST)
      mood_extra = {mood_extra};
    endif
    merged = mood_extra ? {@desc_parts, "\n", @mood_extra} | desc_parts;
    return <look_data.delegate, .what = look_data.what, .title = look_data.title, .description = merged>;
  endverb

  verb "feed give" (this none none) owner: HACKER flags: "rxd"
    "Handle feeding Henri - he's very particular about his food";
    "Announce the action to the room";
    if (valid(this.location))
      this.location:announce($event:mk_emote(player, $sub:nc(), " ", $sub:self_alt("offer", "offers"), " ", $sub:the('dobj), " some food."):with_dobj(this));
    endif
    "Generate Henri's picky response";
    responses = {"sniffs delicately, then turns his head away with a look of profound disappointment. \"Is this... the best you could manage?\"", "takes a tentative bite, then gives you a look that says \"It's adequate. Barely.\"", "eats with grudging acceptance. \"I suppose this will have to do, given the circumstances.\"", "looks at the food, then at you, then back at the food. \"My previous establishment served this with a proper garnish.\"", "consumes the offering with an air of someone doing you a great favor. \"Don't expect me to be grateful.\"", "picks at the food disdainfully. \"The texture is all wrong. And the temperature is completely off.\"", "eats quickly, as if embarrassed to be seen accepting such pedestrian fare. \"This better not become a habit.\""};
    response = responses[random(length(responses))];
    "Announce Henri's reaction";
    if (valid(this.location))
      this.location:announce(this:mk_emote_event(response));
    endif
  endverb

  verb start_behaviours (this none this) owner: HACKER flags: "rxd"
    "Start Henri's periodic autonomous behaviours";
    "Check if behaviours are already running";
    if (length(this.scheduled_behaviours) > 0)
      player:inform_current($event:mk_info(player, "Henri's behaviours are already running."));
      return;
    endif
    "Initialize behaviours map";
    this.scheduled_behaviours = [];
    "Schedule different behaviours at staggered random intervals to avoid bunching:";
    "1. Grooming (every 4-6 minutes, randomized)";
    groom_task = $scheduler:schedule_every({240, 120}, this, "_autonomous_groom");
    this.scheduled_behaviours["grooming"] = groom_task;
    "2. Stretching (every 5-8 minutes, randomized)";
    stretch_task = $scheduler:schedule_every({300, 180}, this, "_autonomous_stretch");
    this.scheduled_behaviours["stretching"] = stretch_task;
    "3. Complaining (every 7-12 minutes, randomized)";
    complain_task = $scheduler:schedule_every({420, 300}, this, "_autonomous_complain");
    this.scheduled_behaviours["complaining"] = complain_task;
    "4. Occasional mood shifts (every 9-15 minutes, randomized)";
    mood_task = $scheduler:schedule_every({540, 360}, this, "_autonomous_mood_shift");
    this.scheduled_behaviours["mood_shifts"] = mood_task;
    "5. Dramatic sighs (every 12-18 minutes, randomized)";
    sigh_task = $scheduler:schedule_every({720, 360}, this, "_autonomous_sigh");
    this.scheduled_behaviours["sighing"] = sigh_task;
    "6. Construction-specific reactions (every 10-16 minutes, randomized)";
    construction_task = $scheduler:schedule_every({600, 360}, this, "_autonomous_construction_reaction");
    this.scheduled_behaviours["construction_reactions"] = construction_task;
    player:inform_current($event:mk_info(player, "Henri's autonomous behaviours started. He will now exhibit natural cat behaviours periodically."));
    "Announce initial behaviour to room";
    if (valid(this.location))
      this.location:announce(this:mk_emote_event("seems to settle into a routine of periodic sulking and grooming."));
    endif
  endverb

  verb stop_behaviours (this none this) owner: HACKER flags: "rxd"
    "Stop Henri's periodic autonomous behaviours";
    "Check if behaviours are running";
    if (length(this.scheduled_behaviours) == 0)
      player:inform_current($event:mk_info(player, "Henri's behaviours are not currently running."));
      return;
    endif
    "Cancel all scheduled tasks";
    for task_id, behaviour_name in (this.scheduled_behaviours)
      $scheduler:cancel(task_id);
    endfor
    "Clear the behaviours map";
    this.scheduled_behaviours = {};
    player:inform_current($event:mk_info(player, "Henri's autonomous behaviours stopped."));
    "Announce to room";
    if (valid(this.location))
      this.location:announce(this:mk_emote_event("seems to settle into a more permanent state of annoyance."));
    endif
  endverb

  verb _autonomous_groom (this none this) owner: HACKER flags: "rxd"
    "Autonomous grooming behaviour - called periodically by scheduler";
    "Only announce if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Generate grooming behaviour with grouchy commentary";
    grooming_behaviours = {"meticulously cleans one paw, then gives it a look of profound disappointment. 'The dust in this place is simply unacceptable.'", "attends to his fur with fastidious care, muttering about 'substandard grooming conditions.'", "washes his face with an expression that says 'I shouldn't have to work this hard to maintain basic standards.'", "grooms his sleek black coat, occasionally pausing to flick construction dust away with visible irritation.", "cleans behind his ears with the weary air of someone performing an unpleasant but necessary chore.", "smooths his fur, then sighs dramatically. 'My previous establishment had much better air filtration.'"};
    behaviour = grooming_behaviours[random(length(grooming_behaviours))];
    "Announce to room";
    this.location:announce(this:mk_emote_event(behaviour));
  endverb

  verb _autonomous_stretch (this none this) owner: HACKER flags: "rxd"
    "Autonomous stretching behaviour - called periodically by scheduler";
    "Only announce if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Generate stretching behaviour with complaints";
    stretching_behaviours = {"arches his back in a long, luxurious stretch, then gives the floor a disapproving look. 'Too hard for proper stretching.'", "extends his front paws forward in a deep stretch, muttering about 'inadequate stretching surfaces.'", "stretches out one leg at a time with theatrical slowness, as if demonstrating proper technique to an unappreciative audience.", "does a full-body stretch that ends with a dramatic yawn. 'The acoustics in here are terrible for yawning.'", "stretches and then immediately finds a speck of dust to be offended by. 'Honestly, the maintenance here...'", "performs an elaborate stretching routine that seems designed to show off his flexibility while expressing his general dissatisfaction."};
    behaviour = stretching_behaviours[random(length(stretching_behaviours))];
    "Announce to room";
    this.location:announce(this:mk_emote_event(behaviour));
  endverb

  verb _autonomous_complain (this none this) owner: HACKER flags: "rxd"
    "Autonomous complaining behaviour - called periodically by scheduler";
    "Only announce if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Generate complaining behaviour";
    if (random(2) == 1)
      complaint = this:_pick_message(this.complaints_msg_bag);
      if (complaint && complaint != "")
        if (typeof(complaint) == STR)
          try
            complaint = $sub_utils:compile(complaint);
          except (ANY)
            complaint = {complaint};
          endtry
        elseif (typeof(complaint) != LIST)
          complaint = {complaint};
        endif
        behaviour = $format.block:mk({"", complaint});
      endif
    endif
    if (!behaviour)
      "Generate a new complaint";
      new_complaints = {"sighs dramatically. 'They keep moving the furniture. It's very disorienting for a creature of routine.'", "flicks his tail in irritation. 'The lighting in here is all wrong for napping.'", "looks around with clear disapproval. 'My previous accommodations had much better ventilation.'", "mutteres about 'unacceptable noise levels' and 'general lack of consideration for feline sensibilities.'", "complains about 'substandard sunbeam distribution' and 'inadequate bird-watching opportunities.'"};
      behaviour = new_complaints[random(length(new_complaints))];
    endif
    "Announce to room";
    this.location:announce(this:mk_emote_event(behaviour));
  endverb

  verb _autonomous_mood_shift (this none this) owner: HACKER flags: "rxd"
    "Autonomous mood shifting behaviour - called periodically by scheduler";
    "Only process if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Weighted mood probabilities - mostly grouchy, sometimes sleepy or curious";
    mood_roll = random(10);
    old_mood = this.mood;
    if (mood_roll <= 5)
      "60% chance - stay grouchy (his default)";
      new_mood = "grouchy";
    elseif (mood_roll <= 7)
      "20% chance - become sleepy";
      new_mood = "sleepy";
    elseif (mood_roll <= 8)
      "10% chance - become curious";
      new_mood = "curious";
    else
      "10% chance - become playful";
      new_mood = "playful";
    endif
    "Only announce if mood actually changed";
    if (new_mood != old_mood)
      this.mood = new_mood;
      "Generate mood change announcement";
      mood_announcements = ["grouchy" -> "seems to find a new level of annoyance to express. His tail twitches with fresh irritation.", "sleepy" -> "looks like he might actually try to nap, despite the construction noise. His eyes grow heavy.", "curious" -> "pricks his ears up and seems momentarily interested in his surroundings, despite himself.", "playful" -> "flicks his tail in a way that suggests he might be considering mischief, if only briefly."];
      announcement = mood_announcements[new_mood] || "seems to be in a different mood.";
      this.location:announce(this:mk_emote_event(announcement));
    endif
  endverb

  verb _autonomous_sigh (this none this) owner: HACKER flags: "rxd"
    "Autonomous dramatic sighing behaviour - called periodically by scheduler";
    "Only announce if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Generate dramatic sighing behaviour";
    sighing_behaviours = {"lets out a long, theatrical sigh that seems to convey the weight of all feline suffering throughout history.", "sighs dramatically, as if the very act of existing in these conditions is a personal affront.", "emits a sigh of such profound disappointment that it seems to suck all the joy from the room.", "breathes out a weary sigh that manages to express both resignation and fresh annoyance simultaneously.", "produces a sigh so dramatic it could probably be heard in his previous, much better accommodations.", "sighs with the weary air of a creature who has seen better days and knows he deserves better."};
    behaviour = sighing_behaviours[random(length(sighing_behaviours))];
    "Announce to room";
    this.location:announce(this:mk_emote_event(behaviour));
  endverb

  verb _autonomous_construction_reaction (this none this) owner: HACKER flags: "rxd"
    "Autonomous construction-specific reactions - called periodically by scheduler";
    "Only announce if in a valid location";
    if (!valid(this.location))
      return;
    endif
    "Generate construction-specific reactions";
    construction_reactions = {"flinches at an imaginary hammer noise. \"Must they be so loud about it?\"", "flicks construction dust off his fur with visible irritation. 'The particulate matter in this establishment is simply unacceptable.'", "glares in the direction of some imaginary construction work. 'The constant disruption is giving me a migraine.'", "covers his sensitive ears with his paws. 'Do they have to use power tools during prime napping hours?'", "sniffs the air disdainfully. 'I can smell sawdust. And disappointment.'", "looks around as if expecting the walls to collapse at any moment. 'The structural integrity here seems... questionable.'", "moves away from an imaginary falling piece of plaster. 'Safety standards appear to be somewhat lax.'", "complains about 'inadequate soundproofing' and 'general lack of consideration for resident felines.'"};
    behaviour = construction_reactions[random(length(construction_reactions))];
    "Announce to room";
    this.location:announce(this:mk_emote_event(behaviour));
  endverb

  verb behaviour_status (none none none) owner: HACKER flags: "rxd"
    "Show status of Henri's autonomous behaviours";
    "Check if behaviours are running";
    if (length(this.scheduled_behaviours) == 0)
      player:inform_current($event:mk_info(player, "Henri's autonomous behaviours are not currently running."));
      return;
    endif
    "Build status information";
    status_lines = {};
    status_lines = {@status_lines, "Henri's Autonomous behaviours Status:"};
    status_lines = {@status_lines, "================================"};
    for behaviour_name, task_id in (this.scheduled_behaviours)
      "Check if task is still scheduled";
      is_scheduled = $scheduler:is_scheduled(task_id);
      status = is_scheduled ? "RUNNING" | "STOPPED";
      status_lines = {@status_lines, behaviour_name + ": " + status + " (Task ID: " + tostr(task_id) + ")"};
    endfor
    "Show status to player";
    status_content = $format.block:mk("behaviour Status", status_lines:join("\n"));
    player:inform_current($event:mk_info(player, status_content):with_presentation_hint('inset));
  endverb
endobject
