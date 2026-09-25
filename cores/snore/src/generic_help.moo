object GENERIC_HELP [
  import_export_id -> "generic_help"
]
  name: "Generic Help Database"
  parent: ROOT_CLASS
  owner: HACKER
  fertile: true
  readable: true

  property index (owner: HACKER, flags: "rc") = {};
  property index_cache (owner: HACKER, flags: "r") = {};

  override aliases (owner: HACKER, flags: "rc") = {"Generic Help Database"};
  override description (owner: HACKER, flags: "rc") = "A help database of the standard form in need of a description. See `help $generic_help'...";
  override object_size (owner: HACKER, flags: "r") = {9501, 1084848672};

  method find_topics owner: #2
    "WIZARDLY";
    let props;
    let i;
    if (args)
      "...check for an exact match first...";
      let search = args[1];
      if (`$object_utils:has_property(parent(this), search) ! ANY')
        $object_utils:has_property(this, " " + search) && return {search};
      elseif ($object_utils:has_property(this, search))
        return {search};
      endif
      "...search for partial matches, allowing for";
      "...confusion between topics that do and don't start with @, and";
      ".. confusion between - and _ characters.";
      props = properties(this);
      let topics = {};
      if (search[1] == "@")
        search = search[2..$];
      endif
      search = strsub(search, "-", "_");
      if (!search)
        "...don't try searching for partial matches if the string is empty or @";
        "...we'd get *everything*...";
        return {};
      endif
      for prop in (props)
        i = index(strsub(prop, "-", "_"), search);
        if (i == 1 || (i == 2 && index(" @", prop[1])))
          topics = {@topics, prop[1] == " " ? prop[2..$] | prop};
        endif
      endfor
      return topics;
    else
      "...return list of all topics...";
      props = setremove(properties(this), "");
      for p in (`$object_utils:all_properties(parent(this)) ! ANY => {}')
        i = " " + p in props;
        if (i)
          props = {p, @listdelete(props, i)};
        endif
      endfor
      return props;
    endif
  endmethod

  method get_topic owner: #2
    "WIZARDLY";
    let text;
    let vb;
    const {topic, ?dblist = {}} = args;
    if (`$object_utils:has_property(parent(this), topic) ! ANY')
      text = `this.(" " + topic) ! ANY';
    else
      text = `this.(topic) || this.(" " + topic) ! ANY';
    endif
    if (typeof(text) == TYPE_LIST)
      vb = text ? strsub(text[1], "*", "") | "";
      if (text && text[1] == "*" + vb + "*")
        text = `this:(vb)(listdelete(text, 1), dblist) ! ANY';
      endif
    endif
    return text;
  endmethod

  method sort_topics owner: HACKER
    ":sort_topics(list_of_topics) -- sorts the given list of strings, assuming that they're help-system topic names";
    let names;
    const buckets = "abcdefghijklmnopqrstuvwxyz";
    const keys = names = $list_utils:make(length(buckets) + 1, {});
    for name in (setremove(args[1], ""))
      const key = index(".@", name[1]) ? name[2..$] + " " | name;
      const k = index(buckets, key[1]) + 1;
      const bucket = keys[k];
      const i = $list_utils:find_insert(bucket, key);
      keys[k] = listinsert(bucket, key, i);
      names[k] = listinsert(names[k], name, i);
      $command_utils:suspend_if_needed(0);
    endfor
    return $list_utils:append(@names);
  endmethod

  method columnize owner: HACKER
    "Return topic names as complete lines. The client controls their visual layout.";
    return args;
  endmethod

  method "forward pass" owner: HACKER
    "{\"*forward*\", topic, @rest}  => text for topic from this help db.";
    "{\"*pass*\",    topic, @rest}  => text for topic from next help db.";
    "In both cases the text of @rest is appended.  ";
    "@rest may in turn begin with a *<verb>*";
    let first;
    let result;
    let db;
    let vb;
    const {text, ?dblist = {}} = args;
    if (verb == "forward")
      first = this:get_topic(text[1], dblist);
    else
      result = $code_utils:help_db_search(text[1], dblist);
      if (result)
        db = result[1];
      endif
      if (result && db != $ambiguous_match)
        first = db:get_topic(result[2], dblist[(db in dblist) + 1..$]);
      else
        first = {};
      endif
    endif
    if (2 <= length(text))
      vb = strsub(text[2], "*", "");
      text[2] == "*" + vb + "*" && return {@first, @`this:(vb)(text[3..$], dblist) ! ANY => {}'};
      return {@first, @text[2..$]};
    else
      return first;
    endif
  endmethod

  method subst owner: HACKER
    "{\"*subst*\", @text} => text with the following substitutions:";
    "  \"...%[expr]....\" => \"...\"+value of expr (assumed to be a string)+\"....\"";
    "  \"%;expr\"         => @(value of expr (assumed to be a list of strings))";
    let b;
    let p;
    let value;
    let r;
    let newlines = {};
    for old in (args[1])
      let new = "";
      let bomb = 0;
      while (true)
        const prcnt = index(old, "%");
        if (!(prcnt && prcnt < length(old)))
          break;
        endif
        new = new + old[1..prcnt - 1];
        const code = old[prcnt + 1];
        old = old[prcnt + 2..$];
        if (code == "[")
          let prog = "";
          while (true)
            b = index(old + "]", "]");
            p = index(old + "%", "%");
            if (b <= p)
              break;
            endif
            prog = prog + old[1..p - 1] + old[p + 1];
            old = old[p + 2..$];
          endwhile
          prog = prog + old[1..b - 1];
          old = old[b + 1..$];
          value = $no_one:eval_d(prog);
          if (value[1])
            new = tostr(new, value[2]);
          else
            new = tostr(new, toliteral(value[2]));
            bomb = 1;
          endif
        elseif (code != ";" || new)
          new = new + "%" + code;
        else
          value = $no_one:eval_d(old);
          r = value[1] ? value[2] | {};
          if (value[1] && typeof(r) == TYPE_LIST)
            newlines = {@newlines, @r[1..$ - 1]};
            new = tostr(r[$]);
          else
            new = tostr(new, toliteral(value[2]));
            bomb = 1;
          endif
          old = "";
        endif
      endwhile
      if (bomb)
        newlines = {@newlines, new + old, tostr("@@@ Helpfile alert:  Previous line is messed up; notify ", this.owner.wizard ? "" | tostr(this.owner.name, " (", this.owner, ") or "), "a wizard. @@@")};
      else
        newlines = {@newlines, new + old};
      endif
    endfor
    return newlines;
  endmethod

  method index owner: HACKER
    "{\"*index*\" [, title]}";
    "Return complete topic-name lines from this help database, headed by title.";
    $command_utils:suspend_if_needed(0);
    const title = args[1] ? args[1][1] | tostr(this.name, " (", this, ")");
    const su = $string_utils;
    return {"", title, su:from_list($list_utils:map_arg(su, "space", su:explode(title), "-"), " "), @this:columnize(@this:sort_topics(this:find_topics()))};
  endmethod

  method initialize owner: #2
    "Initialize an owned help database as readable and infertile.";
    pass(@args);
    if ($perm_utils:controls(caller_perms(), this))
      this.r = 1;
      this.f = 0;
    endif
  endmethod

  method verbdoc owner: #2
    "{\"*verbdoc*\", \"object\", \"verbname\"}  use documentation for this verb";
    let vname;
    set_task_perms(this.owner);
    const object = $string_utils:match_object(args[1][1], player.location);
    !valid(object) && return E_INVARG;
    const hv = $object_utils:has_verb(object, vname = args[1][2]);
    !hv && return E_VERBNF;
    return $code_utils:verb_documentation(hv[1], vname);
  endmethod

  method dump_topic owner: #2
    "Return commands that recreate a topic, or the property access error.";
    let fulltopic;
    try
      const text = this.(fulltopic = args[1]);
      return {tostr(";;", $code_utils:corify_object(this), ".(", toliteral(fulltopic), ") = $command_utils:read_lines()"), @$command_utils:dump_lines(text)};
    except error (ANY)
      return error[1];
    endtry
  endmethod

  method objectdoc owner: HACKER
    "{\"*objectdoc*\", \"object\"} => text for topic from object:help_msg";
    const object = $string_utils:literal_object(args[1][1]);
    !valid(object) && return E_INVARG;
    !($object_utils:has_verb(object, "help_msg") || $object_utils:has_property(object, "help_msg")) && return E_VERBNF;
    return $code_utils:verb_or_property(object, "help_msg");
  endmethod

  method find_index_topics owner: HACKER
    ":find_index_topic([search])";
    "Return the list of index topics of this help DB";
    "(i.e., those which contain an index (list of topics)";
    "this DB, return it, otherwise return false.";
    "If search argument is given and true,";
    "we first remove any cached information concerning index topics.";
    let {?search = 0} = args;
    if (this.index_cache && !search)
      "...make sure every topic listed in .index_cache really is an index topic";
      for p in (this.index_cache)
        if (!("*index*" in `this.(p) ! ANY => {}'))
          search = 1;
        endif
      endfor
      !search && return this.index_cache;
    elseif ($generic_help == this)
      return {};
    endif
    let itopics = {};
    for p in (properties(this))
      const h = `this.(p) ! ANY';
      if (h && "*index*" in h)
        itopics = {@itopics, p};
      endif
    endfor
    this.index_cache = itopics;
    return itopics;
  endmethod
endobject
