object FORMAT_TITLE
  name: "Title Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for title/heading content in events.";
  override import_export_hierarchy = {"format"};
  override import_export_id = "format_title";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a title flyweight. Args: (content) or (content, level)";
    {content, ?level = 3} = args;
    typeof(level) == INT || raise(E_TYPE, "Level must be an integer");
    level >= 1 && level <= 6 || raise(E_INVARG, "Level must be between 1 and 6");
    return <this, .level = level, {content}>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    pieces = {};
    contents = flycontents(this);
    for content in (contents)
      pieces = {@pieces, content:compose(@args)};
    endfor
    result = pieces:join(" ");
    level = `this.level ! E_PROPNF => 2';
    if (content_type == 'text_html)
      tag = "h" + tostr(level);
      return <$html, {tag, {}, {result}}>;
    elseif (content_type == 'text_djot)
      prefix = "#":repeat(level);
      return prefix + " " + result + "\n\n";
    else
      return result + "\n";
    endif
  endverb
endobject