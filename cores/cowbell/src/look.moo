object LOOK
  name: "Object 'look' Flyweight Delegate"
  parent: ROOT
  owner: HACKER

  override description = "The $look flyweight delegate holds the attributes involved in looking at an object, and can be transformed into output events. It always has mandatory 'title and 'description slots, and then optional contents which are a series of integration descriptions.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    {what, @contents} = args;
    return <this, [what -> what, title -> what:name(), description -> what:description()], {@contents}>;
  endverb

  verb into_event (this none this) owner: HACKER flags: "rxd"
    "Three lines -- title, description, contents.";
    "Description is the item description but is also appended to with integrations. Objects with an :integrate_description verb are put there.";
    "The remainder go into the contents block.";
    "Title is the direct-object-capitalized";
    let title = $sub:dc();
    let integrated_contents = {};
    let contents = {};
    for o in (this)
      let integrated_description = `o:integrate_description() ! E_VERBNF => false';
      if (integrated_description)
        integrated_contents = {@integrated_contents, integrated_description};
      else
        contents = {@contents, o:name()};
      endif
    endfor
    description = this.description;
    if (length(integrated_contents))
      description = description + " " + { ic + "." for ic in (integrated_contents) }:to_list();
    endif
    let block_elements = {$sub:dc(), description};
    if (length(contents))
        block_elements = {@block_elements, "You see " + contents:english_list() + " here."};
    endif
    let b = $block:mk(@block_elements);
    return $event:mk_look(player, b):with_dobj(this.what);
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    if (typeof(this) != flyweight)
      return false;
    endif
    try
      this.what && this.title && this.description && return true;
    except (E_PROPNF)
      return false;
    endtry
    return true;
  endverb

  verb test_into_event (this none this) owner: HACKER flags: "rxd"
    look = this:mk($first_room, player);
    !look:validate() && raise(E_ASSERT, "Invalid $look: " + toliteral(look));
    event = look:into_event();
    !event:validate() && raise(E_ASSERT, "Invalid event");
    !(typeof(event) == flyweight) && raise(E_ASSERT, "look event should be a flyweight");
    event.dobj != $first_room && raise(E_ASSERT, "look event dobj is wrong");
    content = event:transform_to();
    typeof(content) != list && raise(E_ASSERT, "Produced content is invalid: " + toliteral(content));
    length(content) != 3 && raise(E_ASSERT, "Produced content is wrong length: " + toliteral(content) + " from " + toliteral(event));
  endverb
endobject
