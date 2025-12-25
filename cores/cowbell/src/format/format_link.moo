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

  verb inline (this none this) owner: HACKER flags: "rxd"
    "Create inline content mixing text and links.";
    "Args: list of strings and link flyweights to be composed inline.";
    "Example: $format.link:inline({'Exits: ', $format.link:cmd('north'), ', ', $format.link:cmd('south')})";
    {parts} = args;
    typeof(parts) == LIST || raise(E_TYPE, "Parts must be a list");
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

  verb ambient_passage (this none this) owner: HACKER flags: "rxd"
    "Create an ambient passage description with the direction as a command link.";
    "Args: {description, direction} - description text containing direction word, direction is the command.";
    {description, direction} = args;
    typeof(description) == STR || raise(E_TYPE, "Description must be a string");
    typeof(direction) == STR || raise(E_TYPE, "Direction must be a string");
    "Find the direction in the description";
    idx = index(description, direction);
    if (idx == 0)
      "Direction not found in description - append link at end";
      parts = {description, " (", this:cmd(direction), ")"};
    else
      "Split description around direction and insert link";
      before = description[1..idx - 1];
      "Get the actual text that matched (preserve original case)";
      matched = description[idx..idx + length(direction) - 1];
      after = description[idx + length(direction)..length(description)];
      parts = {before, this:cmd(direction, matched), after};
    endif
    return <this, .link_type = 'inline, {@parts}>;
  endverb

  verb linkify_direction (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Replace a direction word in a description with a command link.";
    "Args: (description, direction, ?lowercase=false) - returns inline flyweight or original string if not found.";
    {description, direction, ?lowercase = false} = args;
    typeof(description) == STR || return description;
    typeof(direction) == STR || return description;
    "Find the direction word in the description (case-insensitive)";
    pos = index(description, direction);
    !pos && return lowercase ? description:initial_lowercase() | description;
    "Split and create inline with link";
    before = pos > 1 ? description[1..pos - 1] | "";
    if (lowercase && length(before) > 0)
      before = before:initial_lowercase();
    endif
    after = pos + length(direction) <= length(description) ? description[pos + length(direction)..length(description)] | "";
    "Use 'go <direction>' as command so non-standard exit names work";
    link = this:cmd("go " + direction, direction);
    return this:inline({before, link, after});
  endverb
endobject