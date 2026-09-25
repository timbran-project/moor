object MAIL_AGENT [
  import_export_id -> "mail_agent"
]
  name: "Mail Distribution Center"
  parent: ROOT_CLASS
  owner: HACKER
  readable: true

  property large_domains (owner: #2, flags: "r") = {};
  property last_mail_time (owner: HACKER, flags: "r") = 0;
  property max_list_aliases (owner: HACKER, flags: "rc") = 8;
  property max_mail_notify (owner: HACKER, flags: "rc") = 15;
  property moo_name (owner: #2, flags: "rc") = "Snore Core";
  property options (owner: HACKER, flags: "rc") = {
    "include",
    "noinclude",
    "all",
    "sender",
    "nosubject",
    "expert",
    "enter",
    "sticky",
    "@mail",
    "replyto"
  };
  property "player_default_@mail" (owner: HACKER, flags: "rc") = "last:15";
  property "player_default_@unsend" (owner: #2, flags: "r") = "last:1";
  property player_expire_time (owner: HACKER, flags: "rc") = 2592000;
  property reserved_patterns (owner: HACKER, flags: "r") = {};
  property site (owner: #2, flags: "r") = "yoursite";
  property time_collisions (owner: HACKER, flags: "r") = {0, 0};
  property valid_email_regexp (owner: #2, flags: "rc") = "^[-a-z0-9_!.%+$'=/]*[-a-z0-9_!%+$'=]$";
  property valid_host_regexp (owner: #2, flags: "rc") = "^%([-_a-z0-9]+%.%)+%(gov%|edu%|com%|org%|int%|mil%|net%|%nato%|arpa%|name%|info%|[a-z][a-z]%)$";

  override aliases (owner: HACKER, flags: "rc") = {"Mail Distribution Center", "Postmaster"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the database of mailing-list/mail-folder objects.",
    "The basic procedure for creating a new list/folder is to create a child of $mail_recipient (Generic Mail Recipient) assign it a suitable name&aliases, set a suitable .mail_forward/.mail_notify (or create suitable :mail_forward() and :mail_notify() verbs) and then teleport it here.",
    "",
    "Avaliable aliases:",
    ""
  };
  override object_size (owner: HACKER, flags: "r") = {50262, 1084848672};

  method resolve_addr owner: HACKER
    "resolve(name,from,seen,prevrcpts,prevnotifs) => {rcpts,notifs} or E_INVARG";
    "resolve(list,from,seen,prevrcpts,prevnotifs) => {bogus,rcpts,notifs}";
    "Trace .mail_forward lists and .mail_notify to decide where a message goes and who is told.";
    "The list form collects invalid addresses in `bogus' and continues with the rest.  The single";
    "address form returns E_INVARG when the address is invalid.";
    const {recip, from, ?seen = {}, ?prevrcpts = {}, ?prevnotifs = {}} = args;
    let sofar = {prevrcpts, prevnotifs};
    if (typeof(recip) == TYPE_LIST)
      let bogus = {};
      for r in (recip)
        const result = this:resolve_addr(r, from, seen, @sofar);
        result ? (sofar = result) | (bogus = setadd(bogus, r));
      endfor
      return {bogus, @sofar};
    endif
    recip == $nothing || recip in seen && return sofar;
    const is_mailbox = is_player(recip) || $object_utils:isa(recip, $mail_recipient);
    !valid(recip) || !is_mailbox && return E_INVARG;
    let fwd = recip:mail_forward(from);
    if (typeof(fwd) != TYPE_LIST)
      typeof(fwd) == TYPE_STR && player:tell(fwd);
      return E_INVARG;
    endif
    if (is_player(recip) && `recip:refuses_action(from, "mail") ! E_VERBNF')
      player:tell(recip:mail_refused_msg());
      return E_INVARG;
    endif
    let include_recip = false;
    if (fwd)
      const r = recip in fwd;
      if (r)
        include_recip = true;
        fwd = listdelete(fwd, r);
      endif
      const result = this:resolve_addr(fwd, recip, setadd(seen, recip), @sofar);
      const bogus = result[1];
      bogus && player:tell(recip.name, "(", recip, ")'s .mail_forward list includes the following bogus entr", length(bogus) > 1 ? "ies:  " | "y:  ", $string_utils:english_list(bogus));
      sofar = result[2..3];
    else
      include_recip = true;
    endif
    let biffs = sofar[2];
    for n in (this:mail_notify(recip, from))
      if (valid(n))
        const i = $list_utils:iassoc(n, biffs);
        i ? (biffs[i] = setadd(biffs[i], recip)) | (biffs = {{n, recip}, @biffs});
      endif
    endfor
    return {include_recip ? setadd(sofar[1], recip) | sofar[1], biffs};
  endmethod

  method sends_to owner: HACKER
    "sends_to(from,addr,rcpt[,seen]) ==> true iff mail sent to addr passes through rcpt.";
    const {from, addr, rcpt, ?seen = {}} = args;
    addr == rcpt && return true;
    addr in seen && return false;
    const seen2 = {@seen, addr};
    const fwd = this:mail_forward(addr, @from ? {} | {from});
    for a in (typeof(fwd) == TYPE_LIST ? fwd | {})
      this:sends_to(addr, a, rcpt, seen2) && return true;
    endfor
    return false;
  endmethod

  method send_message owner: HACKER
    "send_message(from,rcpt-list,hdrs,msg) -- formats and sends a mail message.  hdrs is either the text of the subject line, or a {subject,{reply-to,...}} list.";
    "Return E_PERM if from isn't owned by the caller.";
    "Return {0, @invalid_rcpts} if rcpt-list contains any invalid addresses.  No mail is sent in this case.";
    "Return {1, @actual_rcpts} if successful.";
    const {from, to, orig_hdrs, msg} = args;
    let hdrs;
    if (typeof(orig_hdrs) == TYPE_LIST && length(orig_hdrs) > 2)
      hdrs = orig_hdrs[1..2];
      const extra = orig_hdrs[3..$];
      const strip = {"Resent-To", "Resent-By"};
      for h in (extra)
        h[1] in strip || (hdrs = {@hdrs, h});
      endfor
    else
      hdrs = orig_hdrs;
    endif
    $perm_utils:controls(caller_perms(), from) || return E_PERM;
    const text = $mail_agent:make_message(from, to, hdrs, msg);
    return this:raw_send(text, to, from);
  endmethod

  method raw_send owner: #2
    "Deliver resolved recipients, then fork notifications after the deliveries commit.";
    "Core delivery adds no suspension; custom forwarding/receive hooks may commit or reject.";
    "raw_send(text,rcpts,sender) -- sends an already formatted message and notifies interested parties.";
    "Return {E_PERM} if the caller is not entitled to use this verb.";
    "Return {0, @invalid_rcpts} if rcpts contains any invalid addresses.  No mail is sent in this case.";
    "Return {1, @actual_rcpts} if successful.";
    let {text, rcpts, from} = args;
    typeof(rcpts) != TYPE_LIST && (rcpts = {rcpts});
    caller in {$mail_agent, $mail_editor} || return {E_PERM};
    const resolve = this:resolve_addr(rcpts, from);
    const bogus = resolve[1];
    bogus && return {0, bogus};
    this:touch(rcpts);
    const actual_rcpts = resolve[2];
    let biffs = resolve[3];
    let results = {};
    for recip in (actual_rcpts)
      let e = recip:receive_message(text, from);
      if (typeof(e) in {TYPE_ERR, TYPE_STR})
        player:notify(tostr(recip, ":receive_message:  ", e));
        e = 0;
      elseif (is_player(recip) && e)
        const i = $list_utils:iassoc(recip, biffs);
        if (i)
          if (!(recip in listdelete(biffs[i], 1)))
            biffs[i][2..1] = {recip};
          endif
        else
          biffs = {{recip, recip}, @biffs};
        endif
      endif
      results = {@results, e};
    endfor
    fork (0)
      for b in (biffs)
        if ($object_utils:has_callable_verb(b[1], "notify_mail"))
          let mnums = {};
          for r in (listdelete(b, 1))
            const rn = r in actual_rcpts;
            mnums = {@mnums, rn && results[rn]};
          endfor
          b[1]:notify_mail(from, listdelete(b, 1), mnums);
        endif
      endfor
    endfork
    return {1, @actual_rcpts};
  endmethod

  method "mail_forward mail_notify" owner: HACKER
    "Call a recipient forwarding or notification hook, returning an empty list if absent.";
    const who = args[1];
    $object_utils:has_verb(who, verb) || return {};
    return who:(verb)(@listdelete(args, 1));
  endmethod

  method touch owner: HACKER
    "touch(name or list,seen) => does .last_used_time = time() if we haven't already touched this in the last hour";
    const {recip, ?seen = {}} = args;
    if (typeof(recip) == TYPE_LIST)
      for r in (recip)
        this:touch(r, seen);
      endfor
      return;
    endif
    const is_mailbox = is_player(recip) || $mail_recipient in $object_utils:ancestors(recip);
    valid(recip) && !(recip in seen) && is_mailbox || return;
    const fwd = this:mail_forward(recip);
    fwd && this:touch(fwd, {@seen, recip});
    is_player(recip) || (recip.last_used_time = time());
  endmethod

  method look_self owner: HACKER
    "Describe this service and its visible mailing lists without automatic suspension.";
    player:tell_lines(this.description);
    for c in (this.contents)
      c:look_self();
    endfor
  endmethod

  method acceptable owner: HACKER
    "Only allow mailing lists/folders in here and only if their names aren't already taken.";
    const what = args[1];
    return $object_utils:isa(what, $mail_recipient) && this:check_names(what, @what.aliases) && what:description() != parent(what):description();
  endmethod

  method check_names owner: HACKER
    "Return whether aliases include an address name and avoid reserved patterns or occupied aliases.";
    let {object, @aliases} = args;
    typeof(object) == TYPE_STR && (aliases = args);
    if (length(aliases) > this.max_list_aliases)
      player:tell("Mailing lists may not have more than ", this.max_list_aliases, " aliases.");
      return false;
    endif
    let usable = false;
    for alias in (aliases)
      if (index(alias, " "))
        continue;
      endif
      const reserved = this:reserved_pattern(alias);
      if (reserved)
        player:tell("Mailing list name \"", alias, "\" uses a reserved pattern: ", reserved[1]);
        return false;
      endif
      for spelling in (setadd(setadd({alias}, strsub(alias, "_", "-")), strsub(alias, "-", "_")))
        const other = this:match(spelling, $nothing);
        if (valid(other) && other != object && strsub(spelling, "_", "-") in { strsub(name, "_", "-") for name in (other.aliases) })
          player:tell("Mailing list name \"", spelling, "\" in use on ", other.name, "(", other, ")");
          return false;
        endif
      endfor
      usable = true;
    endfor
    return usable;
  endmethod

  method "match_old match" owner: HACKER
    "Match a public or private mailing list by literal identity, alias, or unambiguous prefix.";
    let {name, ?who = player} = args;
    !name && return $nothing;
    name[1] == "*" && (name = name[2..$]);
    !name && return $nothing;
    const literal = $string_utils:literal_object(name);
    valid(literal) && $object_utils:isa(literal, $mail_recipient) && return literal;
    const reserved = this:reserved_pattern(name);
    reserved && return reserved[2]:match_mail_recipient(name);
    const private = valid(who) ? `who.mail_lists ! E_PROPNF, E_PERM => {}' | {};
    const candidates = {@this.contents, @typeof(private) == TYPE_LIST ? private | {}};
    const needle = strsub(name, "_", "-");
    let partial = $failed_match;
    for recipient in (candidates)
      if (!valid(recipient))
        continue;
      endif
      for alias in (recipient.aliases)
        const normalized = strsub(alias, "_", "-");
        normalized == needle && return recipient;
        if (index(normalized, needle) == 1 && !index(normalized, " "))
          if (partial == $failed_match)
            partial = recipient;
          elseif (partial != recipient)
            partial = $ambiguous_match;
          endif
        endif
      endfor
    endfor
    return partial;
  endmethod

  method match_recipient owner: HACKER
    ":match_recipient(string[,meobj]) => $player or $mail_recipient object that matches string.  Optional second argument (defaults to player) is returned in the case string==\"me\" and is also used to obtain a list of private $mail_recipients to match against.";
    const {string, ?me = player} = args;
    if (valid(me))
      const matched = me:my_match_recipient(string);
      $failed_match != matched && return matched;
    endif
    !string && return $nothing;
    string[1] == "*" && string != "*" && return this:match(@args);
    if (string[1] == "`")
      args[1][1..1] = "";
      return $string_utils:match_player(@args);
    endif
    const o = $string_utils:match_player(@args);
    valid(o) || o == $ambiguous_match && return o;
    return this:match(@args);
  endmethod

  method match_failed owner: HACKER
    "Explain a failed recipient match; return whether the result denotes a failure.";
    const {match_result, string, ?cmd_id = ""} = args;
    const prefix = cmd_id || "";
    if (match_result == $nothing)
      player:tell(prefix, "You must specify a valid mail recipient.");
    elseif (match_result == $failed_match)
      player:tell(prefix, "There is no mail recipient called \"", string, "\".");
    elseif (match_result == $ambiguous_match)
      const nostar = index(string, "*") != 1;
      const lst = nostar && $player_db:find_all(string);
      if (lst)
        player:tell(prefix, "\"", string, "\" could refer to ", length(lst) > 20 ? tostr("any of ", length(lst), " players") | $string_utils:english_list($list_utils:map_arg(2, $string_utils, "pronoun_sub", "%n (%#)", lst), "no one", " or "), ".");
      else
        player:tell(prefix, "I don't know which \"", nostar ? "*" | "", string, "\" you mean.");
      endif
    elseif (!valid(match_result))
      player:tell(prefix, match_result, " does not exist.");
    else
      return 0;
    endif
    return 1;
  endmethod

  method make_message owner: HACKER
    ":make_message(sender,recipients,subject/replyto/additional-headers,body)";
    " => message in the form as it will get sent.";
    let {from, recips, hdrs, body} = args;
    let fromowner;
    try
      fromowner = from.owner;
    except (E_INVIND)
      raise(E_PERM);
    endtry
    const fromline = this:name_list(from);
    let toline = typeof(recips) == TYPE_LIST ? this:name_list(@recips) | this:name_list(recips);
    let others = {};
    if (typeof(hdrs) != TYPE_LIST)
      hdrs = {hdrs};
    endif
    const subj = hdrs[1];
    if (!valid(from))
      others = {"Probable-Sender:   " + this:name(fromowner)};
    elseif (!is_player(from))
      others = {"Sender:   " + this:name(from.owner)};
    endif
    const replyto = {@hdrs, 0}[2] && this:name_list(@hdrs[2]);
    if (length(hdrs) > 2)
      for h in (hdrs[3..$])
        if (match(h[1], "[a-z1-9-]+"))
          others = {@others, $string_utils:left(h[1] + ": ", 15) + h[2]};
        endif
      endfor
    endif
    const bodylines = typeof(body) == TYPE_LIST ? body | body ? {body} | {};
    return {this:time(), fromline, toline, subj || " ", @replyto ? {"Reply-to: " + replyto} | {}, @others, "", @bodylines};
  endmethod

  method name owner: HACKER
    "Format a recipient name with its opaque object identity; remove embedded object labels.";
    const what = args[1];
    let name;
    if (!valid(what))
      name = "???";
    elseif (!is_player(what) && $object_utils:has_callable_verb(what, "mail_name"))
      name = what:mail_name();
    else
      name = what.name;
    endif
    let m;
    while (true)
      m = $code_utils:match_objid(name);
      if (!m)
        break;
      endif
      const {s, e} = m[1..2];
      name[s..e] = "";
    endwhile
    return tostr(name, " (", what, ")");
  endmethod

  method name_list owner: HACKER
    "Format recipients as a readable address list.";
    return $string_utils:english_list($list_utils:map_arg(this, "name", args), "no one");
  endmethod

  method parse_address_field owner: HACKER
    ":parse_address_field(string) => list of objects";
    "This is the standard routine for parsing address lists that appear in From:, To: and Reply-To: lines";
    let objects = {};
    let string = args[1];
    let m;
    while (true)
      m = match(string, "(#[0-9A-F-]+)");
      if (!m)
        break;
      endif
      const {s, e} = m[1..2];
      const o = toobj(string[s + 1..e - 1]);
      #0 != o && (objects = {@objects, o});
      string = string[e + 1..$];
    endwhile
    return objects;
  endmethod

  method display_seq_full owner: #2
    ":display_seq_full(msg_seq[,preamble]) => {cur, last-read-date}";
    "Display the messages in msg_seq on folder (caller) to player.";
    set_task_perms(caller_perms());
    const {msg_seq, ?preamble = ""} = args;
    let cur = 0;
    let date = 0;
    for x in (caller:messages_in_seq(msg_seq))
      cur = x[1];
      date = x[2][1];
      player:display_message(preamble ? strsub(preamble, "%d", tostr(cur)) | {}, caller:msg_full_text(@x[2]));
    endfor
    return {cur, date};
  endmethod

  method display_seq_headers owner: #2
    ":display_seq_headers(msg_seq[,cur[,last_read_date]])";
    "Print header lines for the messages in msg_seq on folder (caller).";
    set_task_perms(caller_perms());
    const {msg_seq, ?cur = 0, ?last_old = $maxint} = args;
    const keep_seq = {@$seq_utils:contract(caller:kept_msg_seq(), $seq_utils:complement(msg_seq, 1, caller:length_all_msgs())), $maxint};
    let k = 1;
    let mcount = 0;
    for x in (caller:messages_in_seq(msg_seq))
      mcount = mcount + 1;
      if (keep_seq[k] <= mcount)
        k = k + 1;
      endif
      const fresh = x[2][1] > last_old;
      const annot = fresh ? "+" | k % 2 ? " " | "=";
      const line = tostr($string_utils:right(x[1], 4, cur == x[1] ? ">" | " "), ":", annot, " ", caller:msg_summary_line(@x[2]));
      player:tell(line);
    endfor
    player:tell("----+");
  endmethod

  method rm_message_seq owner: #2
    ":rm_message_seq(msg_seq) removes the given sequence from folder (caller).";
    "Save removed records and kept marks for undo.";
    set_task_perms(caller_perms());
    const old = caller.messages;
    const seq = args[1];
    let new = {};
    let save = {};
    let nums = {};
    let next = 1;
    for i in [1..length(seq) / 2]
      const start = seq[2 * i - 1];
      new = {@new, @old[next..start - 1]};
      const prev_next = next;
      next = seq[2 * i];
      save = {@save, {start - prev_next, old[start..next - 1]}};
      nums = {@nums, old[start][1], old[next - 1][1] + 1};
    endfor
    new = {@new, @old[next..$]};
    const save_kept = $seq_utils:intersection(caller.messages_kept, seq);
    const new_kept = $seq_utils:contract(caller.messages_kept, seq);
    caller.messages_going = save_kept ? {save_kept, save} | save;
    caller.messages = new;
    caller.messages_kept = new_kept;
    $object_utils:has_callable_verb(caller, "_fix_last_msg_date") && caller:_fix_last_msg_date();
    return $seq_utils:tostr(nums);
  endmethod

  method undo_rmm owner: #2
    ":undo_rmm()  restores previously deleted messages in .messages_going to .messages.";
    set_task_perms(caller_perms());
    const old = caller.messages;
    let going = caller.messages_going;
    let new = {};
    let seq = {};
    let last = 0;
    let next = 1;
    "There are two possible formats here:";
    "OLD: {{n,msgs},{n,msgs},...}";
    "NEW: {kept_seq, {{n,msgs},{n,msgs},...}}";
    let kept;
    if (going && (!going[1] || typeof(going[1][2]) == TYPE_INT))
      kept = going[1];
      going = going[2];
    else
      kept = {};
    endif
    for s in (going)
      new = {@new, @old[last + 1..last + s[1]], @s[2]};
      last = last + s[1];
      seq = {@seq, next + s[1], length(new) + 1};
      next = length(new) + 1;
    endfor
    caller.messages = {@new, @old[last + 1..$]};
    caller.messages_going = {};
    caller.messages_kept = $seq_utils:union(kept, $seq_utils:expand(caller.messages_kept, seq));
    $object_utils:has_callable_verb(caller, "_fix_last_msg_date") && caller:_fix_last_msg_date();
    return seq;
  endmethod

  method "expunge_rmm list_rmm" owner: #2
    ":list_rmm()    displays contents of .messages_going.";
    ":expunge_rmm() destroys contents of .messages_going once and for all.";
    "Both entry points return the number of removed messages.";
    set_task_perms(caller_perms());
    let cmg = caller.messages_going;
    let kept;
    if (cmg && (!cmg[1] || typeof(cmg[1][2]) == TYPE_INT))
      kept = cmg[1];
      cmg = cmg[2];
    else
      kept = {};
    endif
    if (verb == "expunge_rmm")
      caller.messages_going = {};
      let count = 0;
      for s in (cmg)
        count = count + length(s[2]);
      endfor
      return count;
    endif
    !cmg && return 0;
    let msgs = {};
    let seq = {};
    let next = 1;
    for s in (cmg)
      msgs = {@msgs, @s[2]};
      next = next + s[1];
      seq = {@seq, next, next + length(s[2])};
      next = next + length(s[2]);
    endfor
    kept = {@$seq_utils:contract(kept, $seq_utils:complement(seq, 1, $seq_utils:last(seq))), $maxint};
    let k = 1;
    let mcount = 0;
    for x in (msgs)
      mcount = mcount + 1;
      if (kept[k] <= mcount)
        k = k + 1;
      endif
      player:tell($string_utils:right(x[1], 4), ":", k % 2 ? "  " | "= ", caller:msg_summary_line(@x[2]));
    endfor
    msgs && player:tell("----+");
    return length(msgs);
  endmethod

  method renumber owner: #2
    "Renumber the caller's mailbox in one transaction; return {count, current-message index}.";
    "Discard undo positions; kept marks already use message indexes and remain valid.";
    set_task_perms(caller_perms());
    const {?current = 0} = args;
    const messages = caller.messages;
    const count = length(messages);
    const index = current ? $list_utils:iassoc_sorted(current, messages) | 0;
    caller.messages = { {position, messages[position][2]} for position in [1..count] };
    caller.messages_going = {};
    return {count, index};
  endmethod

  method msg_summary_line owner: HACKER
    ":msg_summary_line(@msg) => date/from/subject as a single string.";
    const body = ("" in {@args, ""}) + 1;
    let subject = body > length(args) ? 0 | args[body];
    subject || (subject = "(None.)");
    const when = args[1];
    let date;
    if (when < time() - 31536000)
      const c = player:ctime(when);
      date = c[5..11] + c[21..25];
    else
      date = player:ctime(when)[5..16];
    endif
    const from = args[2];
    args[4] != " " && (subject = args[4]);
    return tostr(date, "   ", $string_utils:left(from, 20), "   ", subject);
  endmethod

  method parse_message_seq owner: #2
    "parse_message_seq(strings,cur[,last_old])";
    "Default <message-sequence> parser for @mail, @read, and friends on folder (caller).";
    "Returns a string error message, or {msg_seq, @unused_strings}.";
    set_task_perms(caller_perms());
    let {strings, ?cur = 0, ?last_old = 0} = args;
    const nummsgs = caller:length_all_msgs();
    !nummsgs && return "%f %<has> no messages.";
    typeof(strings) != TYPE_LIST && (strings = {strings});
    let seq = {};
    let result = {};
    let in_mask = false;
    const keywords = ":from:%from:to:%to:subject:body:before:after:since:until:first:last:kept:unkept";
    const keyalist = {{1, "from"}, {6, "%from"}, {12, "to"}, {15, "%to"}, {19, "subject"}, {27, "body"}, {32, "before"}, {39, "after"}, {45, "since"}, {51, "until"}, {57, "first"}, {63, "last"}, {68, "kept"}, {73, "unkept"}};
    let strnum = 0;
    for string in (strings)
      strnum = strnum + 1;
      const colon = string ? index(string, ":") | 0;
      const prefix = colon ? ":" + string[1..colon - 1] | "";
      const k = prefix ? index(keywords, prefix) | 0;
      if (string && colon && k && k == rindex(keywords, prefix))
        const keywd = $list_utils:assoc(k, keyalist)[2];
        if (!in_mask)
          seq = {1, nummsgs + 1};
        endif
        in_mask = true;
        if (k <= 27)
          let pattern = string[colon + 1..$];
          if (!(keywd in {"subject", "body"}))
            if (keywd[1] == "%")
              pattern = $string_utils:explode(pattern, "|");
            else
              pattern = this:(keywd == "to" ? "_parse_to" | "_parse_from")(pattern);
              typeof(pattern) == TYPE_STR && return pattern;
            endif
          endif
          seq = caller:(keywd + "_msg_seq")(pattern, seq);
          if (typeof(seq) == TYPE_STR)
            strnum == 1 ? return seq | (seq = {});
          endif
        elseif (k <= 51)
          const date = this:_parse_date(string[colon + 1..$]);
          typeof(date) != TYPE_INT && return tostr("Bad date `", string, "':  ", date);
          const s = caller:length_date_le(keywd in {"before", "since"} ? date - 1 | date + 86399);
          if (keywd in {"before", "until"})
            seq = $seq_utils:remove(seq, s + 1, nummsgs);
          else
            seq = $seq_utils:remove(seq, 1, s);
          endif
        elseif (k <= 63)
          const n = toint(string[colon + 1..$]);
          n || return tostr("Bad number in `", string, "'");
          seq = $seq_utils:(keywd + "n")(seq, n);
        else
          colon < length(string) && return tostr("Unexpected junk after `", keywd, ":'");
          seq = caller:(keywd + "_msg_seq")(seq);
          !seq && strnum == 1 && return tostr("%f %<has> no ", keywd, " messages.");
        endif
      else
        if (in_mask)
          seq && (result = $seq_utils:union(result, seq));
          seq = {};
        endif
        in_mask = false;
        if (!string)
          cur || return "%f %<has> no current message.";
          const i = min(caller:length_num_le(cur - 1) + 1, nummsgs);
          seq = $seq_utils:add(seq, i, i);
        elseif (index(string, "next") == 1 && !index(string, "-"))
          string[1..4] = "";
          const n = string ? toint(string) | 1;
          n <= 0 && return tostr("Bad number `", string, "'");
          const i = caller:length_num_le(cur) + 1;
          i <= nummsgs || return "%f %<has> no next message.";
          seq = $seq_utils:add(seq, i, min(i + n - 1, nummsgs));
        elseif (index(string, "prev") == 1 && !index(string, "-"))
          string[1..4] = "";
          const n = string ? toint(string) | 1;
          n <= 0 && return tostr("Bad number `", string, "'");
          const i = caller:length_num_le(cur - 1);
          i || return "%f %<has> no previous message.";
          seq = $seq_utils:add(seq, max(1, i - n + 1), i);
        elseif (string == "new")
          const s = last_old ? caller:length_date_le(last_old) | caller:length_num_le(cur);
          s < nummsgs || return "%f %<has> no new messages.";
          seq = $seq_utils:add(seq, s + 1, nummsgs);
        elseif (string == "first")
          seq = $seq_utils:add(seq, 1, 1);
        elseif (toint(string))
          const n = toint(string);
          if (n <= 0)
            seq = $seq_utils:add(seq, max(0, nummsgs + n) + 1, nummsgs);
          else
            const i = caller:exists_num_eq(n);
            i || return tostr("%f %<has> no message numbered `", string, "'.");
            seq = $seq_utils:add(seq, i, i);
          endif
        elseif (string in {"last", "$"})
          seq = $seq_utils:add(seq, nummsgs, nummsgs);
        elseif (string == "cur")
          const i = caller:exists_num_eq(cur);
          i || return "%f's current message has been removed.";
          seq = $seq_utils:add(seq, i, i);
        else
          let i = index(string, "..");
          i <= 1 && (i = index(string, "-"));
          i <= 1 && return {$seq_utils:union(result, seq), @strings[strnum..$]};
          const sst = string[1..i - 1];
          let s;
          const start = toint(sst);
          if (start > 0)
            s = caller:length_num_le(start - 1);
          elseif (sst in {"next", "prev", "cur"})
            s = max(0, caller:length_num_le(cur - (sst != "next" ? 1 | 0)) - (sst == "prev" ? 1 | 0));
          elseif (sst in {"last", "$"})
            s = nummsgs - 1;
          elseif (sst == "first")
            s = 0;
          else
            return {$seq_utils:union(result, seq), @strings[strnum..$]};
          endif
          const j = string[i] == "." ? i + 2 | i + 1;
          const endstr = string[j..$];
          let e;
          const end = toint(endstr);
          if (end > 0)
            e = caller:length_num_le(end);
          elseif (endstr in {"next", "prev", "cur"})
            e = min(nummsgs, caller:length_num_le(cur - (endstr == "prev" ? 1 | 0)) + (endstr == "next" ? 1 | 0));
          elseif (endstr in {"last", "$"})
            e = nummsgs;
          elseif (endstr == "first")
            e = 1;
          else
            return {$seq_utils:union(result, seq), @strings[strnum..$]};
          endif
          s < e || return tostr("%f %<has> no messages in range ", string, ".");
          seq = $seq_utils:add(seq, s + 1, e);
        endif
      endif
    endfor
    return {$seq_utils:union(result, seq)};
  endmethod

  method "_parse_from _parse_to" owner: HACKER
    ":_parse_from(string with |'s in it) => object list";
    ":_parse_to(string with |'s in it) => object list";
    "For from:string and to:string selectors. Confirming a recycled literal reads input and commits.";
    let match_obj;
    let match_verb;
    let fail_obj;
    let fail_verb;
    if (verb == "_parse_to")
      match_obj = this;
      fail_obj = this;
      match_verb = "match_recipient";
      fail_verb = "match_failed";
    else
      match_obj = $string_utils;
      fail_obj = $command_utils;
      match_verb = "match_player";
      fail_verb = "player_match_failed";
    endif
    let plist = {};
    for w in ($string_utils:explode(args[1], "|"))
      let p = match_obj:(match_verb)(w);
      if (fail_obj:(fail_verb)(p, w))
        p = $string_utils:literal_object(w);
        if (p == $failed_match || !$command_utils:yes_or_no("Continue? "))
          return "Bad address list:  " + args[1];
        endif
      endif
      plist = setadd(plist, p);
    endfor
    return plist;
  endmethod

  method _parse_date owner: HACKER
    "Parse a mail date or weekday; return its midnight timestamp or an error description.";
    const words = $string_utils:explode(args[1], "-");
    let time;
    if (length(words) == 1)
      if (index("yesterday", words[1]) == 1)
        time = $time_utils:dst_midnight(time() - time() % 86400 - 86400);
      elseif (index("today", words[1]) == 1)
        time = $time_utils:dst_midnight(time() - time() % 86400);
      else
        time = $time_utils:from_day(words[1], -1);
        typeof(time) == TYPE_ERR && (time = "weekday, `Today', `Yesterday', or date expected.");
      endif
      return time;
    endif
    if (length(words) < 1 || length(words) > 3 || !toint(words[1]))
      return "Date should be of the form `5-Jan', `5-Jan-92', `Wed',`Wednesday'";
    endif
    let year = $code_utils:toint({@words, "-1"}[3]);
    E_TYPE == year && return "Date should be of the form `5-Jan', `5-Jan-92', `Wed',`Wednesday'";
    const day = toint(words[1]);
    const month_time = $time_utils:from_month(words[2], -1, day);
    typeof(month_time) == TYPE_ERR && return "Invalid month or day.";
    time = $time_utils:dst_midnight(month_time);
    if (length(words) == 3)
      const thisyear = toint(ctime(time)[21..24]);
      if (100 > year)
        year = thisyear + 50 - (thisyear - year + 50) % 100;
      endif
      time = $time_utils:dst_midnight($time_utils:from_month(words[2], year - thisyear - (year <= thisyear ? 1 | 0), day));
    endif
    return time;
  endmethod

  method new_message_num owner: #2
    ":new_message_num() => number that the next incoming message will receive.";
    set_task_perms(caller_perms());
    const msgs = caller.messages;
    const new = msgs ? msgs[$][1] + 1 | 1;
    const going = caller.messages_going;
    !going && return new;
    let rmsgs = going;
    if (!rmsgs[1] || typeof(rmsgs[1][2]) == TYPE_INT)
      rmsgs = rmsgs[2];
    endif
    const lastremoved = rmsgs[$][2];
    return max(new, lastremoved[$][1] + 1);
  endmethod

  method length_all_msgs owner: #2
    "Return the number of stored messages using the calling folder authority.";
    set_task_perms(caller_perms());
    return length(caller.messages);
  endmethod

  method length_date_le owner: #2
    "Return the count of date-sorted messages at or before the given timestamp.";
    set_task_perms(caller_perms());
    const date = args[1];
    const msgs = caller.messages;
    const count = length(msgs);
    if (count < 25)
      for l in [1..count]
        msgs[l][2][1] > date && return l - 1;
      endfor
      return count;
    endif
    let l = 1;
    let r = count;
    while (l <= r)
      const i = (r + l) / 2;
      if (date < msgs[i][2][1])
        r = i - 1;
      else
        l = i + 1;
      endif
    endwhile
    return r;
  endmethod

  method length_date_gt owner: #2
    "Return the count of date-sorted messages after the given timestamp.";
    set_task_perms(caller_perms());
    const date = args[1];
    const msgs = caller.messages;
    const len = length(msgs);
    if (len < 25)
      for r in [0..len - 1]
        msgs[len - r][2][1] <= date && return r;
      endfor
      return len;
    endif
    let l = 1;
    let r = len;
    while (l <= r)
      const i = (r + l) / 2;
      if (date < msgs[i][2][1])
        r = i - 1;
      else
        l = i + 1;
      endif
    endwhile
    return len - r;
  endmethod

  method length_num_le owner: #2
    ":length_num_le(num) => number of messages in folder numbered <= num";
    set_task_perms(caller_perms());
    return $list_utils:iassoc_sorted(args[1], caller.messages);
  endmethod

  method exists_num_eq owner: #2
    ":exists_num_eq(num) => index of message in folder numbered == num";
    set_task_perms(caller_perms());
    const i = $list_utils:iassoc_sorted(args[1], caller.messages);
    i || return 0;
    return caller.messages[i][1] == args[1] ? i | 0;
  endmethod

  method from_msg_seq owner: #2
    ":from_msg_seq(object or list[,mask])";
    " => msg_seq of messages from any of these senders";
    set_task_perms(caller_perms());
    let {plist, ?mask = {1}} = args;
    typeof(plist) != TYPE_LIST && (plist = {plist});
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let fseq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      for recipient in ($mail_agent:parse_address_field(message[2]))
        recipient in plist && (fseq = $seq_utils:add(fseq, position, position));
      endfor
    endfor
    return fseq || "%f %<has> no messages from " + $string_utils:english_list($list_utils:map_arg(2, $string_utils, "pronoun_sub", "%n (%#)", plist), "no one", " or ");
  endmethod

  method "%from_msg_seq" owner: #2
    ":%from_msg_seq(string or list of strings[,mask])";
    " => msg_seq of messages with one of these strings in the from line";
    set_task_perms(caller_perms());
    let {nlist, ?mask = {1}} = args;
    typeof(nlist) != TYPE_LIST && (nlist = {nlist});
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let fseq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      for pattern in (nlist)
        index(" " + message[2], pattern) && (fseq = $seq_utils:add(fseq, position, position));
      endfor
    endfor
    return fseq || "%f %<has> no messages from " + $string_utils:english_list($list_utils:map_arg($string_utils, "print", nlist), "no one", " or ");
  endmethod

  method to_msg_seq owner: #2
    ":to_msg_seq(object or list[,mask]) => msg_seq of messages to those people";
    set_task_perms(caller_perms());
    let {plist, ?mask = {1}} = args;
    typeof(plist) != TYPE_LIST && (plist = {plist});
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let seq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      for recipient in ($mail_agent:parse_address_field(message[3]))
        recipient in plist && (seq = $seq_utils:add(seq, position, position));
      endfor
    endfor
    return seq || "%f %<has> no messages to " + $string_utils:english_list($list_utils:map_arg(2, $string_utils, "pronoun_sub", "%n (%#)", plist), "no one", " or ");
  endmethod

  method "%to_msg_seq" owner: #2
    ":%to_msg_seq(string or list of strings[,mask])";
    " => msg_seq of messages containing one of strings in the to line";
    set_task_perms(caller_perms());
    let {nlist, ?mask = {1}} = args;
    typeof(nlist) != TYPE_LIST && (nlist = {nlist});
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let seq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      for pattern in (nlist)
        index(" " + message[3], pattern) && (seq = $seq_utils:add(seq, position, position));
      endfor
    endfor
    return seq || "%f %<has> no messages to " + $string_utils:english_list($list_utils:map_arg($string_utils, "print", nlist), "no one", " or ");
  endmethod

  method subject_msg_seq owner: #2
    ":subject_msg_seq(target) => msg_seq of messages with target in the Subject:";
    set_task_perms(caller_perms());
    const {target, ?mask = {1}} = args;
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let seq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      index(message[4], target) && (seq = $seq_utils:add(seq, position, position));
    endfor
    return seq || "%f %<has> no messages with subjects containing `" + target + "'";
  endmethod

  method body_msg_seq owner: #2
    ":body_msg_seq(target[,mask]) => msg_seq of messages with target in the body";
    set_task_perms(caller_perms());
    const {target, ?mask = {1}} = args;
    const messages = caller.messages;
    const selected = $seq_utils:intersection(mask, {1, length(messages) + 1});
    let seq = {};
    for position in ($seq_utils:tolist(selected))
      const message = messages[position][2];
      const blank = "" in message;
      if (blank && blank < length(message) && index(tostr(@message[blank + 1..$]), target))
        seq = $seq_utils:add(seq, position, position);
      endif
    endfor
    return seq || tostr("%f %<has> no messages containing `", target, "' in the body.");
  endmethod

  method messages_in_seq owner: #2
    ":messages_in_seq(msg_seq) => list of messages in msg_seq on folder (caller)";
    set_task_perms(caller_perms());
    const msgs = args[1];
    typeof(msgs) != TYPE_LIST && return caller.messages[msgs];
    length(msgs) == 2 && return caller.messages[msgs[1]..msgs[2] - 1];
    const messages = caller.messages;
    const selected = $seq_utils:intersection(msgs, {1, length(messages) + 1});
    let result = {};
    for range_index in [1..length(selected) / 2]
      result = {@result, @messages[selected[range_index * 2 - 1]..selected[range_index * 2] - 1]};
    endfor
    return result;
  endmethod

  method __convert_new owner: #2
    ":__convert_new(@msg) => msg in new format (if it isn't already)";
    "               ^ don't forget the @ here.";
    "If the msg is already in the new format it passes through unchanged.";
    "If the msg format is unrecognizable, warnings are printed.";
    let date = args[1];
    let start;
    if (typeof(date) != TYPE_INT)
      date = 0;
      start = 1;
    else
      start = 2;
      const colon = index(args[2], ":");
      !(colon && args[2][1..colon] in {"From:", "To:", "Subject:"}) && return args;
    endif
    let from = 0;
    let to = 0;
    let subject = " ";
    const blank = "" in {@args, ""};
    let newhdr = {};
    for line in (args[start..blank - 1])
      if (index(line, "Date:") == 1)
        date && player:notify("Warning: two dates?");
        date = $time_utils:from_ctime(line[6..$]);
      elseif (index(line, "From:") == 1)
        from && player:notify("Warning: two from-lines?");
        from = $string_utils:triml(line[6..$]);
      elseif (index(line, "To:") == 1)
        to && player:notify("Warning: two to-lines?");
        to = $string_utils:triml(line[4..$]);
      elseif (index(line, "Subject:") == 1)
        subject = $string_utils:triml(line[9..$]);
      else
        newhdr = {@newhdr, line};
      endif
    endfor
    from || player:notify("Warning: no from-line.");
    to || player:notify("Warning: no to-line.");
    return {date, from, to, subject, @newhdr, @args[blank..$]};
  endmethod

  method to_text owner: HACKER
    ":to_text(@msg) => message in text form (suitable for printing)";
    const subject = args[4] == " " ? {} | {"Subject:  " + args[4]};
    return {"Date:     " + player:ctime(args[1]), "From:     " + args[2], "To:       " + args[3], @subject, @args[5..$]};
  endmethod

  method "is_readable_by is_writable_by is_usable_by" owner: HACKER
    "Apply folder access rules, or player ownership rules for reading and writing.";
    const what = args[1];
    $object_utils:isa(what, $mail_recipient) && return what:(verb)(@listdelete(args, 1));
    return verb == "is_usable_by" || $perm_utils:controls(args[2], what);
  endmethod

  method reserved_pattern owner: HACKER
    ":reserved_pattern(string) => the matching reserved-pattern entry, or 0.";
    const string = args[1];
    for p in (this.reserved_patterns)
      match(string, p[1]) && return p;
    endfor
    return 0;
  endmethod

  method is_recipient owner: HACKER
    "Return whether an object inherits a supported player or mailing-list recipient class.";
    const what = args[1];
    valid(what) || return false;
    const ances = $object_utils:ancestors(what);
    return $mail_recipient_class in ances != 0 || $mail_recipient in ances != 0;
  endmethod

  method keep_message_seq owner: #2
    "Mark the selected messages as immune to expiration; an empty sequence clears all marks.";
    set_task_perms(caller_perms());
    const msg_seq = args[1];
    if (!msg_seq)
      caller.messages_kept = {};
      return 1;
    endif
    const prev_kept = caller.messages_kept;
    const new_kept = $seq_utils:union(prev_kept, msg_seq);
    caller.messages_kept = new_kept;
    const added = $seq_utils:intersection(new_kept, $seq_utils:complement(prev_kept));
    added || return "";
    let nums = {};
    let start = 0;
    for a in (added)
      start = !start;
      nums = {@nums, start ? caller:messages_in_seq(a)[1] | caller:messages_in_seq(a - 1)[1] + 1};
    endfor
    return $seq_utils:tostr(nums);
  endmethod

  method "kept_msg_seq unkept_msg_seq" owner: #2
    ":kept_msg_seq([mask])  => msg_seq of messages that are marked kept";
    ":unkept_msg_seq([mask]) => msg_seq of messages that are not marked kept";
    set_task_perms(caller_perms());
    const {?mask = {1}} = args;
    verb == "kept_msg_seq" && return $seq_utils:intersection(mask, caller.messages_kept);
    return $seq_utils:intersection(mask, $seq_utils:range(1, caller:length_all_msgs()), $seq_utils:complement(caller.messages_kept));
  endmethod

  method msg_seq_to_msg_num_string owner: #2
    ":msg_seq_to_msg_num_string(msg_seq) => string giving the corresponding message numbers";
    set_task_perms(caller_perms());
    return $seq_utils:tostr($seq_utils:from_list($list_utils:slice(caller:messages_in_seq(args[1]))));
  endmethod

  method msg_seq_to_msg_num_list owner: #2
    ":msg_seq_to_msg_num_list(msg_seq) => list of corresponding message numbers";
    set_task_perms(caller_perms());
    return $list_utils:slice(caller:messages_in_seq(args[1]));
  endmethod

  method send_log_message owner: HACKER
    "send_log_message(perms,from,rcpt-list,hdrs,msg) -- sends while using given permissions for moderation decisions.";
    "Return E_PERM unless called by a wizard.";
    const {perms, from, to, hdrs, msg} = args;
    caller_perms().wizard || return E_PERM;
    const text = $mail_agent:make_message(from, to, hdrs, msg);
    return this:raw_send(text, to, perms);
  endmethod

  method parse_misc_headers owner: HACKER
    ":parse_misc_headers(msg,@extract_names) => {other_headers,bogus_headers,extract_texts,body}";
    "Splits the miscellaneous headers from Date:, From:, To:, and Subject:.";
    const msgtxt = args[1];
    const extract_names = listdelete(args, 1);
    let extract_texts = $list_utils:make(length(extract_names));
    let heads = {};
    let bogus = {};
    const bstart = "" in {@msgtxt, ""};
    for h in (msgtxt[5..bstart - 1])
      const m = match(h, "%([a-z1-9-]+%): +%(.*%)");
      if (!m)
        bogus = {@bogus, h};
        continue;
      endif
      const hname = h[m[3][1][1]..m[3][1][2]];
      const htext = h[m[3][2][1]..m[3][2][2]];
      const i = hname in extract_names;
      i ? (extract_texts[i] = htext) | (heads = {@heads, {hname, htext}});
    endfor
    return {heads, bogus, extract_texts, msgtxt[bstart + 1..$]};
  endmethod

  method resend_message owner: #2
    "resend_message(new_sender,new_rcpts,from,to,hdrs,body)";
    " -- reformats and resends a previously sent message to new recipients.";
    "Return E_PERM if new_sender isn't owned by the caller.";
    "Return {0, @invalid_rcpts} if new_rcpts contains any invalid addresses.  No mail is sent in this case.";
    "Return {1, @actual_rcpts} if successful.";
    let {new_sender, new_rcpts, from, to, hdrs, body} = args;
    if (typeof(hdrs) != TYPE_LIST)
      hdrs = {hdrs, 0};
    elseif (length(hdrs) < 2)
      hdrs = {@hdrs || {""}, 0};
    endif
    hdrs[3..2] = {{"Resent-By", this:name_list(new_sender)}, {"Resent-To", this:name_list(@new_rcpts)}};
    $perm_utils:controls(caller_perms(), new_sender) || return E_PERM;
    const text = $mail_agent:make_message(from, to, hdrs, body);
    return this:raw_send(text, new_rcpts, new_sender);
  endmethod

  method init_for_core owner: #2
    "Reset service bookkeeping during wizard-authorized core extraction.";
    caller_perms().wizard || return;
    this.reserved_patterns = {};
    this.last_mail_time = 0;
    this.time_collisions = {0, 0};
    pass(@args);
  endmethod

  method time owner: HACKER
    "Return the current time. The mail clock is kept in sync with the server clock.";
    return time();
  endmethod

  method set_message_body_by_index owner: #2
    ":set_message_body_by_index(i,newbody)";
    "Replaces the body of the i-th message on the (caller) recipient.";
    set_task_perms(caller_perms());
    const {i, body} = args;
    const bstart = "" in caller.messages[i][2];
    if (bstart)
      caller.messages[i][2][bstart + 1..$] = body;
    else
      caller.messages[i][2][$ + 1..$] = {"", @body};
    endif
  endmethod

  method message_body_by_index owner: #2
    ":message_body_by_index(i)";
    "Return the body of the i-th message on the (caller) recipient.";
    set_task_perms(caller_perms());
    const {i} = args;
    const msg = caller:messages_in_seq({i, i + 1})[1][2];
    const bstart = "" in msg;
    const start = bstart ? bstart + 1 | length(msg) + 1;
    return msg[start..$];
  endmethod

  method parse_address owner: #2
    "parse_address(address) => {userid, site}. A missing site is returned blank.";
    const address = args[1];
    const at = index(address, "@");
    return at ? {address[1..at - 1], address[at + 1..$]} | {address, ""};
  endmethod

  method local_domain owner: #2
    "local_domain(site) => the local domain for a site, or E_INVARG if the site is unusable.";
    let site = args[1];
    index(site, "@") || index(site, "%") && return E_INVARG;
    match(site, "^[0-9.]+$") && return E_INVARG;
    !site && return "";
    let dot = rindex(site, ".");
    if (!dot)
      site = this.site;
      dot = rindex(site, ".");
    endif
    !dot && return site;
    const second = rindex(site[1..dot - 1], ".");
    second || return site;
    let domain = site[second + 1..$];
    site = site[1..second - 1];
    while (site && domain in this.large_domains)
      dot = rindex(site, ".");
      !dot && return tostr(site, ".", domain);
      domain = tostr(site[dot + 1..$], ".", domain);
      site = site[1..dot - 1];
    endwhile
    return domain;
  endmethod

  method invalid_email_address owner: #2
    "invalid_email_address(address) => reason string, or blank when the address looks valid.";
    const address = args[1];
    !address && return "no email address supplied";
    const at = rindex(address, "@");
    at || return "'" + address + "' doesn't look like a valid internet email address";
    const name = address[1..at - 1];
    const host = address[at + 1..$];
    if (match(name, "^in%%") || match(name, "^smtp%%"))
      return tostr("'", name, "' doesn't look like a valid username (try removing the 'in%' or 'smtp%')");
    endif
    match(host, this.valid_host_regexp) || return tostr("'", host, "' doesn't look like a valid internet host");
    match(name, this.valid_email_regexp) || return tostr("'", name, "' doesn't look like a valid user name for internet mail");
    return "";
  endmethod

  method email_will_fail owner: #2
    "email_will_fail(address[, display?]) => reason string, or 0 when the address is usable locally.";
    const {email, ?display = 0} = args;
    const reason = this:invalid_email_address(email);
    reason && display && player:tell("Invalid email address: ", reason);
    return reason;
  endmethod

  method _sort_messages owner: #2
    "Sort caller messages by date in one transaction; return their old indexes in the new order.";
    "Renumber, remap kept marks, discard undo positions, and update date metadata.";
    set_task_perms(caller_perms());
    const messages = caller.messages;
    const order = sort({ i for i in [1..length(messages)] }, { message[2][1] for message in (messages) });
    const kept = caller.messages_kept;
    let new_kept = {};
    for position in [1..length(order)]
      $seq_utils:contains(kept, order[position]) && (new_kept = $seq_utils:add(new_kept, position, position));
    endfor
    caller.messages = { {index, messages[order[index]][2]} for index in [1..length(order)] };
    caller.messages_kept = new_kept;
    caller.messages_going = {};
    caller.last_msg_date = order ? messages[order[$]][2][1] | 0;
    caller.last_used_time = time();
    return order;
  endmethod
endobject
