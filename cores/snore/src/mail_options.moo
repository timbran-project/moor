object MAIL_OPTIONS [
  import_export_id -> "mail_options"
]
  name: "Mail Options"
  parent: GENERIC_OPTIONS
  owner: HACKER
  readable: true

  property choices_rn_order (owner: HACKER, flags: "rc") = {
    {"read", {".current_message folders are sorted by last read date."}},
    {"send", {".current_message folders are sorted by last send date."}},
    {"fixed", {".current_message folders are not sorted."}}
  };
  property show_all (owner: HACKER, flags: "rc") = {
    "Replies will go to original sender only.",
    "Replies will go to original sender and all previous recipients."
  };
  property show_enter (owner: HACKER, flags: "rc") = {
    "Mail editor will not start with an implicit `enter' command.",
    "Mail editor will start with an implicit `enter' command."
  };
  property show_expert (owner: HACKER, flags: "rc") = {"Novice mail user...", "Expert mail user..."};
  property show_followup (owner: HACKER, flags: "rc") = {
    "No special reply action for messages with non-player recipients.",
    "Replies go only to first non-player recipient if any."
  };
  property show_include (owner: HACKER, flags: "rc") = {
    "Original message will not be included in replies",
    "Original message will be included in replies"
  };
  property show_no_dupcc (owner: HACKER, flags: "r") = {
    "i want to read mail to me also sent to lists i read",
    "don't send me personal copies of mail also sent to lists i read"
  };
  property show_no_unsend (owner: #2, flags: "r") = {
    "People may @unsend unread messages they send to me",
    "No one may @unsend messages they sent to me"
  };
  property show_nosubject (owner: HACKER, flags: "rc") = {
    "Mail editor will initially require a subject line.",
    "Mail editor will not initially require a subject line."
  };
  property show_resend_forw (owner: HACKER, flags: "rc") = {
    "@resend puts player in Resent-By: header",
    "@resend puts player in From: header (like @forward)"
  };
  property "type_@mail" (owner: HACKER, flags: "rc") = {2, {2}};
  property "type_@unsend" (owner: #2, flags: "r") = {2, {2}};
  property type_expire (owner: HACKER, flags: "rc") = {0};
  property type_replyto (owner: HACKER, flags: "rc") = {1, {1}};
  property unsend_sequences (owner: #2, flags: "r") = {"before", "after", "since", "until", "subject", "body", "last"};

  override _namelist (owner: HACKER, flags: "r") = "!include!noinclude!all!sender!nosubject!expert!enter!sticky!@mail!replyto!expire!followup!resend_forw!rn_order!news!no_dupcc!no_unsend!@unsend!";
  override aliases (owner: HACKER, flags: "rc") = {"Mail Options"};
  override description (owner: HACKER, flags: "rc") = "Options for mailing";
  override extras (owner: HACKER, flags: "r") = {"noinclude", "sender"};
  override names (owner: HACKER, flags: "r") = {
    "include",
    "all",
    "followup",
    "nosubject",
    "expert",
    "enter",
    "sticky",
    "@mail",
    "replyto",
    "expire",
    "resend_forw",
    "rn_order",
    "news",
    "no_dupcc",
    "no_unsend",
    "@unsend"
  };
  override namewidth (owner: HACKER, flags: "rc") = 19;
  override object_size (owner: HACKER, flags: "r") = {14349, 1084848672};

  method actual owner: HACKER
    "Expand noinclude and sender into the inverse include and all flags.";
    const {name, value} = args;
    const index = name in {"noinclude", "sender"};
    index && return {{{"include", "all"}[index], !value}};
    return {{name, value}};
  endmethod

  method "parse_@mail" owner: HACKER
    "Accept a default message sequence. The + switch selects new messages.";
    const {name, raw, data} = args;
    return raw == 1 ? {name, "new"} | {name, raw};
  endmethod

  method parse_sticky owner: HACKER
    "Parse a numeric option. The + switch enables sticky folders.";
    let {name, raw, data} = args;
    if (typeof(raw) == TYPE_LIST)
      length(raw) > 1 && return "Too many arguments.";
      !raw && return "Number expected.";
      raw = raw[1];
    elseif (typeof(raw) == TYPE_INT)
      return {name, raw ? 1 | 0};
    endif
    const value = $code_utils:toint(raw);
    value == E_TYPE && return tostr("`", raw, "'?  Number expected.");
    return {name, value};
  endmethod

  method parse_replyto owner: HACKER
    "Parse recipients for a Reply-to header. Return {name, recipients} or a diagnostic.";
    let {name, raw, data} = args;
    if (typeof(raw) == TYPE_STR)
      raw = $string_utils:explode(raw, ",");
    elseif (typeof(raw) == TYPE_INT)
      return raw ? "You need to give one or more recipients." | {name, 0};
    endif
    const recipients = $mail_editor:parse_recipients({}, raw);
    !recipients && return "No valid recipients in list.";
    return {name, recipients};
  endmethod

  method show_sticky owner: HACKER
    "Describe whether mail commands retain the last selected folder.";
    const value = this:get(@args);
    !value && return {false, {"Teflon folders:  mail commands always default to `on me'."}};
    return {true, {"Sticky folders:  mail commands default to whatever", "mail collection the previous successful command looked at."}};
  endmethod

  method "show_@mail" owner: HACKER
    "Describe the selected or default message sequence for @mail.";
    const value = this:get(@args);
    const sequence = value || $mail_agent.("player_default_@mail");
    return {value ? "" | 0, {tostr("Default message sequence for @mail:  ", typeof(sequence) == TYPE_STR ? sequence | $string_utils:from_list(sequence, " "))}};
  endmethod

  method show_replyto owner: HACKER
    "Describe the default Reply-to recipients, or the absence of that header.";
    const value = this:get(@args);
    !value && return {0, {"No default Reply-to: field"}};
    return {"", {tostr("Default Reply-to:  ", $mail_agent:name_list(@value))}};
  endmethod

  method show owner: HACKER
    "Describe mail options and explain inverse aliases.";
    const {options, name} = args;
    const index = name in {"sender", "noinclude"};
    !index && return pass(@args);
    const actual = {"all", "include"}[index];
    return {@pass(options, actual), tostr("(", name, " is a synonym for -", actual, ")")};
  endmethod

  method check_replyto owner: HACKER
    "Normalize an object or list of objects to a recipient list, or return a diagnostic.";
    const {value} = args;
    typeof(value) == TYPE_OBJ && return {{value}};
    !this:istype(value, {{TYPE_OBJ}}) && return "Object or list of objects expected.";
    return {value};
  endmethod

  method show_expire owner: HACKER
    "Describe the expiry interval. Negative values disable expiry; zero selects the default.";
    const value = this:get(args[1], "expire");
    value < 0 && return {true, {"Messages will not expire."}};
    return {value, {tostr("Unkept messages expire in ", $time_utils:english_time(value || $mail_agent.player_expire_time), value ? "" | " (default)")}};
  endmethod

  method parse_expire owner: HACKER
    "Parse seconds, an English duration, or Never. The + switch disables expiry.";
    let {name, value, data} = args;
    if (typeof(value) == TYPE_STR && index(value, " "))
      value = $string_utils:explode(value, " ");
      !value && return {name, 0};
    endif
    value == 1 && return {name, -1};
    if (typeof(value) == TYPE_LIST)
      !value && return {name, 0};
      if (length(value) > 1)
        const interval = $time_utils:parse_english_time_interval(@value);
        typeof(interval) == TYPE_ERR && return "Time interval should be of a form like \"30 days, 10 hours and 43 minutes\".";
        return {name, interval};
      endif
      value = value[1];
    endif
    const seconds = $code_utils:toint(value);
    typeof(seconds) == TYPE_INT && return {name, seconds < 0 ? -1 | seconds};
    value == "Never" && return {name, -1};
    return "Number, time interval (e.g., \"30 days\"), or \"Never\" expected";
  endmethod

  method init_for_core owner: #2
    "Reset inherited state during core extraction. Only wizard callers can invoke the reset.";
    !caller_perms().wizard && return;
    pass(@args);
  endmethod

  method check_news owner: HACKER
    "Accept new, contents, or all as the default news view.";
    const {value} = args;
    value in {"new", "contents", "all"} && return {value};
    return "Error: `news' option must be one of `new' or `contents' or `all'";
  endmethod

  method parse_news owner: HACKER
    "Parse the default news view. Flag syntax cannot select a news view.";
    const {name, raw, data} = args;
    typeof(raw) == TYPE_INT && return tostr(name, " is not a boolean option.");
    return {name, typeof(raw) == TYPE_STR ? raw | $string_utils:from_list(raw, " ")};
  endmethod

  method show_news owner: HACKER
    "Describe which news articles the news command displays.";
    const value = this:get(@args);
    value == "all" && return {value, {"the `news' command will show all news"}};
    value == "contents" && return {value, {"the `news' command will show the titles of all articles"}};
    value == "new" && return {value, {"the `news' command will show only new news"}};
    return {0, {"the `news' command will show all news"}};
  endmethod

  method "parse_@unsend" owner: #2
    "Parse the default @unsend sequence. Each entry needs one permitted selector and one colon.";
    let {name, value, data} = args;
    typeof(value) == TYPE_INT && return tostr(name, " is not a boolean option.");
    typeof(value) == TYPE_STR && (value = {value});
    const selectors = this.unsend_sequences;
    for sequence in (value)
      const colon = index(sequence, ":");
      !colon || !(sequence[1..colon - 1] in selectors) && return tostr("Invalid sequence - ", sequence);
      colon != rindex(sequence, ":") && return tostr("As a preventative measure, you may not use more than one : in a sequence. ", "The following sequence is therefore invalid - ", sequence);
    endfor
    return {name, value};
  endmethod

  method "show_@unsend" owner: #2
    "Describe the selected or default message sequence for @unsend.";
    const value = this:get(@args);
    const sequence = value || $mail_agent.("player_default_@unsend");
    return {value ? "" | 0, {tostr("Default message sequence for @unsend:  ", typeof(sequence) == TYPE_STR ? sequence | $string_utils:from_list(sequence, " "))}};
  endmethod
endobject
