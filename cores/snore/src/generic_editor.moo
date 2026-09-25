object GENERIC_EDITOR [
  import_export_id -> "generic_editor"
]
  name: "Generic Editor"
  parent: ROOM
  owner: #96
  fertile: true
  readable: true

  property active (owner: #96, flags: "r") = {};
  property change_msg (owner: #96, flags: "rc") = "Text has been altered since the last save.";
  property changes (owner: #96, flags: "") = {};
  property commands (owner: #96, flags: "rc") = {
    {"say", "<text>"},
    {"emote", "<text>"},
    {"lis*t", "[<range>] [nonum]"},
    {"ins*ert", "[<ins>] [\"<text>]"},
    {"n*ext,p*rev", "[n] [\"<text>]"},
    {"del*ete", "[<range>]"},
    {"f*ind", "/<str>[/[c][<range>]]"},
    {"s*ubst", "/<str1>/<str2>[/[g][c][r][<range>]]"},
    {"m*ove,c*opy", "[<range>] to <ins>"},
    {"join*l", "[<range>]"},
    {"fill", "[<range>] [@<col>]"},
    {"w*hat", ""},
    {"abort", ""},
    {"q*uit,done,pause", ""},
    {"enter", ""},
    {"y*ank", "from <text-source>"}
  };
  property commands2 (owner: #96, flags: "rc") = {
    {
      "say",
      "emote",
      "lis*t",
      "ins*ert",
      "n*ext,p*rev",
      "del*ete",
      "f*ind",
      "s*ubst",
      "m*ove,c*opy",
      "join*l",
      "fill"
    },
    {"y*ank", "w*hat", "abort", "q*uit,done,pause"}
  };
  property depart_msg (owner: #96, flags: "rc") = "%N heads off to the Generic Editing Room.";
  property exit_on_abort (owner: #96, flags: "rc") = false;
  property help (owner: #96, flags: "rc") = EDITOR_HELP;
  property input_versions (owner: #96, flags: "") = [];
  property inserting (owner: #96, flags: "") = {};
  property invoke_task (owner: #96, flags: "r") = 0;
  property no_change_msg (owner: #96, flags: "rc") = "There have been no changes since the last save.";
  property no_littering_msg (owner: #96, flags: "rc") = "Keeping your [whatever] for later work.  Since this the Generic Editor, you have to do your own :set_changed(0) so that we'll know to get rid of whatever it you're working on when you leave.  Please don't litter... especially in the Generic Editor.";
  property no_text_msg (owner: #96, flags: "rc") = "There are no lines of text.";
  property nothing_loaded_msg (owner: #96, flags: "rc") = "You're not currently editing anything.";
  property original (owner: #96, flags: "r") = {};
  property previous_session_msg (owner: #96, flags: "rc") = "";
  property readable (owner: #96, flags: "r") = {};
  property return_msg (owner: #96, flags: "rc") = "%N comes back from the Generic Editing Room.";
  property stateprops (owner: #96, flags: "r") = {{"texts", 0}, {"changes", false}, {"inserting", 1}, {"readable", false}};
  property texts (owner: #96, flags: "") = {};
  property times (owner: #96, flags: "r") = {};

  override aliases (owner: #96, flags: "rc") = {"Generic Editor", "gedit", "edit"};
  override blessed_task (owner: #96, flags: "rc") = 1399008566;
  override description (owner: #96, flags: "rc") = {};
  override entrances (owner: #96, flags: "c") = {#5751};
  override object_size (owner: HACKER, flags: "r") = {51968, 1084848672};
  override who_location_msg (owner: #96, flags: "rc") = "%L [editing]";

  verb say (any any any) owner: #96 flags: "rxd"
    "Insert text at the cursor; callable by the player's speech shortcut.";
    caller != player && caller_perms() != player && return E_PERM;
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    this:insert_line(who, argstr);
  endverb

  verb emote (any any any) owner: #96 flags: "rxd"
    "Append text to the preceding line; callable by the player's emote shortcut.";
    caller != player && caller_perms() != player && return E_PERM;
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    this:append_line(who, argstr);
  endverb

  verb enter (any none none) owner: #96 flags: "rd"
    "Read lines into the current buffer; discard them if that buffer is replaced while waiting.";
    return this:_read_into_buffer();
  endverb

  method _read_into_buffer owner: #96
    "Read for the current player, then revalidate the loaded buffer across read() commits.";
    caller != this && return E_PERM;
    let who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    !maphaskey(this.input_versions, player) && this:_renew_input_version(who);
    const version = this.input_versions[player];
    const lines = $command_utils:read_lines();
    typeof(lines) == TYPE_ERR && return player:notify(tostr(lines));
    who = this:loaded(player);
    if (!who || player.location != this || !maphaskey(this.input_versions, player))
      return player:tell("Input discarded: your editing session changed while waiting.");
    endif
    if (this.input_versions[player] != version)
      return player:tell("Input discarded: your editing session changed while waiting.");
    endif
    return this:insert_line(who, lines, false);
  endmethod

  method _renew_input_version owner: #96
    "Assign a fresh identity to a buffer; only editor lifecycle methods may call this.";
    caller != this && return E_PERM;
    const {who} = args;
    const version = uuid();
    this.input_versions[this.active[who]] = version;
    return version;
  endmethod

  verb "lis*t view" (any any any) owner: #96 flags: "rd"
    "List the current buffer or another player's published buffer, with optional ranges and nonum.";
    "Keep listing in one transaction so the selected session and its publication state stay consistent.";
    let who = 0;
    let range_args = args;
    if (verb == "view")
      if (!args)
        let publishers = {};
        for session in [1..length(this.active)]
          this.readable[session] && (publishers = {@publishers, this.active[session]});
        endfor
        !publishers && return player:tell("No one has published anything in this editor.");
        return player:tell("Players having readable texts in this editor:  ", $string_utils:names_of(publishers));
      endif
      const target = $string_utils:match_player(args[1]);
      $command_utils:player_match_result(target, args[1])[1] && return;
      who = this:loaded(target);
      if (!who || !this:readable(who))
        return player:tell(target.name, "(", target, ") has not published anything in this editor.");
      endif
      range_args = listdelete(range_args, 1);
    else
      who = this:loaded(player);
      !who && return player:tell(this:nothing_loaded_msg());
    endif
    const count = length(this.texts[who]);
    const insertion = this.inserting[who];
    const window = 8;
    let defaults = {"1-$"};
    if (count >= 2 * window)
      defaults = insertion <= window ? {tostr("1-", 2 * window)} | {tostr(window, "_-", window, "^"), tostr(2 * window, "$-$")};
    endif
    const range = this:parse_range(who, defaults, @range_args);
    typeof(range) != TYPE_LIST && return player:tell(tostr(range));
    const nonum = $string_utils:trim(range[3]) == "nonum";
    range[3] && !nonum && return player:tell("Don't understand this:  ", range[3]);
    nonum && return player:tell_lines(this.texts[who][range[1]..range[2]]);
    for line in [range[1]..range[2]]
      this:list_line(who, line);
    endfor
    insertion > count && count == range[2] && player:tell("^^^^");
  endverb

  verb "ins*ert n*ext p*revious ." (any none none) owner: #96 flags: "rd"
    "Set the insertion point, optionally inserting text after a quote. next/previous use offsets.";
    const quote = index(argstr, "\"");
    const text = quote ? argstr[quote + 1..$] | false;
    let spec = $string_utils:trim(quote ? argstr[1..quote - 1] | argstr);
    const is_next = index("next", verb) == 1;
    const is_previous = index("previous", verb) == 1;
    if (is_next)
      spec = "+" + (spec || "1");
    elseif (is_previous)
      spec = "-" + (spec || "1");
    else
      spec = spec || ".";
    endif
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const insertion = this:parse_insert(who, spec);
    if (typeof(insertion) == TYPE_ERR)
      if (is_next || is_previous)
        player:tell("Argument must be a number.");
      else
        player:tell("You must specify an integer or `$' for the last line.");
      endif
      return;
    endif
    const end = length(this.texts[who]) + 1;
    if (insertion < 1 || insertion > end)
      player:tell("That would take you out of range (to line ", insertion, "?).");
      return;
    endif
    this.inserting[who] = insertion;
    if (typeof(text) == TYPE_STR)
      this:insert_line(who, text);
      return;
    endif
    if (!is_next)
      insertion > 1 ? this:list_line(who, insertion - 1) | player:tell("____");
    endif
    if (!is_previous)
      insertion < end ? this:list_line(who, insertion) | player:tell("^^^^");
    endif
  endverb

  verb "del*ete" (any any any) owner: #96 flags: "rd"
    "Delete a range, defaulting to the preceding line, and place the cursor at its start.";
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const range = this:parse_range(who, {"_", "1"}, @args);
    typeof(range) != TYPE_LIST && return player:tell(range);
    range[3] && return player:tell("Junk at end of cmd:  ", range[3]);
    const {first, last} = range[1..2];
    const text = this.texts[who];
    player:tell_lines(text[first..last]);
    player:tell("---Line", last > first ? "s" | "", " deleted.  Insertion point is before line ", first, ".");
    this.texts[who] = {@text[1..first - 1], @text[last + 1..$]};
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    this.inserting[who] = first;
  endverb

  verb "f*ind" (any any any) owner: #96 flags: "rxd"
    "Find literal text from the cursor or a specified line; c ignores case. Advance past a match.";
    "Accept command dispatch or the editor's shorthand hook, not external method calls.";
    valid(caller_perms()) && caller != this && return E_PERM;
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const parsed = this:parse_subst(argstr && argstr[1] + argstr, "c", "Empty search string?");
    typeof(parsed) != TYPE_LIST && return player:tell(tostr(parsed));
    const {delimiter_text, search, flags, start_spec} = parsed;
    let line = start_spec ? this:parse_insert(who, start_spec) | this.inserting[who];
    if (typeof(line) == TYPE_ERR)
      player:tell("Starting from where?", start_spec ? "  (can't parse " + start_spec + ")" | "");
      return;
    endif
    line < 1 && return player:tell("Starting line (", line, ") out of range.");
    const case_matters = !index(flags, "c", true);
    const text = this.texts[who];
    while (line <= length(text) && !index(text[line], search, case_matters))
      line = line + 1;
    endwhile
    line > length(text) && return player:tell("`", search, "' not found.");
    this.inserting[who] = line + 1;
    this:list_line(who, line);
  endverb

  verb "m*ove c*opy" (any any any) owner: #96 flags: "rd"
    "Move or copy a range to an insertion point, preserving the cursor's relation to the lines.";
    "Reject moves into their source range. Update text, cursor, and change flags without suspension.";
    const is_move = verb[1] == "m";
    const action = is_move ? "move" | "copy";
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    let to_position = 0;
    for position in [1..length(args)]
      args[position] == "to" && (to_position = position);
    endfor
    !to_position && return player:tell(action, " to where? ");
    const destination_args = args[to_position + 1..$];
    const destination = this:parse_insert(who, $string_utils:from_list(destination_args, " "));
    typeof(destination) == TYPE_ERR && return player:tell(action, " to where? ");
    const text = this.texts[who];
    const line_count = length(text);
    if (destination < 1 || destination > line_count + 1)
      player:tell("Destination (", destination, ") out of range.");
      return;
    endif
    const range_args = args[1..to_position - 1];
    if ("from" in range_args || "to" in range_args)
      player:tell("Don't use that kind of range specification with this command.");
      return;
    endif
    const range = this:parse_range(who, {"_", "^"}, @range_args);
    typeof(range) != TYPE_LIST && return player:tell(range);
    range[3] && return player:tell("Junk before `to':  ", range[3]);
    const {first, last} = range[1..2];
    if (is_move && destination >= first && destination <= last + 1)
      player:tell("Destination lies inside range of lines to be moved.");
      return;
    endif
    let insertion = this.inserting[who];
    const count = last - first + 1;
    if (!is_move)
      this.texts[who] = {@text[1..destination - 1], @text[first..last], @text[destination..$]};
      insertion >= destination && (insertion = insertion + count);
    elseif (destination < first)
      this.texts[who] = {@text[1..destination - 1], @text[first..last], @text[destination..first - 1], @text[last + 1..$]};
      if (insertion >= destination && insertion <= last)
        insertion = insertion > first ? insertion - first + destination | insertion + count;
      endif
    else
      this.texts[who] = {@text[1..first - 1], @text[last + 1..destination - 1], @text[first..last], @text[destination..$]};
      if (insertion > first && insertion < destination)
        insertion = insertion <= last ? insertion + destination - last - 1 | insertion - count;
      endif
    endif
    this.inserting[who] = insertion;
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    player:tell("Lines ", is_move ? "moved." | "copied.");
  endverb

  verb "join*literal" (any any any) owner: #96 flags: "rd"
    "Join a range with sentence spacing, or literally when the command extends past join.";
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const range = this:parse_range(who, {"_-^", "_", "^"}, @args);
    typeof(range) != TYPE_LIST && return player:tell(range);
    range[3] && return player:tell("Junk at end of cmd:  ", range[3]);
    const result = this:join_lines(who, @range[1..2], length(verb) <= 4);
    if (!result)
      player:tell(result == 0 ? "Need at least two lines to join." | result);
      return;
    endif
    this:list_line(who, range[1]);
  endverb

  verb fill (any any any) owner: #96 flags: "rd"
    "Usage: fill [range] [@ column]. Explicitly reflow selected text at the chosen width.";
    let range;
    let text;
    let from;
    let nlen;
    let fill_column = 70;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
    else
      range = this:parse_range(who, {"_", "1"}, @args);
      if (typeof(range) != TYPE_LIST)
        player:tell(range);
      else
        if (range[3] && range[3][1] == "@")
          fill_column = toint(range[3][2..$]);
        endif
        if (range[3] && (range[3][1] != "@" || fill_column < 10))
          player:tell("Usage:  fill [<range>] [@ column]   (where column >= 10).");
        else
          const join = this:join_lines(who, @range[1..2], 1);
          const newlines = this:fill_string((text = this.texts[who])[from = range[1]], fill_column);
          const fill = (nlen = length(newlines)) > 1 || newlines[1] != text[from];
          if (fill)
            this.texts[who] = {@text[1..from - 1], @newlines, @text[from + 1..$]};
            const insert = this.inserting[who];
            if (insert > from && nlen > 1)
              this.inserting[who] = insert + nlen - 1;
            endif
          endif
          if (fill || join)
            for line in [from..from + nlen - 1]
              this:list_line(who, line);
            endfor
          else
            player:tell("No changes.");
          endif
        endif
      endif
    endif
  endverb

  verb "pub*lish perish unpub*lish depub*lish" (none none none) owner: #96 flags: "rd"
    "Publish or protect the current buffer; preserve publication errors without changing the text.";
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const published = this:set_readable(who, index("publish", verb) == 1);
    typeof(published) == TYPE_ERR && return player:tell(published);
    player:tell(published ? "Your text is now globally readable." | "Your text is read protected.");
  endverb

  verb "w*hat" (none none none) owner: #96 flags: "rxd"
    "Show the player's current editing target and text visibility.";
    const who = player in this.active;
    if (!(this:ok(who) && typeof(this.texts[who]) == TYPE_LIST))
      player:tell(this:nothing_loaded_msg());
    else
      player:tell("You are editing ", this:working_on(who), ".");
      player:tell("Your insertion point is ", this.inserting[who] > length(this.texts[who]) ? "after the last line: next line will be #" | "before line ", this.inserting[who], ".");
      player:tell(this.changes[who] ? this:change_msg() | this:no_change_msg());
      if (this.readable[who])
        player:tell("Your text is globally readable.");
      endif
    endif
  endverb

  verb abort (none none none) owner: #96 flags: "rd"
    "Discard the current session's buffer and leave when exit_on_abort is enabled.";
    const who = player in this.active;
    !who && return player:tell(this:nothing_loaded_msg());
    if (this.changes[who])
      player:tell("Throwing away session for ", this:working_on(who), ".");
    else
      player:tell("No changes to throw away.  Editor cleared.");
    endif
    this:reset_session(who);
    this.exit_on_abort && this:done();
  endverb

  verb "done q*uit pause" (none none none) owner: #96 flags: "rxd"
    "Return to the saved room; retain or discard the buffer through the editor's exit hook.";
    !(caller in {this, player}) && return E_PERM;
    const who = player in this.active;
    !who && return player:tell("You are not actually in ", this.name, ".");
    const origin = this.original[who];
    if (!valid(origin))
      player:tell("I don't know where you came here from.");
      return player:tell("You'll have to use 'home' or a teleporter.");
    endif
    player:moveto(origin);
    if (player.location == this)
      player:tell("Hmmm... the place you came from doesn't want you back.");
      return player:tell("You'll have to use 'home' or a teleporter.");
    endif
    const message = this:return_msg();
    message && player.location:announce($string_utils:pronoun_sub(message));
  endverb

  method huh2 owner: #2
    "Handle s/pattern/replacement/ and /search/ shorthand using the existing command tokenization.";
    set_task_perms(caller_perms());
    const stack = callers();
    if (stack && (stack[1][1] != this || length(stack) > 1))
      return pass(@args);
    endif
    const {command, words} = args;
    let prefix_end = 1;
    const prefix_limit = min(length(command), 5);
    while (prefix_end <= prefix_limit && command[prefix_end] == "subst"[prefix_end])
      prefix_end = prefix_end + 1;
    endwhile
    const tail = $code_utils:argstr(command, words);
    if (prefix_end > 1 && prefix_end <= length(command))
      const delimiter = command[prefix_end];
      if (delimiter < "A" || delimiter > "Z")
        argstr = command[prefix_end..$] + (tail ? " " + tail | "");
        return this:subst();
      endif
    endif
    if (command && command[1] == "/")
      argstr = command + (tail ? " " + tail | "");
      return this:find();
    endif
    return pass(@args);
  endmethod

  method insertion owner: #96
    "Return the session's insertion point, or its access error.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    return this.inserting[who];
  endmethod

  method set_insertion owner: #96
    "Store a positive insertion point, clamped to the buffer end; return it or an access/input error.";
    const {who, value} = args;
    const access = this:ok(who);
    !access && return access;
    const position = toint(value);
    position < 1 && return E_INVARG;
    const insertion = min(position, length(this.texts[who]) + 1);
    this.inserting[who] = insertion;
    return insertion;
  endmethod

  method "changed retain_session_on_exit" owner: #96
    "Return the session's changed flag, or its access error.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    return this.changes[who];
  endmethod

  method set_changed owner: #96
    "Store and return a changed flag; setting it also records the time. Return access errors unchanged.";
    const {who, value} = args;
    const access = this:ok(who);
    !access && return access;
    const changed = !!value;
    changed && (this.times[who] = time());
    this.changes[who] = changed;
    return changed;
  endmethod

  method origin owner: #96
    "Return the room saved for the session's return, or its access error.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    return this.original[who];
  endmethod

  method set_origin owner: #96
    "Store and return a valid destination or $nothing; reject this editor and other invalid objects.";
    const {who, origin} = args;
    const access = this:ok(who);
    !access && return access;
    origin != $nothing && (!valid(origin) || origin == this) && return E_INVARG;
    this.original[who] = origin;
    return origin;
  endmethod

  method readable owner: #96
    "Return the public readability flag, or E_RANGE for an absent session.";
    const {who} = args;
    who < 1 || who > length(this.active) && return E_RANGE;
    return this.readable[who];
  endmethod

  method set_readable owner: #96
    "Store and return a boolean readability flag, or the session's access error.";
    const {who, value} = args;
    const access = this:ok(who);
    !access && return access;
    const readable = !!value;
    this.readable[who] = readable;
    return readable;
  endmethod

  method text owner: #96
    "Return published text or authorized private text; preserve E_RANGE and E_PERM on denial.";
    const {?who = player in this.active} = args;
    if (!this:readable(who))
      const access = this:ok(who);
      !access && return access;
    endif
    return this.texts[who];
  endmethod

  method load owner: #96
    "Load a string or text list; reset insertion, changed, readability, and time after access checks.";
    let {who, texts} = args;
    const access = this:ok(who);
    !access && return access;
    if (typeof(texts) == TYPE_STR)
      texts = {texts};
    elseif (typeof(texts) != TYPE_LIST || (texts && typeof(texts[1]) != TYPE_STR))
      return E_TYPE;
    endif
    this:_renew_input_version(who);
    this.texts[who] = texts;
    this.inserting[who] = length(texts) + 1;
    this.changes[who] = false;
    this.readable[who] = false;
    this.times[who] = time();
  endmethod

  method working_on owner: #96
    "Return a generic description for authorized sessions; child editors supply their own wording.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    return "something [in " + this.name + "]";
  endmethod

  method ok owner: #96
    "Authorize the calling editor operation; return true, E_RANGE, or E_PERM.";
    const {who} = args;
    who < 1 || who > length(this.active) && return E_RANGE;
    const stack = callers();
    if (length(stack) < 2)
      return player == this.active[who] ? true | E_PERM;
    endif
    const operation = stack[2];
    operation[1] == this && return true;
    $perm_utils:controls(operation[3], this.active[who]) && return true;
    operation[3] == $generic_editor.owner && return true;
    return E_PERM;
  endmethod

  method loaded owner: #96
    "Return the player's session index when text is loaded, otherwise zero.";
    const {who} = args;
    const session = who in this.active;
    !session && return 0;
    return typeof(this.texts[session]) == TYPE_LIST ? session | 0;
  endmethod

  method list_line owner: #96
    "Display one authorized line with its insertion marker; ignore denied requests.";
    const {who, line} = args;
    !this:ok(who) && return;
    const insertion = this.inserting[who];
    const marker = 1 + (line in {insertion - 1, insertion});
    player:tell($string_utils:right(line, 3, " _^"[marker]), ":_^"[marker], " ", this.texts[who][line]);
  endmethod

  method insert_line owner: #96
    "Insert a string or line list at the cursor; accept an optional session and quiet flag.";
    "Return E_NONE for unloaded text, or the session's access error. The insertion commits with its flags.";
    if (typeof(args[1]) != TYPE_INT)
      args = {player in this.active, @args};
    endif
    let {who, lines, ?quiet} = args;
    const access = this:ok(who);
    !access && return access;
    const text = this.texts[who];
    typeof(text) != TYPE_LIST && return E_NONE;
    const editor_player = this.active[who];
    length(args) < 3 && (quiet = editor_player:edit_option("quiet_insert"));
    typeof(lines) != TYPE_LIST && (lines = {lines});
    const insertion = this.inserting[who];
    this.texts[who] = {@text[1..insertion - 1], @lines, @text[insertion..$]};
    this.inserting[who] = insertion + length(lines);
    if (!lines)
      editor_player:tell("No lines added.");
      return;
    endif
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    quiet && return;
    if (length(lines) == 1)
      editor_player:tell("Line ", insertion, " added.");
    else
      editor_player:tell("Lines ", insertion, "-", insertion + length(lines) - 1, " added.");
    endif
  endmethod

  method append_line owner: #96
    "Append to the preceding line, or insert at the buffer start; accept an optional session index.";
    "Return E_NONE for unloaded text, or the session's access error.";
    if (typeof(args[1]) != TYPE_INT)
      args = {player in this.active, @args};
    endif
    const {who, addition} = args;
    const access = this:ok(who);
    !access && return access;
    const line = this.inserting[who] - 1;
    line < 1 && return this:insert_line(who, {addition});
    const text = this.texts[who];
    typeof(text) != TYPE_LIST && return E_NONE;
    this.texts[who][line] = text[line] + addition;
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    const editor_player = this.active[who];
    !editor_player:edit_option("quiet_insert") && editor_player:tell("Appended to line ", line, ".");
  endmethod

  method join_lines owner: #96
    "Join a range literally or with sentence spacing; return the removed line count or access error.";
    const {who, first, last, english} = args;
    const access = this:ok(who);
    !access && return access;
    first >= last && return 0;
    const text = this.texts[who];
    let joined = "";
    for line in (text[first..last])
      if (!english)
        joined = joined + line;
        continue;
      endif
      let end = length(line);
      while (end > 0 && line[end] == " ")
        end = end - 1;
      endwhile
      if (end > 0)
        joined = joined + line + (index(".:", line[end]) ? "  " | " ");
      endif
    endfor
    this.texts[who] = {@text[1..first - 1], joined, @text[last + 1..$]};
    const insertion = this.inserting[who];
    if (insertion > first)
      this.inserting[who] = insertion <= last ? first + 1 | insertion - last + first;
    endif
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    return last - first;
  endmethod

  method parse_number owner: #96
    "Return a line number or zero for invalid text; preserve the editor session's access error.";
    const {who, text, before} = args;
    const access = this:ok(who);
    !access && return access;
    !text && return 0;
    const insertion = this.inserting[who];
    text == "." && return insertion - (before ? 1 | 0);
    const size = length(text);
    const suffix = index("_^$", text[size]);
    !suffix && return toint(text);
    const last = length(this.texts[who]);
    const start = {insertion, insertion - 1, last + 1}[suffix];
    const distance = size == 1 ? 1 | toint(text[1..size - 1]);
    !distance && return 0;
    return suffix == 2 ? start + distance | start - distance;
  endmethod

  method parse_range owner: #96
    "Return {first, last, unused text}, a diagnostic string, or the editor session's access error.";
    const {who, defaults, @words} = args;
    const access = this:ok(who);
    !access && return access;
    const last = length(this.texts[who]);
    !last && return this:no_text_msg();
    let first_line = 0;
    let last_line = 0;
    for candidate in (defaults)
      const range = this:parse_range(who, {}, candidate);
      if (typeof(range) == TYPE_LIST)
        first_line = range[1];
        last_line = range[2];
        break;
      endif
    endfor
    let named_range = false;
    let cursor = 1;
    const count = length(words);
    while (cursor <= count)
      const word = words[cursor];
      if (word == "from" || word == "to")
        cursor == count && return word + " ?";
        cursor = cursor + 1;
        const line = this:parse_number(who, words[cursor], word == "to");
        !line && return word + " ?";
        if (word == "from")
          first_line = line;
        else
          last_line = line;
        endif
        named_range = true;
        cursor = cursor + 1;
        continue;
      endif
      if (named_range)
        break;
      endif
      const separator = index(word, "-");
      if (separator)
        first_line = this:parse_number(who, word[1..separator - 1], false);
        last_line = this:parse_number(who, word[separator + 1..$], true);
        cursor = cursor + 1;
        break;
      endif
      const line = this:parse_number(who, word, false);
      if (!line)
        break;
      endif
      first_line = line;
      last_line = line;
      cursor = cursor + 1;
      if (cursor <= count)
        const end_line = this:parse_number(who, words[cursor], true);
        if (end_line)
          last_line = end_line;
          cursor = cursor + 1;
        endif
      endif
      break;
    endwhile
    first_line < 1 && return tostr("from ", first_line, "?  (out of range)");
    last_line > last && return tostr("to ", last_line, "?  (out of range)");
    first_line > last_line && return tostr("from ", first_line, " to ", last_line, "?  (backwards range)");
    return {first_line, last_line, $string_utils:from_list(words[cursor..count], " ")};
  endmethod

  method parse_insert owner: #96
    "Return the line after an insertion point, E_INVARG for invalid text, or a session access error.";
    const {who, text} = args;
    const access = this:ok(who);
    !access && return access;
    !text && return E_INVARG;
    const insertion = this.inserting[who];
    if (text[1] == "-" || text[1] == "+")
      const amount_text = text[2..$];
      const amount = toint(amount_text);
      !amount && amount_text != "0" && return E_INVARG;
      return text[1] == "-" ? insertion - amount | insertion + amount;
    endif
    const marker = index(text, "^") || index(text, "_");
    let offset = 0;
    if (marker)
      offset = marker == 1 ? 1 | toint(text[1..marker - 1]);
      !offset && return E_INVARG;
      text[marker] == "^" && (offset = -offset);
    endif
    const line_text = text[marker + 1..$];
    line_text == "." && return offset + insertion;
    line_text == "$" && return offset + length(this.texts[who]) + 1;
    const line = toint(line_text);
    !line && return E_INVARG;
    const above = marker && text[marker] == "^";
    return offset + (above ? 1 | 0) + line;
  endmethod

  method parse_subst owner: #96
    "Return {old text, new text, flags, range text}, or a diagnostic for missing or empty input.";
    let {command, ?recognized_flags = "gcr", ?null_subst_msg = "Null substitution?"} = args;
    !command && return "s*ubst/<str1>/<str2>[/[g][c][r][<range>]] expected...";
    const delimiter = command[1];
    command = command[2..$];
    let separator = index(command + delimiter, delimiter, 1);
    const old_text = command[1..separator - 1];
    command = command[separator + 1..$];
    separator = index(command + delimiter, delimiter, 1);
    const new_text = command[1..separator - 1];
    command = command[separator + 1..$];
    !old_text && !new_text && return null_subst_msg;
    let cursor = 1;
    while (cursor <= length(command) && index(recognized_flags, command[cursor]))
      cursor = cursor + 1;
    endwhile
    return {old_text, new_text, command[1..cursor - 1], command[cursor..$]};
  endmethod

  method invoke owner: #96
    ":invoke(...)";
    "to find out what arguments this verb expects,";
    "see this editor's parse_invoke verb.";
    let msg;
    let info;
    const new = args[1];
    if (!(caller in {this, player}) && !$perm_utils:controls(caller_perms(), player))
      "...non-editor/non-player verb trying to send someone to the editor...";
      return E_PERM;
    endif
    const who = this:loaded(player);
    if (who && this:changed(who))
      if (!new)
        if (this:suck_in(player))
          player:tell("You are working on ", this:working_on(who));
        endif
        return;
      endif
      if (player.location == this)
        player:tell("You are still working on ", this:working_on(who));
        msg = this:previous_session_msg();
        if (msg)
          player:tell(msg);
        endif
        return;
      endif
      "... we're not in the editor and we're about to start something new,";
      "... but there's still this pending session...";
      player:tell("You were working on ", this:working_on(who));
      if (!$command_utils:yes_or_no("Do you wish to delete that session?"))
        if (this:suck_in(player))
          player:tell("Continuing with ", this:working_on(player in this.active));
          msg = this:previous_session_msg();
          if (msg)
            player:tell(msg);
          endif
        endif
        return;
      endif
      "... note session number may have changed => don't trust `who'";
      this:kill_session(player in this.active);
    endif
    const spec = this:parse_invoke(@args);
    if (typeof(spec) == TYPE_LIST)
      info = player:edit_option("local") && $object_utils:has_verb(this, "local_editing_info") ? this:local_editing_info(@spec) | {};
      if (info)
        this:invoke_local_editor(@info);
      elseif (this:suck_in(player))
        this:init_session(player in this.active, @spec);
      endif
    endif
  endmethod

  method suck_in owner: #96
    "The correct way to move someone into the editor.";
    let who_obj;
    let msg;
    const loc = (who_obj = args[1]).location;
    if (loc != this && caller == this)
      this.invoke_task = task_id();
      who_obj:moveto(this);
      if (who_obj.location == this)
        try
          "...forked, just in case loc:announce is broken...";
          "changed to a try-endtry. Lets reduce tasks..Ho_Yan 12/20/96";
          msg = valid(loc) ? this:depart_msg() | "";
          if (msg)
            loc:announce($string_utils:pronoun_sub(msg));
          endif
        except (ANY)
          "Just drop it and move on";
        endtry
      else
        who_obj:tell("For some reason, I can't move you.   (?)");
        this:exitfunc(who_obj);
      endif
      this.invoke_task = 0;
    endif
    return who_obj.location == this;
  endmethod

  method new_session owner: #2
    "Create a session or retain an existing one, preserving a return room outside editors.";
    caller != this && return E_PERM;
    let {who_obj, from} = args;
    if ($object_utils:isa(from, $generic_editor))
      const previous = who_obj in from.active;
      from = previous ? from.original[previous] | $nothing;
    endif
    const who = who_obj in this.active;
    if (who)
      valid(from) && (this.original[who] = from);
      return -1;
    endif
    for state in ({{"active", who_obj}, {"original", valid(from) ? from | $nothing}, {"times", time()}, @this.stateprops})
      this.(state[1]) = {@this.(state[1]), state[2]};
    endfor
    const created = length(this.active);
    this:_renew_input_version(created);
    return created;
  endmethod

  method kill_session owner: #2
    "Remove an authorized session and its pending-input identity; other players keep theirs.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    const editor_player = this.active[who];
    for state in ({@this.stateprops, {"original"}, {"active"}, {"times"}})
      this.(state[1]) = listdelete(this.(state[1]), who);
    endfor
    if (maphaskey(this.input_versions, editor_player))
      this.input_versions = mapdelete(this.input_versions, editor_player);
    endif
    return who;
  endmethod

  method reset_session owner: #2
    "Clear an authorized buffer and invalidate pending input while retaining its return room.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    for state in (this.stateprops)
      this.(state[1])[who] = state[2];
    endfor
    this.times[who] = time();
    this:_renew_input_version(who);
    return who;
  endmethod

  method kill_all_sessions owner: #2
    "WIZARDLY";
    let who;
    let origin;
    caller != this && !caller_perms().wizard && return E_PERM;
    for victim in (this.contents)
      victim:tell("Sorry, ", this.name, " is going down.  Your editing session is hosed.");
      victim:moveto((who = victim in this.active) && valid(origin = this.original[who]) ? origin | valid(victim.home) ? victim.home | $player_start);
    endfor
    for p in ({@this.stateprops, {"original"}, {"active"}, {"times"}})
      this.(p[1]) = {};
    endfor
    this.input_versions = [];
    return 1;
  endmethod

  method acceptable owner: #96
    "Accept permitted players, including wizards, into the editor.";
    let who_obj;
    return is_player(who_obj = args[1]) && (who_obj.wizard || pass(@args));
  endmethod

  method enterfunc owner: #96
    "Establish an authorized editor session and show arrival information.";
    let who;
    let msg;
    const who_obj = args[1];
    if (who_obj.wizard && !(who_obj in this.active))
      this:accept(who_obj);
    endif
    pass(@args);
    if (this.invoke_task == task_id())
      "Means we're about to load something, so be quiet.";
      this.invoke_task = 0;
    else
      who = this:loaded(who_obj);
      if (who)
        who_obj:tell("You are working on ", this:working_on(who), ".");
      else
        msg = this:nothing_loaded_msg();
        if (msg)
          who_obj:tell(msg);
        endif
      endif
    endif
  endmethod

  method exitfunc owner: #96
    "Retain or discard a departing player's session according to editor policy.";
    let who_obj;
    const who = (who_obj = args[1]) in this.active;
    if (!who)
    elseif (this:retain_session_on_exit(who))
      const msg = this:no_littering_msg();
      if (msg)
        who_obj:tell_lines(msg);
      endif
    else
      this:kill_session(who);
    endif
    pass(@args);
  endmethod

  verb "@flush" (this any any) owner: #96 flags: "rxd"
    "@flush <editor>";
    "@flush <editor> at <month> <day>";
    "@flush <editor> at <weekday>";
    "The first form removes all sessions from the editor; the other two forms remove everything older than the given date.";
    if (caller_perms() != #-1 && caller_perms() != player)
      raise(E_PERM);
    elseif (!$perm_utils:controls(player, this))
      player:tell("Only the owner of the editor can do a ", verb, ".");
      return;
    endif
    if (!prepstr)
      player:tell("Trashing all sessions.");
      this:kill_all_sessions();
    elseif (prepstr != "at")
      player:tell("Usage:  ", verb, " ", dobjstr, " [at [mon day|weekday]]");
    else
      const p = prepstr in args;
      let t = $time_utils:from_day(iobjstr, -1);
      if (t)
      else
        t = $time_utils:from_month(args[p + 1], -1);
        if (t)
          if (length(args) > p + 1)
            const n = toint(args[p + 2]);
            if (!n)
              player:tell(args[p + 1], " WHAT?");
              return;
            endif
            t = t + (n - 1) * 86400;
          endif
        else
          player:tell("couldn't parse date");
          return;
        endif
      endif
      this:do_flush(t, "noisy");
    endif
    player:tell("Done.");
  endverb

  verb "@stateprop" (any for this) owner: #96 flags: "rd"
    "Usage: @stateprop name=value for editor. Add a state property when the player controls this editor.";
    let default;
    let prop;
    if (!$perm_utils:controls(player, this))
      player:tell(E_PERM);
      return;
    endif
    const i = index(dobjstr, "=");
    if (i)
      default = dobjstr[i + 1..$];
      prop = dobjstr[1..i - 1];
      if (argstr[1 + index(argstr, "=")] == "\"")
      elseif (default[1] == "#")
        default = toobj(default);
      elseif (index("0123456789", default[1]))
        default = toint(default);
      elseif (default == "{}")
        default = {};
      endif
    else
      default = 0;
      prop = dobjstr;
    endif
    const result = this:set_stateprops(prop, default);
    if (typeof(result) == TYPE_ERR)
      player:tell(result == E_RANGE ? tostr(".", prop, " needs to hold a list of the same length as .active (", length(this.active), ").") | result != E_NACC ? result | prop + " is already a property on an ancestral editor.");
    else
      player:tell("Property added.");
    endif
  endverb

  verb "@rmstateprop" (any from this) owner: #96 flags: "rd"
    "Usage: @rmstateprop name from editor. Remove a state property when the player controls this editor.";
    let result;
    if (!$perm_utils:controls(player, this))
      player:tell(E_PERM);
    else
      result = this:set_stateprops(dobjstr);
      if (typeof(result) == TYPE_ERR)
        player:tell(result != E_NACC ? result | dobjstr + " is already a property on an ancestral editor.");
      else
        player:tell("Property removed.");
      endif
    endif
  endverb

  method initialize owner: #96
    "Initialize an owned editor and discard its inherited sessions.";
    if ($perm_utils:controls(caller_perms(), this))
      pass(@args);
      this:kill_all_sessions();
    endif
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this:kill_all_sessions();
      if (this == $generic_editor)
        this.help = $editor_help;
      endif
      if ($object_utils:defines_verb(this, "is_not_banned"))
        delete_verb(this, "is_not_banned");
      endif
    endif
  endmethod

  method set_stateprops owner: #96
    "Add or remove a session state property; require editor control or an internal call.";
    let prop;
    let i;
    const remove = length(args) < 2;
    caller != this && !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    !(length(args) in {1, 2}) && return E_ARGS;
    prop = args[1];
    typeof(prop) != TYPE_STR && return E_TYPE;
    i = $list_utils:iassoc(prop, this.stateprops);
    if (i)
      if (!remove)
        this.stateprops[i] = {prop, args[2]};
      elseif ($object_utils:has_property(parent(this), prop))
        return E_NACC;
      else
        this.stateprops = listdelete(this.stateprops, i);
      endif
    elseif (remove)
    elseif (prop in `properties(this) ! ANY => {}')
      this:_stateprop_length(prop) != length(this.active) && return E_RANGE;
      this.stateprops = {{prop, args[2]}, @this.stateprops};
    else
      return $object_utils:has_property(this, prop) ? E_NACC | E_PROPNF;
    endif
    return 0;
  endmethod

  method description owner: #96
    "Return editor command help appropriate to an arrival or an explicit look.";
    let cmdargs;
    let is_look_self = 1;
    for c in (callers())
      if (is_look_self && c[2] in {"enterfunc", "confunc"})
        return {"", "Do a 'look' to get the list of commands, or 'help' for assistance.", "", @this.description};
      endif
      if (c[2] != "look_self" && c[2] != "pass")
        is_look_self = 0;
      endif
    endfor
    let d = {"Commands:", ""};
    let col = {{}, {}};
    for c in [1..2]
      for cmd in (this.commands2[c])
        cmd = this:commands_info(cmd);
        col[c] = {cmdargs = $string_utils:left(cmd[1] + " ", 12) + cmd[2], @col[c]};
      endfor
    endfor
    let i1 = length(col[1]);
    let i2 = length(col[2]);
    let right = 0;
    while (i1 || i2)
      if (!(i1 && length(col[1][i1]) > 35 || (i2 && length(col[2][i2]) > 35)))
        d = {@d, $string_utils:left(i1 ? col[1][i1] | "", 40) + (i2 ? col[2][i2] | "")};
        i1 && (i1 = i1 - 1);
        i2 && (i2 = i2 - 1);
        right = 0;
      elseif (right && i2)
        d = {@d, length(col[2][i2]) > 35 ? $string_utils:right(col[2][i2], 75) | $string_utils:space(40) + col[2][i2]};
        i2 = i2 - 1;
        right = 0;
      elseif (i1)
        d = {@d, col[1][i1]};
        i1 = i1 - 1;
        right = 1;
      else
        right = 1;
      endif
    endwhile
    return {@d, "", "----  Do `help <cmdname>' for help with a given command.  ----", "", "  <ins> ::= $ (the end) | [^]n (above line n) | _n (below line n) | . (current)", "<range> ::= <lin> | <lin>-<lin> | from <lin> | to <lin> | from <lin> to <lin>", "  <lin> ::= n | [n]$ (n from the end) | [n]_ (n before .) | [n]^ (n after .)", "`help insert' and `help ranges' describe these in detail.", @this.description};
  endmethod

  method commands_info owner: #96
    "Return command help from this editor or its parent.";
    const cmd = args[1];
    const pc = $list_utils:assoc(cmd, this.commands);
    pc && return pc;
    this == $generic_editor && return {cmd, "<<<<<======= Need to add this to .commands"};
    return parent(this):commands_info(cmd);
  endmethod

  method match_object owner: #96
    "Resolve an object from the player's saved pre-editor location.";
    let objstr;
    let who;
    {objstr, ?who = player} = args;
    let origin = this;
    while (true)
      const where = player in origin.active;
      if (where)
        origin = origin.original[where];
      endif
      if (!where || !$recycler:valid(origin) || origin == this)
        break;
      endif
      !$object_utils:isa(origin, $generic_editor) && return origin:match_object(objstr, who);
    endwhile
    return who:my_match_object(objstr, #-1);
  endmethod

  method who_location_msg owner: #96
    "Describe the player's saved location while editing.";
    const who = args[1];
    const where = {#-1, @this.original}[1 + (who in this.active)];
    let wherestr = `where:who_location_msg(who) ! ANY => "An Editor"';
    if (typeof(wherestr) != TYPE_STR)
      wherestr = "broken who_location_msg";
    endif
    return strsub(this.who_location_msg, "%L", wherestr);
    return $string_utils:pronoun_sub(this.who_location_msg, who, this, where);
  endmethod

  method "nothing_loaded_msg no_text_msg change_msg no_change_msg no_littering_msg depart_msg return_msg previous_session_msg" owner: #96
    "Return the player's customized editor message, or this editor's default.";
    return $code_utils:verb_or_property(player, verb, this) || this.(verb);
  endmethod

  method "announce announce_all announce_all_but tell_contents" owner: #96
    "Suppress room broadcasts inside the shared editor.";
    return;
  endmethod

  method fill_string owner: #96
    "Explicit text editing: split a string at word boundaries, with a default width of 80.";
    "tries to cut <string> into substrings of length < <width> along word boundaries.  Prefix, if supplied, will be prefixed to the 2nd..last substrings.";
    let last;
    let next;
    let {string, ?width = 80, ?prefix = ""} = args;
    width = width + 1;
    width < 3 + length(prefix) && return E_INVARG;
    string = "$" + string + " $";
    let len = length(string);
    if (len <= width)
      last = len - 1;
      next = len;
    else
      last = rindex(string[1..width], " ");
      if (last < (width + 1) / 2)
        last = width + index(string[width + 1..len], " ");
      endif
      next = last;
      while (true)
        next = next + 1;
        if (!(string[next] == " "))
          break;
        endif
      endwhile
    endif
    while (true)
      last = last - 1;
      if (!(string[last] == " "))
        break;
      endif
    endwhile
    let ret = {string[2..last]};
    width = width - length(prefix);
    const minlast = (width + 1) / 2;
    while (next < len)
      string = "$" + string[next..len];
      len = len - next + 2;
      if (len <= width)
        last = len - 1;
        next = len;
      else
        last = rindex(string[1..width], " ");
        if (last < minlast)
          last = width + index(string[width + 1..len], " ");
        endif
        next = last;
        while (true)
          next = next + 1;
          if (!(string[next] == " "))
            break;
          endif
        endwhile
      endif
      while (true)
        last = last - 1;
        if (!(string[last] == " "))
          break;
        endif
      endwhile
      if (last > 1)
        ret = {@ret, prefix + string[2..last]};
      endif
    endwhile
    return ret;
  endmethod

  method here_huh owner: #96
    "Handle s/pattern/replacement/ and /search/ shorthand using the existing command tokenization.";
    caller != this && caller_perms() != player && return E_PERM;
    const {command, words} = args;
    let prefix_end = 1;
    const prefix_limit = min(length(command), 5);
    while (prefix_end <= prefix_limit && command[prefix_end] == "subst"[prefix_end])
      prefix_end = prefix_end + 1;
    endwhile
    const tail = $code_utils:argstr(command, words);
    if (prefix_end > 1 && prefix_end <= length(command))
      const delimiter = command[prefix_end];
      if (delimiter < "A" || delimiter > "Z")
        argstr = command[prefix_end..$] + (tail ? " " + tail | "");
        this:subst();
        return true;
      endif
    endif
    if (command && command[1] == "/")
      argstr = command + (tail ? " " + tail | "");
      this:find();
      return true;
    endif
    return false;
  endmethod

  method match owner: #2
    "Exclude the shared editor's contents from ordinary object matching.";
    return $failed_match;
  endmethod

  method get_room owner: #96
    ":get_room([player])  => correct room to match in on invocation.";
    let who;
    {?who = player} = args;
    who.location != this && return who.location;
    let origin = this;
    while (true)
      const where = player in origin.active;
      if (where)
        origin = origin.original[where];
      endif
      if (!where || !valid(origin) || origin == this)
        break;
      endif
      !$object_utils:isa(origin, $generic_editor) && return origin;
    endwhile
    return this;
  endmethod

  method invoke_local_editor owner: #2
    ":invoke_local_editor(name, text, upload)";
    "Spits out the magic text that invokes the local editor in the player's client.";
    "NAME is a good human-readable name for the local editor to use for this particular piece of text.";
    "TEXT is a string or list of strings, the initial body of the text being edited.";
    "UPLOAD, a string, is a MOO command that the local editor can use to save the text when the user is done editing.  The local editor is going to send that command on a line by itself, followed by the new text lines, followed by a line containing only `.'.  The UPLOAD command should therefore call $command_utils:read_lines() to get the new text as a list of strings.";
    caller != this && return;
    let {name, text, upload} = args;
    if (typeof(text) == TYPE_STR)
      text = {text};
    endif
    notify(player, tostr("#$# edit name: ", name, " upload: ", upload));
    ":dump_lines() takes care of the final `.' ...";
    for line in ($command_utils:dump_lines(text))
      notify(player, line);
    endfor
  endmethod

  method _stateprop_length owner: #2
    "+c properties on children cannot necessarily be read, so we need this silliness...";
    caller != this && return E_PERM;
    return length(this.(args[1]));
  endmethod

  verb print (none none none) owner: #2 flags: "rd"
    "Print the complete accessible buffer without line numbers, followed by a separator.";
    const text = this:text(player in this.active);
    if (typeof(text) == TYPE_LIST)
      player:tell_lines(text);
    else
      player:tell("Text unreadable:  ", text);
    endif
    player:tell("--------------------------");
  endverb

  method accept owner: #96
    "Create an editing session when this player is accepted.";
    let who_obj;
    return this:acceptable(who_obj = args[1]) && this:new_session(who_obj, who_obj.location);
  endmethod

  verb "y*ank" (any any any) owner: #2 flags: "rd"
    "Usage: yank from <note>";
    "       yank <message-sequence> from <mail-recipient>";
    "       yank from <object>:<verb>";
    "       yank from <object>.<property>";
    "Grabs the specified text and inserts it at the cursor.";
    let sequence;
    let folder;
    let lines;
    let pr;
    let o;
    set_task_perms(player);
    if (dobjstr)
      "yank <message-sequence> from <mail-recipient>";
      const p = player:parse_mailread_cmd(verb, args, "", "from");
      !p && return;
      sequence = p[2];
      if ($seq_utils:size(sequence) != 1)
        player:notify(tostr("You can only ", verb, " one message at a time"));
        return;
      else
        const m = (folder = p[1]):messages_in_seq(sequence);
        const msg = m[1];
        let header = tostr("Message ", msg[1]);
        if (folder != player)
          header = tostr(header, " on ", $mail_agent:name(folder));
        endif
        header = tostr(header, ":");
        lines = {header, @player:msg_full_text(@msg[2])};
        this:insert_line(this:loaded(player), lines, 0);
      endif
    else
      pr = $code_utils:parse_propref(iobjstr);
      if (pr)
        o = player:my_match_object(pr[1]);
        $command_utils:object_match_failed(o, pr[1]) && return;
        lines = `o.(pr[2]) ! ANY';
        if (lines == E_PROPNF)
          player:notify(tostr("There is no `", pr[2], "' property on ", $string_utils:nn(o), "."));
          return;
        elseif (lines == E_PERM)
          player:notify(tostr("Error: Permission denied reading ", iobjstr));
          return;
        elseif (typeof(lines) == TYPE_ERR)
          player:notify(tostr("Error: ", lines, " reading ", iobjstr));
          return;
        elseif (typeof(lines) == TYPE_STR)
          this:insert_line(this:loaded(player), lines, 0);
          return;
        elseif (typeof(lines) == TYPE_LIST)
          for x in (lines)
            if (typeof(x) != TYPE_STR)
              player:notify(tostr("Error: ", iobjstr, " does not contain a ", verb, "-able value."));
              return;
            endif
          endfor
          this:insert_line(this:loaded(player), lines, 0);
          return;
        else
          player:notify(tostr("Error: ", iobjstr, " does not contain a ", verb, "-able value."));
          return;
        endif
      else
        pr = $code_utils:parse_verbref(iobjstr);
        if (pr)
          o = player:my_match_object(pr[1]);
          $command_utils:object_match_failed(o, pr[1]) && return;
          lines = `verb_code(o, pr[2], !player:edit_option("no_parens")) ! ANY';
          if (lines)
            this:insert_line(this:loaded(player), lines, 0);
            return;
          elseif (lines == E_PERM)
            player:notify(tostr("Error: Permission denied reading ", iobjstr));
            return;
          elseif (lines == E_VERBNF)
            player:notify(tostr("There is no `", pr[2], "' verb on ", $string_utils:nn(o), "."));
          else
            player:notify(tostr("Error: ", lines, " reading ", iobjstr));
            return;
          endif
        else
          iobj = player:my_match_object(iobjstr);
          if ($command_utils:object_match_failed(iobj, iobjstr))
            return;
          else
            lines = `iobj:text() ! ANY';
            if (lines == E_PERM)
              player:notify(tostr("Error: Permission denied reading ", iobjstr));
              return;
            elseif (lines == E_VERBNF)
              player:notify(tostr($string_utils:nn(iobj), " doesn't seem to be a note."));
            elseif (typeof(lines) == TYPE_ERR)
              player:notify(tostr("Error: ", lines, " reading ", iobjstr));
              return;
            else
              this:insert_line(this:loaded(player), lines, 0);
            endif
          endif
        endif
      endif
    endif
  endverb

  method do_flush owner: #96
    "Flushes editor sessions older than args[1].  If args[2] is true, prints status as it runs.  If args[2] is false, runs silently.";
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const {t, noisy} = args;
    for i in [-length(this.active)..-1]
      if (this.times[-i] < t)
        if (noisy)
          player:tell($string_utils:nn(this.active[-i]), ctime(this.times[-i]));
        endif
        this:kill_session(-i);
      endif
    endfor
  endmethod

  verb "s*ubst" (any any any) owner: #96 flags: "rxd"
    "Replace text in a range; g replaces all matches, c ignores case, and r uses MOO regex syntax.";
    "Build replacement lines before changing the buffer. Accept dispatch or the editor's shorthand hook.";
    valid(caller_perms()) && caller != this && return E_PERM;
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    const parsed = this:parse_subst(argstr);
    typeof(parsed) != TYPE_LIST && return player:tell(tostr(parsed));
    const {pattern, replacement, flags, range_spec} = parsed;
    const range = this:parse_range(who, {"_", "1"}, @$string_utils:explode(range_spec));
    typeof(range) != TYPE_LIST && return player:tell(range);
    range[3] && return player:tell("Junk at end of cmd:  ", range[3]);
    const is_global = index(flags, "g", true) > 0;
    const regexp = index(flags, "r", true) > 0;
    const case_matters = !index(flags, "c", true);
    const {first, last} = range[1..2];
    const text = this.texts[who];
    let lines = {};
    let changed = {};
    for line in [first..last]
      const original = text[line];
      let rewritten = original;
      if (!pattern)
        rewritten = replacement + original;
      elseif (regexp)
        try
          const result = this:subst_regexp(original, pattern, replacement, case_matters, is_global);
          typeof(result) == TYPE_STR && (rewritten = result);
        except error (E_INVARG)
          player:tell("Invalid regular expression or replacement.");
          return;
        endtry
      elseif (is_global)
        rewritten = strsub(original, pattern, replacement, case_matters);
      else
        const position = index(original, pattern, case_matters);
        if (position)
          rewritten = original[1..position - 1] + replacement + original[position + length(pattern)..$];
        endif
      endif
      strcmp(original, rewritten) && (changed = {@changed, line});
      lines = {@lines, rewritten};
    endfor
    if (!changed)
      player:tell("No changes in line", first == last ? tostr(" ", first) | tostr("s ", first, "-", last), ".");
      return;
    endif
    this.texts[who] = {@text[1..first - 1], @lines, @text[last + 1..$]};
    if (!this.changes[who])
      this.changes[who] = true;
      this.times[who] = time();
    endif
    for line in (changed)
      this:list_line(who, line);
    endfor
  endverb

  method subst_regexp owner: #96
    "Replace the first or all MOO regex matches. Return a string, including empty, or {} for no match.";
    "Search the original text; skip one character after an empty match. Invalid input raises E_INVARG.";
    const {text, pattern, replacement, case_matters, ?is_global = false} = args;
    const case_flag = case_matters ? 1 | 0;
    let found = match(text, pattern, case_flag);
    !found && return {};
    let pieces = {};
    let copied = 1;
    while (found)
      const {first, last} = found[1..2];
      pieces = {@pieces, text[copied..first - 1], substitute(replacement, found)};
      copied = last + 1;
      if (!is_global)
        break;
      endif
      const next = max(last + 1, first + 1);
      if (next > length(text) + 1)
        break;
      endif
      found = match(text, pattern, case_flag, next);
    endwhile
    return tostr(@pieces, text[copied..$]);
  endmethod

  method include_for_core owner: #96
    "Include the generic editor's owner in an extracted core.";
    return this == $generic_editor ? {"owner"} | {};
  endmethod
endobject
