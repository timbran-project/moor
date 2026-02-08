object HELP_SOURCE
  name: "Help Source Prototype"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property topic_order (owner: ARCH_WIZARD, flags: "rc") = {};

  override import_export_hierarchy = {"help"};
  override import_export_id = "help_source";

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Generic property-backed help topic provider.";
    "Reads topic_* properties as either $help flyweights or tuple data.";
    {for_player, ?topic = ""} = args;
    props = properties(this);
    order = `this.topic_order ! ANY => {}';
    if (typeof(order) != TYPE_LIST)
      order = {};
    endif
    seen = [];
    names = {};
    for p in (order)
      if (typeof(p) == TYPE_STR && index(p, "topic_") == 1 && p in props)
        names = {@names, p};
        seen[p] = 1;
      endif
    endfor
    for p in (props)
      if (index(p, "topic_") == 1 && !maphaskey(seen, p))
        names = {@names, p};
      endif
    endfor
    my_topics = {};
    for prop in (names)
      data = `this.(prop) ! ANY => 0';
      if (typeof(data) == TYPE_FLYWEIGHT)
        t = data;
      elseif (typeof(data) == TYPE_LIST && length(data) >= 3)
        {name, summary, content, ?aliases = {}, ?category = "general", ?see_also = {}} = data;
        if (typeof(name) != TYPE_STR || !name)
          continue;
        endif
        if (typeof(summary) != TYPE_STR)
          summary = tostr(summary);
        endif
        if (typeof(content) != TYPE_STR)
          content = tostr(content);
        endif
        typeof(aliases) == TYPE_LIST || (aliases = {});
        typeof(see_also) == TYPE_LIST || (see_also = {});
        if (typeof(category) == TYPE_STR)
          cat = tosym(category);
        else
          cat = category;
        endif
        t = $help:mk(name, summary, content, aliases, cat, see_also);
      else
        continue;
      endif
      if (topic == "")
        my_topics = {@my_topics, t};
      elseif (`t:matches(topic) ! ANY => false')
        return t;
      endif
    endfor
    return topic == "" ? my_topics | 0;
  endverb
endobject