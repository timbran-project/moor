object DISCORD_BRIDGE [
  import_export_id -> "discord_bridge",
  import_export_hierarchy -> {"integrations"}
]
  name: "Discord Bridge"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property api_base (owner: ARCH_WIZARD, flags: "") = "https://discord.com/api/v10";
  property backlog_seconds (owner: ARCH_WIZARD, flags: "") = 300;
  property batch_seconds (owner: ARCH_WIZARD, flags: "") = 5;
  property bot_token (owner: ARCH_WIZARD, flags: "") = "";
  property channel_id (owner: ARCH_WIZARD, flags: "") = "";
  property channel_members (owner: ARCH_WIZARD, flags: "") = [];
  property cursor (owner: ARCH_WIZARD, flags: "") = "";
  property enabled (owner: ARCH_WIZARD, flags: "") = false;
  property flush_schedule (owner: ARCH_WIZARD, flags: "") = 0;
  property guild_id (owner: ARCH_WIZARD, flags: "") = "";
  property guild_lookups (owner: ARCH_WIZARD, flags: "") = [];
  property guild_names (owner: ARCH_WIZARD, flags: "") = [];
  property inbound (owner: ARCH_WIZARD, flags: "") = {};
  property inbound_per_minute (owner: ARCH_WIZARD, flags: "") = 20;
  property last_error (owner: ARCH_WIZARD, flags: "") = [];
  property lookup_seconds (owner: ARCH_WIZARD, flags: "") = 300;
  property max_length (owner: ARCH_WIZARD, flags: "") = 400;
  property member_seconds (owner: ARCH_WIZARD, flags: "") = 7776000;
  property outbox (owner: ARCH_WIZARD, flags: "") = {};
  property poll_schedule (owner: ARCH_WIZARD, flags: "") = 0;
  property poll_seconds (owner: ARCH_WIZARD, flags: "") = 10;
  property presence (owner: ARCH_WIZARD, flags: "") = [];
  property presence_quiet_seconds (owner: ARCH_WIZARD, flags: "") = 600;
  property speakers (owner: ARCH_WIZARD, flags: "") = {};
  property transport (owner: ARCH_WIZARD, flags: "") = #-1;
  property webhook_url (owner: ARCH_WIZARD, flags: "") = "";
  property world_name (owner: ARCH_WIZARD, flags: "") = "the MOO";

  override description (owner: ARCH_WIZARD, flags: "rc") = "Relays what Discord speakers hear, and who arrives and leaves, to a Discord channel through its webhook, and speaks the channel's messages through the speakers. Uses the curl worker: posts go to the channel webhook and the bot reads the channel by polling.";

  method configure owner: ARCH_WIZARD
    "Set the channel's webhook, the bot token and the channel id, then start polling and listening for presence.";
    caller_perms().wizard || raise(E_PERM);
    const {webhook_url, bot_token, channel_id, ?world_name = this.world_name} = args;
    typeof(webhook_url) == TYPE_STR && webhook_url:starts_with("https://") || raise(E_INVARG, "The webhook URL must be https.");
    typeof(bot_token) == TYPE_STR && length(bot_token) >= 32 || raise(E_INVARG, "The bot token looks too short.");
    typeof(channel_id) == TYPE_STR && pcre_match(channel_id, "^[0-9]{1,20}$") || raise(E_INVARG, "The channel id must be digits.");
    typeof(world_name) == TYPE_STR && length(world_name) || raise(E_INVARG);
    this.webhook_url = webhook_url;
    this.bot_token = bot_token;
    if (channel_id != this.channel_id)
      this.cursor = "";
      this.guild_id = "";
      this.guild_names = [];
      this.guild_lookups = [];
    endif
    this.channel_id = channel_id;
    this.world_name = world_name;
    this.last_error = [];
    this in $presence_listeners || ($presence_listeners = {@$presence_listeners, this});
    this.enabled = true;
    schedule_stop(this.poll_schedule);
    this.poll_schedule = schedule_every(this, "_poll", this.poll_seconds, {}, ["pass_elapsed" -> false, "jitter" -> 1]);
    return true;
  endmethod

  method disable owner: ARCH_WIZARD
    "Stop relaying in both directions; configuration is kept.";
    caller_perms().wizard || raise(E_PERM);
    this.enabled = false;
    schedule_stop(this.poll_schedule);
    this.poll_schedule = 0;
    $presence_listeners = setremove($presence_listeners, this);
    return true;
  endmethod

  method status owner: ARCH_WIZARD
    "Report whether the bridge is relaying and polling, and the last failure since it was configured.";
    caller_perms().wizard || raise(E_PERM);
    return ["enabled" -> this.enabled, "polling" -> schedule_valid(this.poll_schedule), "channel_id" -> this.channel_id, "speakers" -> this.speakers, "cursor" -> this.cursor, "queued" -> length(this.outbox), "last_error" -> this.last_error];
  endmethod

  method add_speaker owner: ARCH_WIZARD
    "Let a speaker relay what it hears and speak what the channel says.";
    caller_perms().wizard || raise(E_PERM);
    const {speaker} = args;
    valid(speaker) && isa(speaker, $discord_speaker) || raise(E_INVARG);
    this.speakers = setadd(this.speakers, speaker);
    return true;
  endmethod

  method remove_speaker owner: ARCH_WIZARD
    "Stop a speaker relaying or speaking.";
    caller_perms().wizard || raise(E_PERM);
    const {speaker} = args;
    this.speakers = setremove(this.speakers, speaker);
    return true;
  endmethod

  method relay owner: ARCH_WIZARD
    "Queue a line a registered speaker heard; a linked actor's name becomes a mention of their Discord account.";
    const {speaker, actor, text} = args;
    caller == speaker && speaker in this.speakers || raise(E_PERM);
    this.enabled || return false;
    const mention = this:_mention(actor);
    const name = length(mention) ? actor:name() | "";
    if (length(mention) && text:starts_with(name))
      const rest = text[length(name) + 1..$];
      this:_queue(rest, rest:starts_with(" ") ? mention + " " | mention);
    else
      this:_queue(text);
    endif
    return true;
  endmethod

  method presence_event owner: ARCH_WIZARD
    "Post a new player, or an arrival once per quiet period. Departures are never posted: a lost connection is not a departure.";
    caller == #0 || caller_perms().wizard || raise(E_PERM);
    const {user, kind} = args;
    this.enabled && valid(user) && is_player(user) || return false;
    kind in {'created, 'connected} || raise(E_INVARG);
    const key = tostr(user, " ", kind);
    const last = `this.presence[key] ! E_RANGE => 0';
    kind != 'created && time() - last < this.presence_quiet_seconds && return false;
    "Entries past the quiet period no longer hold anything back, so they are dropped.";
    let presence = [key -> time()];
    for other in (mapkeys(this.presence))
      time() - this.presence[other] < this.presence_quiet_seconds && (presence[other] = this.presence[other]);
    endfor
    this.presence = presence;
    const name = user:name();
    const text = kind == 'created ? "A new guest, " + name + ", has arrived for the first time." | name + " has arrived at " + this.world_name + ".";
    this:_queue(text);
    return true;
  endmethod

  method _poll owner: ARCH_WIZARD
    "Fetch the channel's new messages and speak them; the first poll only finds where the channel is.";
    caller_perms().wizard || raise(E_PERM);
    this.enabled && length(this.channel_id) || return 0;
    const first = !length(this.cursor);
    const query = first ? "?limit=1" | "?limit=50&after=" + this.cursor;
    let response = {};
    try
      response = this:_request("GET", this.api_base + "/channels/" + this.channel_id + "/messages" + query, "", {{"Authorization", "Bot " + this.bot_token}});
    except error (ANY)
      this:_report(tostr("Discord bridge poll failed: ", toliteral(error[1])));
      return 0;
    endtry
    const status = `response[1] ! ANY => 0';
    if (status in {401, 403})
      this:_report(tostr("Discord bridge stopped polling: the channel refused the bot token with HTTP ", status));
      schedule_stop(this.poll_schedule);
      this.poll_schedule = 0;
      return 0;
    endif
    "A rate limit or an outage is retried on the next poll.";
    status == 200 || return 0;
    const messages = `parse_json(response[3]) ! ANY => {}';
    typeof(messages) == TYPE_LIST || return 0;
    "An empty channel has no history to skip, so everything after it is new.";
    first && !length(messages) && (this.cursor = "0");
    const ids = { `message["id"] ! ANY => "0"' for message in (messages) };
    let spoken = 0;
    let stale = 0;
    for message in (sort(messages, ids, true))
      const id = `message["id"] ! ANY => ""';
      if (typeof(id) == TYPE_STR && pcre_match(id, "^[0-9]{1,20}$"))
        if (!first && this.backlog_seconds > 0 && time() - this:_posted_at(id) > this.backlog_seconds)
          stale = stale + 1;
        elseif (!first)
          const result = this:_receive(message);
          "The rate limit leaves the cursor here, so the next poll speaks this message.";
          if (result < 0)
            break;
          endif
          spoken = spoken + result;
        endif
        this.cursor = id;
      endif
    endfor
    stale && server_log(tostr("Discord bridge skipped ", stale, " channel messages older than ", this.backlog_seconds, " seconds"));
    return spoken;
  endmethod

  method _posted_at owner: ARCH_WIZARD
    "The time a Discord id was made, in seconds, from the milliseconds since 2015 in its upper bits.";
    caller == this || raise(E_PERM);
    const {id} = args;
    return (toint(id) / 4194304 + 1420070400000) / 1000;
  endmethod

  method _receive owner: ARCH_WIZARD
    "Speak one channel message in every speaker's room, returning 1, or 0 for bots, webhooks and system messages, or -1 when over the rate limit.";
    caller == this || raise(E_PERM);
    const {message} = args;
    typeof(message) == TYPE_MAP || return 0;
    "Webhook posts include the bridge's own, so skipping them keeps the bridge from echoing itself.";
    maphaskey(message, "webhook_id") && return 0;
    `message["type"] ! E_RANGE => -1' in {0, 19} || return 0;
    const author = `message["author"] ! E_RANGE => []';
    typeof(author) == TYPE_MAP || return 0;
    `author["bot"] ! E_RANGE => false' == true && return 0;
    const discord_id = `author["id"] ! E_RANGE => ""';
    const global_name = `author["global_name"] ! E_RANGE => ""';
    const display_name = this:_clean(typeof(global_name) == TYPE_STR && length(global_name) ? global_name | `author["username"] ! E_RANGE => ""', 64);
    const content = this:_markup_to_text(`message["content"] ! E_RANGE => ""', `message["mentions"] ! E_RANGE => {}');
    const text = this:_clean(content, this.max_length);
    typeof(discord_id) == TYPE_STR && length(display_name) && length(text) || return 0;
    this:_admit() || return -1;
    "Whoever posts here is a member of the channel's server, so a mention of them will resolve.";
    let members = [discord_id -> time()];
    const seen = this:_members();
    for other in (mapkeys(seen))
      time() - seen[other] < this.member_seconds && (members[other] = seen[other]);
    endfor
    this.channel_members = members;
    const linked = $login:find_by_oauth2("discord", discord_id);
    const linked_player = valid(linked) && is_player(linked) ? linked | #-1;
    for speaker in (this.speakers)
      valid(speaker) && `speaker:speak(linked_player, display_name, text) ! ANY';
    endfor
    return 1;
  endmethod

  method _mention owner: ARCH_WIZARD
    "A Discord mention for an actor whose linked account has posted in the channel, or the empty string.";
    caller == this || raise(E_PERM);
    const {actor} = args;
    typeof(actor) == TYPE_OBJ && valid(actor) && is_player(actor) || return "";
    for identity in (`actor.oauth2_identities ! ANY => {}')
      if (typeof(identity) == TYPE_LIST && length(identity) == 2 && identity[1] == "discord" && maphaskey(this:_members(), identity[2]))
        return "<@" + identity[2] + ">";
      endif
    endfor
    return "";
  endmethod

  method _markup_to_text owner: ARCH_WIZARD
    "Replace Discord's markup for users, roles, channels, emoji, commands and times in a channel message with readable text.";
    caller == this || raise(E_PERM);
    const {content, mentions} = args;
    typeof(content) == TYPE_STR || return "";
    let users = [];
    for user in (typeof(mentions) == TYPE_LIST ? mentions | {})
      const id = `user["id"] ! ANY => ""';
      const global_name = `user["global_name"] ! ANY => ""';
      const name = typeof(global_name) == TYPE_STR && length(global_name) ? global_name | `user["username"] ! ANY => ""';
      typeof(id) == TYPE_STR && typeof(name) == TYPE_STR && length(name) && (users[id] = "@" + name);
    endfor
    let result = "";
    let last = 0;
    for found in (pcre_match(content, "<(@!?|@&|#|a?:[A-Za-z0-9_~]+:|/[^:<>]+:|t:)([0-9]{1,20})(?::[tTdDfFR])?>"))
      const {start, finish} = found["0"]["position"];
      result = result + content[last + 1..start - 1] + this:_markup_name(found["1"]["match"], found["2"]["match"], users);
      last = finish;
    endfor
    return result + content[last + 1..$];
  endmethod

  method _markup_name owner: ARCH_WIZARD
    "Readable text for one piece of Discord markup, given its kind and id.";
    caller == this || raise(E_PERM);
    const {kind, id, users} = args;
    if (kind in {"@", "@!"})
      const linked = `$login:find_by_oauth2("discord", id) ! ANY => #-1';
      return valid(linked) && is_player(linked) ? linked:name() | `users[id] ! E_RANGE => "@someone"';
    elseif (kind == "@&")
      const role = this:_guild_name("role", id);
      return "@" + (length(role) ? role | "role");
    elseif (kind == "#")
      const channel = this:_guild_name("channel", id);
      return "#" + (length(channel) ? channel | "channel");
    elseif (kind == "t:")
      return `ctime(toint(id)) ! ANY => "a time"';
    elseif (kind[1] == "/")
      return kind[1..$ - 1];
    endif
    "A custom emoji, animated or not, reads as its :name:.";
    return kind[1] == "a" ? kind[2..$] | kind;
  endmethod

  method _guild_name owner: ARCH_WIZARD
    "The name of a role or channel in the channel's server, fetching the server's list when the id is new, at most once per lookup period.";
    caller == this || raise(E_PERM);
    const {kind, id} = args;
    const key = kind + ":" + id;
    maphaskey(this.guild_names, key) && return this.guild_names[key];
    const now = time();
    now - `this.guild_lookups[kind] ! E_RANGE => 0' < this.lookup_seconds && return "";
    this.guild_lookups[kind] = now;
    if (!length(this.guild_id))
      const guild_id = `this:_api_get("/channels/" + this.channel_id)["guild_id"] ! ANY => ""';
      typeof(guild_id) == TYPE_STR && pcre_match(guild_id, "^[0-9]{1,20}$") || return "";
      this.guild_id = guild_id;
    endif
    const items = this:_api_get("/guilds/" + this.guild_id + (kind == "role" ? "/roles" | "/channels"));
    typeof(items) == TYPE_LIST || return "";
    let names = [];
    for other in (mapkeys(this.guild_names))
      other:starts_with(kind + ":") || (names[other] = this.guild_names[other]);
    endfor
    for item in (items)
      const item_id = `item["id"] ! ANY => ""';
      const name = `item["name"] ! ANY => ""';
      typeof(item_id) == TYPE_STR && typeof(name) == TYPE_STR && length(name) && (names[kind + ":" + item_id] = name);
    endfor
    this.guild_names = names;
    return `names[key] ! E_RANGE => ""';
  endmethod

  method _api_get owner: ARCH_WIZARD
    "Read a path of Discord's API as the bot, returning the parsed body, or 0 when the read fails.";
    caller == this || raise(E_PERM);
    const {path} = args;
    try
      const response = this:_request("GET", this.api_base + path, "", {{"Authorization", "Bot " + this.bot_token}});
      response[1] == 200 || return 0;
      return parse_json(response[3]);
    except error (ANY)
      this:_report(tostr("Discord bridge read of ", path, " failed: ", toliteral(error[1])));
      return 0;
    endtry
  endmethod

  method _report owner: ARCH_WIZARD
    "Log a failure and keep it as the last error for status.";
    caller == this || raise(E_PERM);
    const {text} = args;
    server_log(text);
    this.last_error = ["time" -> time(), "message" -> text];
  endmethod

  method _members owner: ARCH_WIZARD
    "Channel members as a map of Discord id to when they last posted; an older list of ids counts as seen now.";
    caller == this || raise(E_PERM);
    const members = this.channel_members;
    typeof(members) == TYPE_MAP && return members;
    let converted = [];
    for id in (typeof(members) == TYPE_LIST ? members | {})
      typeof(id) == TYPE_STR && (converted[id] = time());
    endfor
    return converted;
  endmethod

  method _request owner: ARCH_WIZARD
    "Make one HTTP request, or ask the test transport when one is set.";
    caller == this || raise(E_PERM);
    const {method, url, body, headers} = args;
    valid(this.transport) && return this.transport:request(method, url, body, headers);
    return $http:request(method, url, body, headers, ["max_bytes" -> 262144, "timeout_seconds" -> 10.0]);
  endmethod

  method _admit owner: ARCH_WIZARD
    "Count an inbound message against the per-minute limit.";
    caller == this || raise(E_PERM);
    const now = time();
    const recent = { stamp for stamp in (this.inbound) if now - stamp < 60 };
    length(recent) < this.inbound_per_minute || return false;
    this.inbound = {@recent, now};
    return true;
  endmethod

  method _clean owner: ARCH_WIZARD
    "Drop control characters and cut to a length, marking the cut.";
    caller == this || raise(E_PERM);
    const {value, limit} = args;
    typeof(value) == TYPE_STR || return "";
    const text = pcre_replace(value, "s/[\\x00-\\x1f\\x7f]+/ /g"):trim();
    return length(text) > limit ? text[1..limit - 1] + "…" | text;
  endmethod

  method _escape owner: ARCH_WIZARD
    "Escape Discord markdown so hotel text shows as written.";
    caller == this || raise(E_PERM);
    const {text} = args;
    return pcre_replace(text, "s/([\\\\*_~`|>#\\[\\]()-])/\\$1/g");
  endmethod

  method _queue owner: ARCH_WIZARD
    "Add a line to the outbox, after an optional mention, and make sure a flush is coming.";
    caller == this || raise(E_PERM);
    const {text, ?mention = ""} = args;
    const line = mention + this:_escape(this:_clean(text, this.max_length));
    length(line) || return;
    this.outbox = {@this.outbox, line};
    schedule_valid(this.flush_schedule) && return;
    this.flush_schedule = schedule_at(this, "_flush", time() + this.batch_seconds, {}, ["adaptive" -> false, "pass_elapsed" -> false]);
  endmethod

  method _flush owner: ARCH_WIZARD
    "Post the outbox under the world's name, packing lines into as few posts as Discord allows.";
    caller_perms().wizard || raise(E_PERM);
    const lines = this.outbox;
    this.outbox = {};
    this.flush_schedule = 0;
    let posts = {};
    for line in (lines)
      if (length(posts) && length(posts[$]) + 1 + length(line) <= 1900)
        posts[$] = posts[$] + "\n" + line;
      else
        posts = {@posts, line};
      endif
    endfor
    for post in (posts)
      this:_post(post);
    endfor
    return length(posts);
  endmethod

  method _post owner: ARCH_WIZARD
    "Send one post to the channel webhook, retrying once after a rate limit.";
    caller == this || raise(E_PERM);
    const {content} = args;
    const username = this.world_name[1..min(80, length(this.world_name))];
    const body = generate_json(["username" -> username, "content" -> content, "allowed_mentions" -> ["parse" -> {}]]);
    for attempt in [1..2]
      let response = {};
      try
        response = this:_request("POST", this.webhook_url, body, {{"Content-Type", "application/json"}});
      except error (ANY)
        this:_report(tostr("Discord bridge post failed: ", toliteral(error[1])));
        return false;
      endtry
      const status = `response[1] ! ANY => 0';
      status >= 200 && status < 300 && return true;
      if (status == 429 && attempt == 1)
        const wait = `parse_json(response[3])["retry_after"] ! ANY => 1';
        suspend(min(10, max(1, toint(wait))));
        continue;
      endif
      this:_report(tostr("Discord bridge post refused with HTTP ", status));
      return false;
    endfor
    return false;
  endmethod
endobject
