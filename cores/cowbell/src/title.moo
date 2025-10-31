object TITLE
  name: "Title Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override import_export_id = "title";

  verb mk (this none this) owner: HACKER flags: "rxd"
    length(args) != 1 && raise(E_INVARG, "Title must have one argument");
    return <this, {@args}>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    pieces = {};
    for content in (this)
      if (typeof(content) == STR)
        pieces = {@pieces, content};
      elseif (typeof(content) == FLYWEIGHT)
        pieces = {@pieces, content:compose(@args)};
      else
        raise(E_TYPE);
      endif
    endfor
    result = pieces:join(" ");
    if (content_type == 'text_html)
      return <$html, {"h3", {}, {result}}>;
    else
      return result;
    endif
  endverb
endobject