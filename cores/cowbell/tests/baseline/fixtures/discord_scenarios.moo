object DISCORD_SCENARIOS [
  import_export_id -> "discord_scenarios"
]
  name: "Discord Bridge Scenarios"
  parent: core::ROOT
  owner: core::ARCH_WIZARD
  readable: true

  property channel (owner: core::ARCH_WIZARD, flags: "r") = {};
  property heard (owner: core::ARCH_WIZARD, flags: "r") = {};
  property posts (owner: core::ARCH_WIZARD, flags: "r") = {};
  property read_status (owner: core::ARCH_WIZARD, flags: "r") = 200;
  property reads (owner: core::ARCH_WIZARD, flags: "r") = {};
  property responses (owner: core::ARCH_WIZARD, flags: "r") = [];

  method request owner: core::ARCH_WIZARD
    "Stand in for the curl worker: record webhook posts and answer channel reads.";
    const {method, url, body, headers} = args;
    if (method == "POST")
      this.posts = {@this.posts, parse_json(body)};
      return {204, {}, ""};
    endif
    this.reads = {@this.reads, {url, headers}};
    this.read_status == 200 || return {this.read_status, {}, ""};
    maphaskey(this.responses, url) && return {200, {}, generate_json(this.responses[url])};
    return {200, {}, generate_json(this.channel)};
  endmethod

  method tell owner: core::ARCH_WIZARD
    "Stand in for a player in the room.";
    const {event} = args;
    this.heard = {@this.heard, $document:render(event:resolve(this), 'text_plain)['body]};
  endmethod

  method _setup owner: core::ARCH_WIZARD
    "Point the bridge at this fixture, returning what it replaced.";
    const bridge = $discord_bridge;
    let saved = ["listeners" -> $presence_listeners, "location" -> this.location];
    for key in ({"webhook_url", "bot_token", "channel_id", "cursor", "world_name", "enabled", "transport", "speakers", "outbox", "presence", "inbound", "channel_members", "guild_id", "guild_names", "guild_lookups", "backlog_seconds", "last_error", "poll_schedule"})
      saved[key] = bridge.(key);
    endfor
    bridge:configure("https://discord.example/api/webhooks/1/token", "bot-token-0123456789abcdef0123456789", "5", "Test World");
    bridge.transport = this;
    bridge.cursor = "";
    bridge.outbox = {};
    bridge.presence = [];
    bridge.inbound = {};
    bridge.channel_members = [];
    "The scenarios use short ids, which Discord would have made in 2015.";
    bridge.backlog_seconds = 0;
    bridge.speakers = {};
    this.channel = {};
    this.responses = [];
    this.read_status = 200;
    this.posts = {};
    this.reads = {};
    this.heard = {};
    return saved;
  endmethod

  method _teardown owner: core::ARCH_WIZARD
    "Restore the bridge and drop its schedules.";
    const {saved} = args;
    const bridge = $discord_bridge;
    schedule_stop(bridge.poll_schedule);
    schedule_stop(bridge.flush_schedule);
    bridge.flush_schedule = 0;
    for key in ({"webhook_url", "bot_token", "channel_id", "cursor", "world_name", "enabled", "transport", "speakers", "outbox", "presence", "inbound", "channel_members", "guild_id", "guild_names", "guild_lookups", "backlog_seconds", "last_error", "poll_schedule"})
      bridge.(key) = saved[key];
    endfor
    $presence_listeners = saved["listeners"];
    move(this, saved["location"]);
  endmethod

  method _message owner: core::ARCH_WIZARD
    "A channel message as Discord's API returns it.";
    const {id, author_id, name, text, ?extra = []} = args;
    let message = ["id" -> id, "type" -> 0, "channel_id" -> "5", "content" -> text, "author" -> ["id" -> author_id, "username" -> name, "global_name" -> name, "avatar" -> "abc123"]];
    for key in (mapkeys(extra))
      message[key] = extra[key];
    endfor
    return message;
  endmethod

  method test_room_events_are_batched_into_posts owner: core::ARCH_WIZARD
    "What the room announces goes out under the world's name, packed into one post, markdown escaped and mentions off.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    const actor = create($actor);
    try
      actor.name = "Henri";
      move(speaker, room);
      $discord_bridge:add_speaker(speaker);
      room:announce($event:mk_say(actor, "Henri says, \"*hello* @everyone\"."));
      room:announce($event:mk_emote(actor, "Henri waves."));
      $test_utils:assert_true(schedule_valid($discord_bridge.flush_schedule), "a flush is scheduled");
      $test_utils:assert_eq($discord_bridge:_flush(), 1, "two lines share a post");
      const post = this.posts[1];
      $test_utils:assert_eq(post["username"], "Test World", "posted under the world's name");
      $test_utils:assert_false(maphaskey(post, "avatar_url"), "with the webhook's own avatar");
      $test_utils:assert_eq(post["content"], "Henri says, \"\\*hello\\* @everyone\".\nHenri waves.", "markdown escaped");
      $test_utils:assert_eq(post["allowed_mentions"], ["parse" -> {}], "no mentions are parsed");
      $test_utils:assert_eq(length(speaker.recent), 2, "the speaker keeps what it relayed");
      $discord_bridge:remove_speaker(speaker);
      room:announce($event:mk_say(actor, "Henri says, \"gone\"."));
      $test_utils:assert_eq($discord_bridge.outbox, {}, "an unregistered speaker relays nothing");
    finally
      this:_teardown(saved);
      recycle(actor);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_channel_messages_reach_the_room owner: core::ARCH_WIZARD
    "Polling speaks new channel messages in order, cleaned and marked as from Discord, and skips bots, webhooks and history.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    try
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      $test_utils:assert_true(schedule_valid($discord_bridge.poll_schedule), "configuring schedules polling");
      $discord_bridge:_poll();
      $test_utils:assert_eq($discord_bridge.cursor, "0", "an empty channel has no history to skip");
      $discord_bridge.cursor = "";
      this.reads = {};
      this.channel = {this:_message("100", "42", "alice", "from before the bridge")};
      $test_utils:assert_eq($discord_bridge:_poll(), 0, "the first poll only finds the latest message");
      $test_utils:assert_eq($discord_bridge.cursor, "100", "and remembers it");
      $test_utils:assert_eq(this.reads[1][1], "https://discord.com/api/v10/channels/5/messages?limit=1", "reads the channel");
      $test_utils:assert_eq(this.reads[1][2], {{"Authorization", "Bot bot-token-0123456789abcdef0123456789"}}, "as the bot");
      const escape = parse_json("\"\\u001b\"");
      "Discord lists the newest first.";
      this.channel = {this:_message("1000", "42", "alice", "second"), this:_message("999", "43", "relay", "from a bot", ["author" -> ["id" -> "43", "username" -> "relay", "bot" -> true]]), this:_message("998", "44", "hook", "from a webhook", ["webhook_id" -> "7"]), this:_message("997", "42", "alice", "pinned a message", ["type" -> 6]), this:_message("101", "42", "alice", "hi" + escape + "[31m there")};
      $test_utils:assert_eq($discord_bridge:_poll(), 2, "two messages are spoken");
      $test_utils:assert_eq(this.reads[2][1], "https://discord.com/api/v10/channels/5/messages?limit=50&after=100", "reads after the cursor");
      $test_utils:assert_eq(this.heard, {"Bakelite radio: alice (Discord): hi [31m there", "Bakelite radio: alice (Discord): second"}, "oldest first, control characters removed, marked as from Discord");
      $test_utils:assert_eq($discord_bridge.cursor, "1000", "the cursor moves to the newest");
      $test_utils:assert_eq($discord_bridge.outbox, {}, "the speaker does not relay its own words");
    finally
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_linked_authors_are_named_as_players owner: core::ARCH_WIZARD
    "A linked Discord user speaks under their player's name, and the player appears in Discord as a mention of that user.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    const player_ids = #90102.oauth2_identities;
    const old_name = #90102.name;
    try
      #90102.oauth2_identities = {{"discord", "42"}};
      #90102.name = "Quillon";
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      room:announce($event:mk_say(#90102, #90102:name() + " says, \"early\"."));
      $discord_bridge:_flush();
      $test_utils:assert_eq(this.posts[1]["content"], #90102:name() + " says, \"early\".", "no mention before the account posts in the channel");
      this.posts = {};
      this.heard = {};
      $discord_bridge.cursor = "100";
      this.channel = {this:_message("101", "42", "al", "hello")};
      $discord_bridge:_poll();
      $test_utils:assert_eq(this.heard, {"Bakelite radio: Quillon: hello"}, "named as the player");
      room:announce($event:mk_say(#90102, #90102:name() + " says, \"*hi*\"."));
      $discord_bridge:_flush();
      $test_utils:assert_eq(this.posts[1]["content"], "<@42> says, \"\\*hi\\*\".", "in Discord the player is a mention of their account");
    finally
      #90102.oauth2_identities = player_ids;
      #90102.name = old_name;
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_mentions_in_channel_messages_are_named owner: core::ARCH_WIZARD
    "A mention in a channel message reads as the linked player's name, or as the name Discord gives for the user.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    const player_ids = #90102.oauth2_identities;
    const old_name = #90102.name;
    try
      #90102.oauth2_identities = {{"discord", "42"}};
      #90102.name = "Quillon";
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      $discord_bridge.cursor = "100";
      const mentions = {["id" -> "42", "username" -> "q", "global_name" -> "Q"], ["id" -> "77", "username" -> "bea", "global_name" -> "Bea"]};
      this.channel = {this:_message("101", "43", "alice", "<@42> and <@!77> and <@88> test", ["mentions" -> mentions])};
      $discord_bridge:_poll();
      $test_utils:assert_eq(this.heard, {"Bakelite radio: alice (Discord): Quillon and @Bea and @someone test"}, "mentions are named");
    finally
      #90102.oauth2_identities = player_ids;
      #90102.name = old_name;
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_discord_markup_reads_as_text owner: core::ARCH_WIZARD
    "Roles and channels read by name from the server's lists, fetched once; emoji, commands and times read as text.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    try
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      $discord_bridge.cursor = "100";
      const api = "https://discord.com/api/v10";
      this.responses = [api + "/channels/5" -> ["id" -> "5", "guild_id" -> "9"], api + "/guilds/9/roles" -> {["id" -> "21", "name" -> "Staff"]}, api + "/guilds/9/channels" -> {["id" -> "5", "name" -> "lobby"], ["id" -> "6", "name" -> "ooc"]}];
      this.channel = {this:_message("101", "43", "alice", "Café <@&21> see <#6> <a:wave:31> </look here:7> <t:0:R> <@&22> <#5>")};
      $discord_bridge:_poll();
      $test_utils:assert_eq(this.heard, {"Bakelite radio: alice (Discord): Café @Staff see #ooc :wave: /look here " + ctime(0) + " @role #lobby"}, "markup reads as text");
      $test_utils:assert_eq(length(this.reads), 4, "the channel, its server and each list are read once");
      this.heard = {};
      this.channel = {this:_message("102", "43", "alice", "<@&23>")};
      $discord_bridge:_poll();
      $test_utils:assert_eq(this.heard, {"Bakelite radio: alice (Discord): @role"}, "an unknown role reads generically");
      $test_utils:assert_eq(length(this.reads), 5, "and does not refetch within the lookup period");
    finally
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_rate_limited_messages_wait_for_the_next_poll owner: core::ARCH_WIZARD
    "Messages over the rate limit are spoken by a later poll, and messages older than the backlog are skipped.";
    const saved = this:_setup();
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    const limit = $discord_bridge.inbound_per_minute;
    try
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      $discord_bridge.backlog_seconds = 300;
      $discord_bridge.inbound_per_minute = 1;
      "A Discord id holds the milliseconds since 2015 above its lowest 22 bits.";
      const now = (time() * 1000 - 1420070400000) * 4194304;
      const old = (now / 4194304 - 3600000) * 4194304;
      $discord_bridge.cursor = tostr(old - 1);
      this.channel = {this:_message(tostr(now + 2), "42", "alice", "third"), this:_message(tostr(now + 1), "42", "alice", "second"), this:_message(tostr(old), "42", "alice", "an hour ago")};
      $test_utils:assert_eq($discord_bridge:_poll(), 1, "one message fits the limit");
      $test_utils:assert_eq(this.heard, {"Bakelite radio: alice (Discord): second"}, "the old message is skipped");
      $test_utils:assert_eq($discord_bridge.cursor, tostr(now + 1), "the cursor stops before the refused message");
      $discord_bridge.inbound = {};
      this.channel = {this:_message(tostr(now + 2), "42", "alice", "third")};
      $test_utils:assert_eq($discord_bridge:_poll(), 1, "the next poll speaks it");
      $test_utils:assert_eq(this.reads[$][1], "https://discord.com/api/v10/channels/5/messages?limit=50&after=" + tostr(now + 1), "reading after the last spoken message");
      $test_utils:assert_eq($discord_bridge.cursor, tostr(now + 2), "and moves on");
    finally
      $discord_bridge.inbound_per_minute = limit;
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_a_refused_token_shows_in_status owner: core::ARCH_WIZARD
    "A refused bot token stops polling, status says why, and configuring again clears it.";
    const saved = this:_setup();
    try
      $test_utils:assert_eq($discord_bridge:status()["last_error"], [], "configuring starts with no error");
      $test_utils:assert_true($discord_bridge:status()["polling"], "and polling");
      this.read_status = 401;
      $discord_bridge:_poll();
      const status = $discord_bridge:status();
      $test_utils:assert_false(status["polling"], "a refused token stops polling");
      $test_utils:assert_true(status["enabled"], "posting to the webhook goes on");
      $test_utils:assert_true(index(status["last_error"]["message"], "HTTP 401") > 0, "status says why");
      this.read_status = 200;
      $discord_bridge:configure("https://discord.example/api/webhooks/1/token", "bot-token-0123456789abcdef0123456789", "5", "Test World");
      $test_utils:assert_eq($discord_bridge:status()["last_error"], [], "configuring again clears the error");
      $test_utils:assert_true($discord_bridge:status()["polling"], "and polls again");
    finally
      this:_teardown(saved);
    endtry
    return true;
  endmethod

  method test_old_presence_and_members_are_dropped owner: core::ARCH_WIZARD
    "Presence entries past the quiet period and members unseen for the member period are dropped; a list of members still works.";
    const saved = this:_setup();
    const old_location = #90102.location;
    const room = create($room);
    const speaker = create($discord_speaker);
    speaker.name = "Bakelite radio";
    try
      move(speaker, room);
      move(this, room);
      $discord_bridge:add_speaker(speaker);
      $discord_bridge.presence = ["#1 connected" -> time() - 7200, "#2 connected" -> time()];
      move(#90102, room);
      $discord_bridge:presence_event(#90102, 'connected);
      $test_utils:assert_eq(mapkeys($discord_bridge.presence), {"#2 connected", tostr(#90102, " connected")}, "the old entry is gone");
      $discord_bridge.channel_members = {"7", "8"};
      $discord_bridge.cursor = "100";
      this.channel = {this:_message("101", "9", "alice", "hello")};
      $discord_bridge:_poll();
      $test_utils:assert_eq(mapkeys($discord_bridge.channel_members), {"7", "8", "9"}, "a list of members becomes a map");
      $discord_bridge.channel_members["7"] = time() - 8000000;
      this.channel = {this:_message("102", "9", "alice", "again")};
      $discord_bridge:_poll();
      $test_utils:assert_eq(mapkeys($discord_bridge.channel_members), {"8", "9"}, "a member unseen for 90 days is gone");
    finally
      move(#90102, old_location);
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_a_last_disconnection_tells_no_one owner: core::ARCH_WIZARD
    "A player's last connection closing announces nothing in their room and posts nothing to Discord.";
    const saved = this:_setup();
    const room = create($room);
    const old_location = #90102.location;
    const old_disconnected = #90102.last_disconnected;
    try
      add_property(room, "heard", {}, {$arch_wizard, ""});
      add_verb(room, {$arch_wizard, "rxd", "announce"}, {"this", "none", "this"});
      set_verb_code(room, "announce", {"this.heard = {@this.heard, args};"});
      move(#90102, room);
      $test_utils:assert_eq(`connections(#90102) ! E_INVARG => {}', {}, "the player has no connections");
      $user_disconnected(#90102);
      "Presence listeners run in forked tasks; let any that were started finish.";
      suspend(0.01);
      $test_utils:assert_eq(room.heard, {}, "the room hears nothing");
      $test_utils:assert_eq($discord_bridge.outbox, {}, "nothing is queued for Discord");
      $test_utils:assert_true(#90102.last_disconnected > 0, "the disconnection time is still recorded");
    finally
      move(#90102, old_location);
      #90102.last_disconnected = old_disconnected;
      this:_teardown(saved);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_presence_is_posted_once_per_quiet_period owner: core::ARCH_WIZARD
    "Arrivals in a speaker's room post once per quiet period; departures are never posted.";
    const saved = this:_setup();
    const old_name = #90102.name;
    const old_location = #90102.location;
    const room = create($room);
    const speaker = create($discord_speaker);
    try
      move(speaker, room);
      $discord_bridge:add_speaker(speaker);
      move(#90102, room);
      #90102.name = "Quillon";
      $test_utils:assert_true($discord_bridge:presence_event(#90102, 'connected), "first arrival posts");
      $test_utils:assert_false($discord_bridge:presence_event(#90102, 'connected), "a quick reconnect does not");
      $test_utils:assert_eq(`$discord_bridge:presence_event(#90102, 'disconnected) ! E_INVARG => E_INVARG', E_INVARG, "a departure is not a presence event");
      $discord_bridge:_flush();
      $test_utils:assert_eq(this.posts[1]["username"], "Test World", "posted as the world");
      $test_utils:assert_eq(this.posts[1]["content"], "Quillon has arrived at Test World.", "only the arrival is posted");
    finally
      #90102.name = old_name;
      move(#90102, old_location);
      this:_teardown(saved);
      recycle(speaker);
      recycle(room);
    endtry
    return true;
  endmethod

  method test_arrivals_elsewhere_are_not_posted owner: core::ARCH_WIZARD
    "An arrival in a room without one of the bridge's speakers is not posted; a new player is, wherever they are.";
    const saved = this:_setup();
    const old_name = #90102.name;
    const old_location = #90102.location;
    const lobby = create($room);
    const elsewhere = create($room);
    const speaker = create($discord_speaker);
    try
      move(speaker, lobby);
      $discord_bridge:add_speaker(speaker);
      move(#90102, elsewhere);
      #90102.name = "Quillon";
      $test_utils:assert_false($discord_bridge:presence_event(#90102, 'connected), "an arrival away from the speakers is not posted");
      $test_utils:assert_true($discord_bridge:presence_event(#90102, 'created), "a new player is posted wherever they are");
      $discord_bridge:_flush();
      $test_utils:assert_eq(length(this.posts), 1, "one post");
      $test_utils:assert_eq(this.posts[1]["content"], "A new guest, Quillon, has arrived for the first time.", "only the new player");
    finally
      #90102.name = old_name;
      move(#90102, old_location);
      this:_teardown(saved);
      recycle(speaker);
      recycle(elsewhere);
      recycle(lobby);
    endtry
    return true;
  endmethod

  method test_only_a_player_who_was_away_arrives owner: core::ARCH_WIZARD
    "A connection counts as an arrival only when the player was last here more than the quiet period ago, by their last connection or last disconnection, whichever is later.";
    const old_connected = #90102.last_connected;
    const old_disconnected = #90102.last_disconnected;
    const quiet = $login.connection_quiet_period;
    try
      #90102.last_connected = 0;
      #90102.last_disconnected = 0;
      $test_utils:assert_true(#0:_was_away(#90102), "a player never seen was away");
      #90102.last_connected = time() - quiet - 600;
      #90102.last_disconnected = time() - 60;
      $test_utils:assert_false(#0:_was_away(#90102), "a long session whose connection just dropped was not away");
      #90102.last_connected = time() - 60;
      #90102.last_disconnected = time() - quiet - 600;
      $test_utils:assert_false(#0:_was_away(#90102), "a recent connection was not away");
      #90102.last_connected = time() - quiet - 3600;
      #90102.last_disconnected = time() - quiet - 600;
      $test_utils:assert_true(#0:_was_away(#90102), "gone longer than the quiet period was away");
    finally
      #90102.last_connected = old_connected;
      #90102.last_disconnected = old_disconnected;
    endtry
    return true;
  endmethod
endobject
