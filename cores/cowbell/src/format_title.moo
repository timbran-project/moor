object FORMAT_TITLE
  name: "Title Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for title/heading content in events.";
  override import_export_id = "format_title";

  verb mk (this none this) owner: HACKER flags: "rxd"
    length(args) != 1 && raise(E_INVARG, "Title must have one argument");
    return <this, {@args}>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    pieces = {};
    contents = flycontents(this);
    for content in (contents)
      pieces = {@pieces, content:compose(@args)};
    endfor
    result = pieces:join(" ");
    if (content_type == 'text_html)
      return <$html, {"h3", {}, {result}}>;
    elseif (content_type == 'text_djot)
      return "## " + result + "\n";
    else
      return result + "\n";
    endif
  endverb
endobject