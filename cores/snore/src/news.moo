object NEWS [
  import_export_id -> "news"
]
  name: "News"
  parent: MAIL_RECIPIENT
  location: MAIL_AGENT
  owner: HACKER
  readable: true

  property archive_news (owner: HACKER, flags: "rc") = {};
  property current_news (owner: HACKER, flags: "rc") = {1, 2};
  property current_news_going (owner: HACKER, flags: "rc") = {};
  property last_news_time (owner: HACKER, flags: "rc") = 1790208000;

  override aliases (owner: HACKER, flags: "rc") = {"News"};
  override description (owner: HACKER, flags: "rc") = "It's the current issue of the News, dated %d.";
  override expire_period (owner: HACKER, flags: "r") = 0;
  override last_msg_date (owner: HACKER, flags: "r") = 1790208000;
  override last_used_time (owner: HACKER, flags: "r") = 1790208000;
  override mail_forward (owner: HACKER, flags: "r") = {};
  override messages (owner: HACKER, flags: "") = {
    {
      1,
      {
        1790208000,
        "Wizard (#2)",
        "*News (#61)",
        "Welcome to Snore Core",
        "",
        "Welcome to Snore Core",
        "just boring enough",
        "",
        "Snore Core is a LambdaCore fork for mooR. Familiar MOO commands, rooms, objects, mail, and live programming remain at its center.",
        "The goal is to fit most existing MOO tutorials while using more of mooR's language and database facilities.",
        "",
        "Getting started",
        "---------------",
        "Type help introduction for an introduction, help index for topics, and @version for the server and core names.",
        "Try look, say hello, and @who. Mail, news, private pages, gagging, and guests are available.",
        "",
        "For administrators",
        "------------------",
        "Customize $login.welcome_message and $login.help_message for your world.",
        "Set $mail_agent.moo_name to your world name. Set $login.create_enabled to control account creation.",
        "Set your password with @password. Use help @password for its syntax.",
        "$player_class selects the class for new accounts. It defaults to $default_player. Keep $player as the base class.",
        "The builder, programmer, and wizard classes install their command features by default. Feature membership does not grant authority.",
        "The @programmer command promotes a player to programmer. Wizard authority allows changes throughout the database.",
        "The supplied Guest account supports guest visits. See help @guests and help @make-guest for administration.",
        "The news is a mailing list: send mail to *News, then use @addnews $ to *News to publish the latest message.",
        "",
        "What differs from older cores",
        "-----------------------------",
        "Core objects use traditional object numbers. Newly created player and world objects use UUID identifiers.",
        "Clients handle long-output paging and word wrapping. The core has no FTP, HTTP, or Gopher services.",
        "The mooR book in book/src describes the language and database. The core README and style guide describe this fork.",
        "",
        "Forked from LambdaCore through lambda-moor. The original core is the work of Pavel Curtis and the LambdaMOO community."
      }
    }
  };
  override moderated (owner: HACKER, flags: "rc") = 1;
  override object_size (owner: HACKER, flags: "r") = {21017, 1084848672};
  override readers (owner: HACKER, flags: "rc") = 1;

  method description owner: HACKER
    "Return the newspaper description with the current edition date substituted.";
    const raw = ctime(this.last_news_time);
    const date = raw[1..10] + "," + raw[20..24];
    return strsub(this.description, "%d", date);
  endmethod

  method is_writable_by owner: #2
    "Allow ordinary folder writers and the configured wizard-player mail identities.";
    return pass(@args) || args[1] in $list_utils:map_prop($object_utils:descendants($wiz), "mail_identity");
  endmethod

  method rm_message_seq owner: HACKER
    "Remove messages and update the current edition only after mailbox removal succeeds.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const {sequence} = args;
    const removed = $seq_utils:intersection(this.current_news, sequence);
    const edition = $seq_utils:contract(this.current_news, sequence);
    const result = $mail_agent:(verb)(@args);
    this.current_news_going = removed;
    this.current_news = edition;
    return result;
  endmethod

  method undo_rmm owner: HACKER
    "Restore the last removed messages and re-add them to the current edition.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const seq = $mail_agent:(verb)(@args);
    this.current_news = $seq_utils:union(this.current_news_going, $seq_utils:expand(this.current_news, seq));
    this.current_news_going = {};
    return seq;
  endmethod

  method expunge_rmm owner: HACKER
    "Expunge removed messages and drop their edition entries.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    this.current_news_going = {};
    return $mail_agent:(verb)(@args);
  endmethod

  method set_current_news owner: HACKER
    "Validate and replace the edition; notify readers when its newest timestamp advances.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const {sequence} = args;
    if (!sequence)
      this.current_news = {};
      this.last_news_time = 0;
      return;
    endif
    const selected = this:messages_in_seq(sequence);
    length(selected) > 0 || raise(E_INVARG, "The edition must contain stored messages.");
    const newest = max(@{ item[2][1] for item in (selected) });
    this.current_news = sequence;
    newest > this.last_news_time || return;
    this.last_news_time = newest;
    this:touch();
  endmethod

  method add_current_news owner: HACKER
    "Add messages to the current edition.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    return this:set_current_news($seq_utils:union(this.current_news, args[1]));
  endmethod

  method rm_current_news owner: HACKER
    "Remove messages from the current edition.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    return this:set_current_news($seq_utils:intersection(this.current_news, $seq_utils:complement(args[1])));
  endmethod

  method news_display_seq_full owner: #2
    ":news_display_seq_full(msg_seq) => {cur, last-read-date}";
    "Display the given msg_seq as a collection of news items";
    set_task_perms(caller_perms());
    const desc = this:description();
    player:notify(typeof(desc) == TYPE_LIST ? desc[1] | desc);
    player:notify("");
    const msgs = this:messages_in_seq(args[1]);
    const n = length(msgs);
    !n && return {0, 0};
    for i in [1..n]
      const item = msgs[i];
      player:notify_lines(this:to_text(@item[2]));
      player:notify("");
    endfor
    player:notify("(end)");
    return {msgs[n][1], msgs[n][2][1]};
  endmethod

  method to_text owner: HACKER
    ":to_text(@msg) => message in text form -- formatted like a $news entry circa October, 1993";
    const date = args[1];
    const subject = args[4] == " " ? "-*-NEWS FLASH-*-" | $string_utils:uppercase(args[4]);
    const text = args[("" in {@args, ""}) + 1..$];
    const ctime = $time_utils:time_sub("$D, $N $3, $Y", date);
    return {ctime, subject, @text};
  endmethod

  method check owner: #2
    "Notify the player when the newspaper has items they have not read.";
    set_task_perms(caller_perms());
    (player:get_current_message(this) || {0, 0})[2] < this.last_news_time || return;
    const option = player:mail_option("news");
    if (option in {0, "all"})
      player:tell("There is new news.  Type `news' to read all news or `news new' to read just new news.");
    elseif (option == "contents")
      player:tell("There is new news.  Type `news all' to read all news or `news new' to read just new news.");
    elseif (option == "new")
      player:tell("There is new news.  Type `news' to read new news, or `news all' to read all news.");
    endif
  endmethod

  verb touch (this none none) owner: #2 flags: "rxd"
    "Tell connected players who have not seen the edition that it changed.";
    const who = valid(caller_perms()) ? caller_perms() | player;
    !this:ok_write(caller, who) && return player:notify("Permission denied.");
    for recipient in (connected_players())
      if (!$object_utils:has_callable_verb(recipient, "get_current_message"))
        continue;
      endif
      if ((recipient:get_current_message(this) || {0, 0})[2] < this.last_news_time)
        recipient:notify("There's a new edition of the newspaper.  Type 'news new' to see the new article(s).");
      endif
    endfor
  endverb

  verb "@addnews" (any at this) owner: #2 flags: "rxd"
    "'@addnews <message-sequence> to <this>' - Add articles to the current edition.";
    caller_perms() == #-1 || caller_perms() == player || raise(E_PERM);
    set_task_perms(player);
    if (!this:is_writable_by(player))
      player:notify("You can't write the news.");
      return;
    endif
    const result = this:add_news(args[1..(prepstr in args) - 1], player:get_current_message(this) || {0, 0});
    if (typeof(result) == TYPE_STR)
      player:notify(result);
      return;
    endif
    const current = this.current_news;
    if (current)
      player:notify("Current newspaper set.");
      this:display_seq_headers(current);
    else
      player:notify("Current newspaper is now empty.");
    endif
  endverb

  verb "@rmnews" (any from this) owner: #2 flags: "rxd"
    "'@rmnews <message-sequence> from <this>' - Remove articles from the current edition.";
    caller_perms() == #-1 || caller_perms() == player || raise(E_PERM);
    set_task_perms(player);
    if (!this:is_writable_by(player))
      player:notify("You can't write the news.");
      return;
    endif
    const result = this:rm_news(args[1..(prepstr in args) - 1], player:get_current_message(this) || {0, 0});
    if (typeof(result) == TYPE_STR)
      player:notify(result);
      return;
    endif
    const current = this.current_news;
    if (current)
      player:notify("Current newspaper set.");
      this:display_seq_headers(current);
    else
      player:notify("Current newspaper is now empty.");
    endif
  endverb

  verb "@setnews" (this at any) owner: #2 flags: "rd"
    "Replace the current edition with the given message sequence.";
    set_task_perms(player);
    if (!this:is_writable_by(player))
      player:notify("You can't write the news.");
      return;
    endif
    const strings = args[(prepstr in args) + 1..$];
    const seq = this:_parse(strings, @player:get_current_message(this) || {0, 0});
    if (typeof(seq) == TYPE_STR)
      player:notify(seq);
      return;
    endif
    if (this.current_news == seq)
      player:notify("No change.");
      return;
    endif
    this:set_current_news(seq);
    if (seq)
      player:notify("Current newspaper set.");
      this:display_seq_headers(seq);
    else
      player:notify("Current newspaper is now empty.");
    endif
  endverb

  method _parse owner: HACKER
    "Parse a message sequence against the news folder; return a sequence or an error string.";
    const strings = args[1];
    !strings && return "You need to specify a message sequence";
    const pms = this:parse_message_seq(@args);
    typeof(pms) == TYPE_STR && return $string_utils:substitute(pms, {{"%f", "The news"}, {"%<has>", "has"}, {"%%", "%"}});
    typeof(pms) != TYPE_LIST && return tostr(pms);
    length(pms) > 1 && return tostr("I don't understand `", pms[2], "'.");
    const seq = pms[1];
    !seq && return tostr("The News (", this, ") has no `", $string_utils:from_list(strings, " "), "' messages.");
    return seq;
  endmethod

  method init_for_core owner: #2
    "Create the initial newspaper during wizard-authorized core extraction.";
    caller_perms().wizard || return E_PERM;
    pass(@args);
    this.description = "It's the current issue of the News, dated %d.";
    this.moderated = 1;
    this.last_news_time = 0;
    this.readers = 1;
    this.expire_period = 0;
    this.archive_news = {};
    $mail_agent:send_message(#2, this, "Welcome to Snore Core", $wiz_utils.new_core_message);
    this:add_news("$");
  endmethod

  method add_news owner: #2
    "Add a parsed message sequence to the current edition.";
    this:ok_write(caller, caller_perms()) || raise(E_PERM);
    const {specs, ?cur = {0, 0}} = args;
    const seq = this:_parse(specs, @cur);
    typeof(seq) == TYPE_STR && return seq;
    const old = this.current_news;
    const new = $seq_utils:union(old, seq);
    old == new && return "Those messages are already in the news.";
    this:set_current_news(new);
    return 1;
  endmethod

  method rm_news owner: #2
    "Remove a parsed message sequence from the current edition.";
    this:ok_write(caller, caller_perms()) || raise(E_PERM);
    const {specs, ?cur = {0, 0}} = args;
    const seq = this:_parse(specs, @cur);
    typeof(seq) == TYPE_STR && return seq;
    const old = this.current_news;
    const new = $seq_utils:intersection(old, $seq_utils:complement(seq));
    old == new && return "Those messages were not in the news.";
    this:set_current_news(new);
    return 1;
  endmethod

  verb "@listnews" (none on this) owner: #2 flags: "rxd"
    "List the current newspaper article headers with reader authority.";
    caller_perms() == $nothing || caller_perms() == player || raise(E_PERM);
    set_task_perms(player);
    player:notify("The following articles are currently in the newspaper:");
    this:display_seq_headers(this.current_news);
  endverb

  verb "@clearnews" (this none none) owner: #2 flags: "rd"
    "Empty the current edition.";
    set_task_perms(player);
    if (!this:is_writable_by(player))
      player:notify("You can't write the news.");
      return;
    endif
    this:set_current_news({});
    player:notify("Current newspaper is now empty.");
  endverb

  method date_sort owner: HACKER
    "Sort news messages atomically and preserve the edition's membership by message identity.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const previous = this.current_news;
    const order = $mail_agent:_sort_messages();
    let edition = {};
    for position in [1..length(order)]
      $seq_utils:contains(previous, order[position]) && (edition = $seq_utils:add(edition, position, position));
    endfor
    this.current_news = edition;
    this.current_news_going = {};
    return 0;
  endmethod
endobject
