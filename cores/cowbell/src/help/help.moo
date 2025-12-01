object HELP
  name: "Help Topic Flyweight Delegate"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for help topics. Creates structured help entries that can be rendered for humans or machines.";
  override import_export_hierarchy = {"help"};
  override import_export_id = "help";

  verb mk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a help topic flyweight.";
    "Args: (name, summary, content, ?aliases, ?category, ?see_also)";
    {name, summary, content, ?aliases = {}, ?category = 'general, ?see_also = {}} = args;
    return <this, .name = name, .summary = summary, .content = content, .aliases = aliases, .category = category, .see_also = see_also>;
  endverb

  verb matches (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if this help topic matches a search query (supports prefix matching).";
    {query} = args;
    "Exact match on name";
    this.name == query && return true;
    "Prefix match on name";
    index(this.name, query) == 1 && return true;
    "Check aliases";
    for alias in (this.aliases)
      alias == query && return true;
      index(alias, query) == 1 && return true;
    endfor
    return false;
  endverb

  verb render_prose (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Render this help topic as a list of lines (splat into a block).";
    lines = {};
    lines = {@lines, this.summary};
    lines = {@lines, ""};
    "Split content on newlines so each becomes a separate line";
    for line in (this.content:split("\n"))
      lines = {@lines, line};
    endfor
    if (length(this.see_also) > 0)
      lines = {@lines, ""};
      lines = {@lines, "See also: " + this.see_also:join(", ")};
    endif
    return lines;
  endverb

  verb render_structured (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return structured data for agents/LLMs.";
    return ['name -> this.name, 'aliases -> this.aliases, 'category -> this.category, 'summary -> this.summary, 'content -> this.content, 'see_also -> this.see_also];
  endverb
endobject