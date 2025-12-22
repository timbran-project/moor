object FORMAT_LINK
  name: "Link Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for interactive links in events. Supports command links (moo://cmd/), inspect links (moo://inspect/), help links (moo://help/), and external URLs.";
  override import_export_hierarchy = {"format"};
  override import_export_id = "format_link";

  verb cmd (this none this) owner: HACKER flags: "rxd"
    "Create a command link that executes as if typed.";
    "Args: (command) or (command, label)";
    {command, ?label = false} = args;
    typeof(command) == STR || raise(E_TYPE, "Command must be a string");
    label = label ? label | command;
    return <this, .link_type = 'cmd, .command = command, .label = label>;
  endverb

  verb inspect (this none this) owner: HACKER flags: "rxd"
    "Create an inspect link that shows object info in a popover.";
    "Args: (target) or (target, label)";
    {target, ?label = false} = args;
    typeof(target) == OBJ || raise(E_TYPE, "Target must be an object");
    label = label ? label | `target:name() ! E_VERBNF => target.name';
    return <this, .link_type = 'inspect, .target = target, .label = label>;
  endverb

  verb help (this none this) owner: HACKER flags: "rxd"
    "Create a help link that opens documentation.";
    "Args: (topic) or (topic, label)";
    {topic, ?label = false} = args;
    typeof(topic) == STR || raise(E_TYPE, "Topic must be a string");
    label = label ? label | topic;
    return <this, .link_type = 'help, .topic = topic, .label = label>;
  endverb

  verb external (this none this) owner: HACKER flags: "rxd"
    "Create an external link that opens a URL in a new tab.";
    "Args: (url) or (url, label)";
    {url, ?label = false} = args;
    typeof(url) == STR || raise(E_TYPE, "URL must be a string");
    label = label ? label | url;
    return <this, .link_type = 'external, .url = url, .label = label>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    "Render link for the given content type.";
    {render_for, content_type, event} = args;
    if (this.link_type == 'inline)
      return this:_compose_inline(@args);
    endif
    if (content_type == 'text_html)
      return this:to_html();
    endif
    if (content_type == 'text_djot)
      return this:to_djot();
    endif
    return this.label;
  endverb

  verb to_djot (this none this) owner: HACKER flags: "rxd"
    "Render as djot link syntax: [label](url){.class}";
    if (this.link_type == 'cmd)
      url = "moo://cmd/" + urlencode(this.command);
      return "[" + this.label + "](" + url + "){.cmd}";
    elseif (this.link_type == 'inspect)
      oref = $url_utils:to_curie_str(this.target);
      url = "moo://inspect/" + oref;
      return "[" + this.label + "](" + url + "){.inspect}";
    elseif (this.link_type == 'help)
      url = "moo://help/" + urlencode(this.topic);
      return "[" + this.label + "](" + url + "){.help}";
    elseif (this.link_type == 'external)
      return "[" + this.label + "](" + this.url + "){.external}";
    endif
    return this.label;
  endverb

  verb to_html (this none this) owner: HACKER flags: "rxd"
    "Render as HTML anchor element.";
    if (this.link_type == 'cmd)
      url = "moo://cmd/" + urlencode(this.command);
      return <$html, {"a", {"href", url, "class", "cmd"}, {this.label}}>;
    elseif (this.link_type == 'inspect)
      oref = $url_utils:to_curie_str(this.target);
      url = "moo://inspect/" + oref;
      return <$html, {"a", {"href", url, "class", "inspect"}, {this.label}}>;
    elseif (this.link_type == 'help)
      url = "moo://help/" + urlencode(this.topic);
      return <$html, {"a", {"href", url, "class", "help"}, {this.label}}>;
    elseif (this.link_type == 'external)
      return <$html, {"a", {"href", this.url, "class", "external", "target", "_blank"}, {this.label}}>;
    endif
    return this.label;
  endverb

  verb test_cmd_link_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating command link flyweight.";
    fw = this:cmd("north");
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.link_type != 'cmd && return E_ASSERT;
    fw.command != "north" && return E_ASSERT;
    fw.label != "north" && return E_ASSERT;
    return true;
  endverb

  verb test_cmd_link_with_label (this none this) owner: HACKER flags: "rxd"
    "Test creating command link with custom label.";
    fw = this:cmd("take brass key", "key");
    fw.command != "take brass key" && return E_ASSERT;
    fw.label != "key" && return E_ASSERT;
    return true;
  endverb

  verb test_inspect_link_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating inspect link flyweight.";
    fw = this:inspect($room);
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.link_type != 'inspect && return E_ASSERT;
    fw.target != $room && return E_ASSERT;
    return true;
  endverb

  verb test_help_link_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating help link flyweight.";
    fw = this:help("movement");
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.link_type != 'help && return E_ASSERT;
    fw.topic != "movement" && return E_ASSERT;
    fw.label != "movement" && return E_ASSERT;
    return true;
  endverb

  verb test_external_link_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating external link flyweight.";
    fw = this:external("https://example.com", "Example");
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.link_type != 'external && return E_ASSERT;
    fw.url != "https://example.com" && return E_ASSERT;
    fw.label != "Example" && return E_ASSERT;
    return true;
  endverb

  verb test_cmd_link_html (this none this) owner: HACKER flags: "rxd"
    "Test command link renders to HTML.";
    fw = this:cmd("north");
    html_fw = fw:to_html();
    typeof(html_fw) != FLYWEIGHT && return E_TYPE;
    xml = html_fw:render('text_html);
    !index(xml, "moo://cmd/north") && return E_ASSERT;
    !index(xml, "class=\"cmd\"") && return E_ASSERT;
    return true;
  endverb

  verb test_cmd_link_encoding (this none this) owner: HACKER flags: "rxd"
    "Test command link URL encodes special characters.";
    fw = this:cmd("take brass key");
    html_fw = fw:to_html();
    xml = html_fw:render('text_html);
    !index(xml, "take%20brass%20key") && return E_ASSERT;
    return true;
  endverb

  verb test_plain_text_fallback (this none this) owner: HACKER flags: "rxd"
    "Test links render as plain label in text mode.";
    fw = this:cmd("north", "Go North");
    result = fw:compose($nothing, 'text_plain, $nothing);
    result != "Go North" && return E_ASSERT;
    return true;
  endverb

  verb inline (this none this) owner: HACKER flags: "rxd"
    "Create inline content mixing text and links.";
    "Args: list of strings and link flyweights to be composed inline.";
    "Example: $format.link:inline({'Exits: ', $format.link:cmd('north'), ', ', $format.link:cmd('south')})";
    {parts} = args;
    typeof(parts) == LIST || raise(E_TYPE, "Parts must be a list");
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb exits_line (this none this) owner: HACKER flags: "rxd"
    "Create an exits line with direction links.";
    "Args: list of exit direction strings.";
    {exits} = args;
    typeof(exits) == LIST || raise(E_TYPE, "Exits must be a list");
    length(exits) == 0 && return "";
    "Build parts list with links separated by commas";
    parts = {};
    if (length(exits) == 1)
      parts = {"An exit leads out ", this:cmd(exits[1]), "."};
    else
      parts = {"Exits lead out "};
      for i in [1..length(exits)]
        if (i > 1 && i == length(exits))
          parts = {@parts, " and "};
        elseif (i > 1)
          parts = {@parts, ", "};
        endif
        parts = {@parts, this:cmd(exits[i])};
      endfor
      parts = {@parts, "."};
    endif
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb things_line (this none this) owner: HACKER flags: "rxd"
    "Create a 'You see X, Y and Z here.' line with inspect links.";
    "Args: list of objects.";
    {objects} = args;
    typeof(objects) == LIST || raise(E_TYPE, "Objects must be a list");
    length(objects) == 0 && return "";
    parts = {"You see "};
    for i in [1..length(objects)]
      if (i > 1 && i == length(objects))
        parts = {@parts, " and "};
      elseif (i > 1)
        parts = {@parts, ", "};
      endif
      item = objects[i];
      label = `item:display_name() ! E_VERBNF => item.name';
      parts = {@parts, this:inspect(item, label)};
    endfor
    parts = {@parts, " here."};
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb actors_line (this none this) owner: HACKER flags: "rxd"
    "Create an 'X, Y and Z are here.' line with inspect links.";
    "Args: list of {actor, status} pairs where status can be empty string.";
    {actor_data} = args;
    typeof(actor_data) == LIST || raise(E_TYPE, "Actor data must be a list");
    length(actor_data) == 0 && return "";
    parts = {};
    for i in [1..length(actor_data)]
      if (i > 1 && i == length(actor_data))
        parts = {@parts, " and "};
      elseif (i > 1)
        parts = {@parts, ", "};
      endif
      {actor, status} = actor_data[i];
      actor_name = `actor:name() ! E_VERBNF => actor.name';
      label = status && status != "" ? actor_name + " (" + status + ")" | actor_name;
      parts = {@parts, this:inspect(actor, label)};
    endfor
    verb_form = length(actor_data) == 1 ? " is" | " are";
    parts = {@parts, verb_form, " here."};
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb sleeping_line (this none this) owner: HACKER flags: "rxd"
    "Create an 'X, Y and Z are deeply asleep.' line with inspect links.";
    "Args: list of {actor, status} pairs (status ignored for sleeping).";
    {actor_data} = args;
    typeof(actor_data) == LIST || raise(E_TYPE, "Actor data must be a list");
    length(actor_data) == 0 && return "";
    parts = {};
    for i in [1..length(actor_data)]
      if (i > 1 && i == length(actor_data))
        parts = {@parts, " and "};
      elseif (i > 1)
        parts = {@parts, ", "};
      endif
      {actor, status} = actor_data[i];
      actor_name = `actor:name() ! E_VERBNF => actor.name';
      parts = {@parts, this:inspect(actor, actor_name)};
    endfor
    verb_form = length(actor_data) == 1 ? " is" | " are";
    parts = {@parts, verb_form, " deeply asleep."};
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb _compose_inline (this none this) owner: HACKER flags: "rxd"
    "Internal: compose inline content for given content type.";
    {render_for, content_type, event} = args;
    parts = flycontents(this);
    if (content_type == 'text_html)
      "Build HTML span with mixed content";
      html_parts = {};
      for part in (parts)
        if (typeof(part) == FLYWEIGHT)
          html_parts = {@html_parts, part:compose(render_for, content_type, event)};
        else
          html_parts = {@html_parts, tostr(part)};
        endif
      endfor
      return <$html, {"span", {}, html_parts}>;
    endif
    "Djot or plain text: concatenate as string";
    result = "";
    for part in (parts)
      if (typeof(part) == FLYWEIGHT)
        result = result + part:compose(render_for, content_type, event);
      else
        result = result + tostr(part);
      endif
    endfor
    return result;
  endverb

  verb test_inline_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating inline content flyweight.";
    fw = this:inline({"Hello ", this:cmd("test"), "!"});
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.link_type != 'inline && return E_ASSERT;
    return true;
  endverb

  verb test_inline_plain_text (this none this) owner: HACKER flags: "rxd"
    "Test inline content renders to plain text.";
    fw = this:inline({"Go ", this:cmd("north"), " or ", this:cmd("south"), "."});
    result = fw:compose($nothing, 'text_plain, $nothing);
    result != "Go north or south." && return E_ASSERT;
    return true;
  endverb

  verb test_exits_line_single (this none this) owner: HACKER flags: "rxd"
    "Test exits line with single exit.";
    fw = this:exits_line({"north"});
    result = fw:compose($nothing, 'text_plain, $nothing);
    result != "An exit leads out north." && return E_ASSERT;
    return true;
  endverb

  verb test_exits_line_multiple (this none this) owner: HACKER flags: "rxd"
    "Test exits line with multiple exits.";
    fw = this:exits_line({"north", "south", "east"});
    result = fw:compose($nothing, 'text_plain, $nothing);
    result != "Exits lead out north, south and east." && return E_ASSERT;
    return true;
  endverb

  verb test_exits_line_html (this none this) owner: HACKER flags: "rxd"
    "Test exits line renders links in HTML.";
    fw = this:exits_line({"north", "south"});
    html_fw = fw:compose($nothing, 'text_html, $nothing);
    typeof(html_fw) != FLYWEIGHT && return E_TYPE;
    xml = html_fw:render('text_html);
    !index(xml, "moo://cmd/north") && return E_ASSERT;
    !index(xml, "moo://cmd/south") && return E_ASSERT;
    return true;
  endverb

  verb test_cmd_link_djot (this none this) owner: HACKER flags: "rxd"
    "Test command link renders to djot.";
    fw = this:cmd("north");
    djot = fw:to_djot();
    djot != "[north](moo://cmd/north){.cmd}" && return E_ASSERT;
    return true;
  endverb

  verb test_exits_line_djot (this none this) owner: HACKER flags: "rxd"
    "Test exits line renders links in djot.";
    fw = this:exits_line({"north", "south"});
    djot = fw:compose($nothing, 'text_djot, $nothing);
    !index(djot, "[north](moo://cmd/north){.cmd}") && return E_ASSERT;
    !index(djot, "[south](moo://cmd/south){.cmd}") && return E_ASSERT;
    return true;
  endverb

  verb test_inspect_link_djot (this none this) owner: HACKER flags: "rxd"
    "Test inspect link renders to djot with class.";
    fw = this:inspect($room, "a room");
    djot = fw:to_djot();
    !index(djot, "moo://inspect/") && return E_ASSERT;
    !index(djot, "{.inspect}") && return E_ASSERT;
    return true;
  endverb
endobject