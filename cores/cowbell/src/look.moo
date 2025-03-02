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
    return $event:mk_look(player, $block:mk($sub:dc()), this.description):with_dobj(this.what);
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
    !look:validate() && raise(E_INVARG, "Invalid $look: " + toliteral(look));
    event = look:into_event();
    !event:validate() && raise(E_INVARG, "Invalid event");
    !(typeof(event) == flyweight) && raise(E_NONE, "look event should be a flyweight");
    event.dobj != $first_room && raise(E_NONE, "look event dobj is wrong");
    content = event:transform_to();
    typeof(content) != list && raise(E_INVARG, "Produced content is invalid: " + toliteral(content));
    length(content) != 2 && raise(E_INVARG, "Produced content is not long enough: " + toliteral(content));
  endverb
endobject
