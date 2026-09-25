object GUEST_LOG [
  import_export_id -> "guest_log"
]
  name: "Guest Log"
  parent: ROOT_CLASS
  owner: #2

  property connections (owner: #2, flags: "") = {};
  property max_entries (owner: #2, flags: "") = 511;

  override aliases (owner: #2, flags: "rc") = {"Guest Log"};
  override object_size (owner: HACKER, flags: "r") = {3738, 1084848672};

  method enter owner: #2
    "Prepend {guest, is_login, timestamp, host}; only descendants of $guest can append.";
    $object_utils:isa(caller, $guest) || return E_PERM;
    const limit = max(0, this.max_entries);
    this.connections = limit ? {{caller, @args}, @this.connections[1..min($, limit - 1)]} | {};
  endmethod

  method last owner: #2
    "Print up to n log entries, optionally filtered by guest; zero means all retained entries.";
    "Wizard-only. Budget yields commit; the report uses a captured log and caller authority.";
    set_task_perms(caller_perms());
    caller_perms().wizard || return player:notify("Sorry.");
    const {?count = 0, ?guests = {}} = args;
    const history = this.connections;
    const limit = count ? min(max(0, count), length(history)) | length(history);
    let pending = [];
    let listing = {};
    for entry in (history[1..limit])
      const {guest, is_login, timestamp, host} = entry;
      if (guests && !(guest in guests))
        continue;
      endif
      const position = `pending[guest] ! E_RANGE => 0';
      if (is_login && position)
        listing[position][3] = timestamp;
        pending = mapdelete(pending, guest);
      elseif (is_login)
        const idle = `idle_seconds(guest) ! E_INVARG => -1';
        listing = {@listing, {guest, host, timestamp, idle < 0 ? 1 | -idle}};
      else
        listing = {@listing, {guest, host, 0, timestamp}};
        pending[guest] = length(listing);
      endif
      $command_utils:suspend_if_needed(0);
    endfor
    const strings = $string_utils;
    player:notify(strings:left(strings:left(strings:left("Guest", 20) + "Connected", 36) + "Idle/Disconn.", 52) + "From");
    player:notify(strings:left(strings:left(strings:left("-----", 20) + "---------", 36) + "-------------", 52) + "----");
    for row in (listing)
      let connected = "earlier";
      if (row[3])
        const stamp = ctime(row[3]);
        connected = stamp[1..3] + stamp[9..19];
      endif
      let disconnected = "  " + strings:from_seconds(-(row[4]));
      if (row[4] > 0)
        const stamp = ctime(row[4]);
        disconnected = stamp[1..3] + stamp[9..19];
      endif
      const name = valid(row[1]) ? strsub(row[1].name, "uest", ".") | "recycled";
      player:notify(strings:left(strings:left(strings:right(tostr(name, " (", row[1], ")  "), -20) + connected, 36) + disconnected, 52) + row[2]);
      $command_utils:suspend_if_needed(0);
    endfor
  endmethod

  method init_for_core owner: #2
    "Clear private visitor history during wizard-controlled extraction.";
    caller_perms().wizard || return E_PERM;
    pass(@args);
    this.connections = {};
  endmethod

  method find owner: #2
    "Return the host for a guest at a timestamp, 0 while disconnected, or E_NACC before retained history.";
    set_task_perms(caller_perms());
    caller_perms().wizard || raise(E_PERM);
    const {who, when} = args;
    let host = who in connected_players() ? $string_utils:connection_hostname(who.last_connect_place) | 0;
    for entry in (this.connections)
      entry[3] < when && return host;
      if (entry[1] != who)
        continue;
      endif
      if (entry[2])
        entry[3] == when && return entry[4];
        host = 0;
      else
        entry[3] == when && return 0;
        host = entry[4];
      endif
    endfor
    return E_NACC;
  endmethod
endobject
