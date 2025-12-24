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
    "NPCs don't have connection state - no status";
    is_player(who) || return "";
    "Players who aren't connected are sleeping";
    who in connected_players() || return "deeply asleep";
    if (typeof(idle = idle_seconds(who)) == ERR)
      return "";
    endif
    idle < 60 && return "awake";
    idle < 180 && return "dozing";
    idle < 600 && return "idle";
    idle < 1800 && return "out on his feet";
    return "sleeping";
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
    deeply_asleep = {};
    flyweight_contents = flycontents(this);
    for o in (flyweight_contents)
      if (o == player)
        continue;
      endif
      integrated_description = `o:integrate_description() ! E_VERBNF => false';
      if (integrated_description)
        integrated_contents = {@integrated_contents, integrated_description};
      elseif (o:is_actor())
        "Collect actor with idle status for inspect links";
        status = this:actor_idle_status(o);
        if (status == "deeply asleep")
          deeply_asleep = {@deeply_asleep, {o, ""}};
        elseif (status && status != "awake")
          actors = {@actors, {o, status}};
        else
          actors = {@actors, {o, ""}};
        endif
      else
        things = {@things, o};
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
      "Process ambient passages based on prose_style";
      fragment_passages = {};
      for ap in (ambient_passages)
        "Handle formats: string, {desc, style}, or {desc, style, label}";
        label = "";
        if (typeof(ap) == LIST && length(ap) >= 3)
          {description, prose_style, label} = ap;
        elseif (typeof(ap) == LIST && length(ap) >= 2)
          {description, prose_style} = ap;
        else
          description = ap;
          prose_style = 'fragment;
        endif
        if (prose_style == 'sentence)
          "Complete sentence - linkify direction if label provided";
          if (label)
            formatted = $format.link:linkify_direction(description, label);
            "Capitalize the result";
            if (typeof(formatted) == STR)
              formatted = formatted:capitalize();
              if (!formatted:ends_with(".") && !formatted:ends_with("!") && !formatted:ends_with("?"))
                formatted = formatted + ".";
              endif
            endif
          else
            formatted = description:capitalize();
            if (typeof(formatted) == STR && !formatted:ends_with(".") && !formatted:ends_with("!") && !formatted:ends_with("?"))
              formatted = formatted + ".";
            endif
          endif
          desc_content = {@desc_content, "  ", formatted};
        else
          "Fragment - strip trailing punctuation since we wrap in 'You see X.'";
          if (typeof(description) == STR)
            while (length(description) > 0 && (description:ends_with(".") || description:ends_with("!") || description:ends_with("?")))
              description = description[1..length(description) - 1];
            endwhile
          endif
          "Linkify with lowercase if label provided, collect for 'You see X' treatment";
          if (label)
            linkified = $format.link:linkify_direction(description, label, true);
            fragment_passages = {@fragment_passages, linkified};
          else
            fragment_passages = {@fragment_passages, description:initial_lowercase()};
          endif
        endif
      endfor
      "Combine fragment passages with 'You see' wrapper";
      if (length(fragment_passages))
        "Build inline content: 'You see X, Y and Z.'";
        parts = {"  You see "};
        for i in [1..length(fragment_passages)]
          frag = fragment_passages[i];
          if (i > 1 && i == length(fragment_passages))
            parts = {@parts, " and "};
          elseif (i > 1)
            parts = {@parts, ", "};
          endif
          parts = {@parts, frag};
        endfor
        parts = {@parts, "."};
        desc_content = {@desc_content, $format.link:inline(parts)};
      endif
    endif
    "Wrap desc_content in inline so it composes properly as a flyweight";
    block_elements = {title, $format.link:inline(desc_content)};
    "Add exits if present (with command links)";
    exits = `this.exits ! E_PROPNF => {}';
    if (length(exits) > 0)
      block_elements = {@block_elements, $format.link:exits_line(exits)};
    endif
    if (length(things))
      block_elements = {@block_elements, $format.link:things_line(things)};
    endif
    if (length(actors))
      block_elements = {@block_elements, $format.link:actors_line(actors)};
    endif
    if (length(deeply_asleep))
      block_elements = {@block_elements, $format.link:sleeping_line(deeply_asleep)};
    endif
    b = $format.block:mk(@block_elements);
    event = $event:mk_look(player, b):with_dobj(this.what):with_metadata('preferred_content_types, {'text_html, 'text_plain}):with_presentation_hint('inset):with_group('look, this.what);
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
    typeof(this) != FLYWEIGHT && return false;
    try
      return this.what && this.title && this.description;
    except (E_PROPNF)
      return false;
    endtry
  endverb
endobject