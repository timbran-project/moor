object LOOK
  name: "Object 'look' Flyweight Delegate"
  parent: ROOT
  owner: HACKER

  override description = "The $look flyweight delegate holds the attributes involved in looking at an object, and can be transformed into output events. It always has mandatory 'title and 'description slots, and then optional contents which are a series of integration descriptions.";
  override import_export_id = "look";

  verb mk (this none this) owner: HACKER flags: "rxd"
    {what, @contents} = args;
    return <this, .what = what, .title = what:name(), .description = what:description(), .exits = {}, .ambient_passages = {}, {@contents}>;
  endverb

  verb actor_idle_status (this none this) owner: HACKER flags: "rxd"
    "Get a descriptive idle status for an actor (player or NPC)";
    {who} = args;
    if (!who:is_actor())
      return "";
    endif
    "NPCs don't have connection state - no status";
    if (!is_player(who))
      return "";
    endif
    "Players who aren't connected are sleeping";
    if (!(who in connected_players()))
      return "sleeping";
    endif
    if (typeof(idle = idle_seconds(who)) == ERR)
      return "";
    endif
    if (idle < 60)
      return "awake";
    elseif (idle < 180)
      return "dozing";
    elseif (idle < 600)
      return "idle";
    elseif (idle < 1800)
      return "out on his feet";
    else
      return "deeply asleep";
    endif
  endverb

  verb into_event (this none this) owner: HACKER flags: "rxd"
    "Three lines -- title, description, contents.";
    "Description is the item description but is also appended to with integrations. Objects with an :integrate_description verb are put there.";
    "The remainder go into the contents block, separated by type: actors vs things.";
    title = $format.title:mk($sub:dc());
    "Normalize base description so lists with $sub flyweights remain intact";
    description = this.description;
    desc_content = {};
    if (typeof(description) == LIST)
      desc_content = description;
    elseif (typeof(description) == STR)
      desc_content = {description};
    else
      desc_content = {tostr(description)};
    endif
    integrated_contents = {};
    things = {};
    actors = {};
    flyweight_contents = flycontents(this);
    for o in (flyweight_contents)
      if (o == player)
        continue;
      endif
      integrated_description = `o:integrate_description() ! E_VERBNF => false';
      if (integrated_description)
        integrated_contents = {@integrated_contents, integrated_description};
      elseif (o:is_actor())
        "Format actor with idle status";
        status = this:actor_idle_status(o);
        actor_name = `o:name() ! E_VERBNF => o.name';
        if (status)
          actors = {@actors, actor_name + " (" + status + ")"};
        else
          actors = {@actors, actor_name};
        endif
      else
        things = {@things, `o:display_name() ! E_VERBNF => o.name'};
      endif
    endfor
    "Combine integrated object descriptions and ambient passages into the main paragraph";
    ambient_passages = `this.ambient_passages ! E_PROPNF => {}';
    if (length(integrated_contents))
      for ic in (integrated_contents)
        ic_formatted = ic:capitalize();
        if (typeof(ic_formatted) == STR && !ic_formatted:ends_with("."))
          ic_formatted = ic_formatted + ".";
        endif
        desc_content = {@desc_content, "  ", ic_formatted};
      endfor
    endif
    if (length(ambient_passages))
      lowercased_passages = { desc:initial_lowercase() for desc in (ambient_passages) };
      desc_content = {@desc_content, "  You see ", lowercased_passages:english_list(), "."};
    endif
    block_elements = {title, desc_content};
    "Add exits if present";
    exits = `this.exits ! E_PROPNF => {}';
    if (length(exits) > 1)
      block_elements = {@block_elements, "Exits lead out " + exits:join(", ") + "."};
    elseif (length(exits) == 1)
      block_elements = {@block_elements, "An exit leads out " + exits[1] + "."};
    endif
    if (length(things))
      block_elements = {@block_elements, "You see " + things:english_list() + " here."};
    endif
    if (length(actors))
      block_elements = {@block_elements, actors:english_list() + " " + (length(actors) == 1 ? "is" | "are") + " here."};
    endif
    b = $format.block:mk(@block_elements);
    event = $event:mk_look(player, b):with_dobj(this.what):with_metadata('preferred_content_types, {'text_html, 'text_plain}):with_presentation_hint('inset);
    "Add thumbnail if the target has one";
    if (respond_to(this.what, 'thumbnail))
      pic = `this.what:thumbnail() ! ANY => false';
      if (pic && typeof(pic) == LIST && length(pic) == 2)
        event = event:with_metadata('thumbnail, pic);
      endif
    endif
    return event;
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    if (typeof(this) != FLYWEIGHT)
      return false;
    endif
    try
      this.what && this.title && this.description && return true;
    except (E_PROPNF)
      return false;
    endtry
    return true;
  endverb
endobject