// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object HEADLESS_AUTHORITY_RECEIVER
  name: "Authority Delivery Probe"
  parent: EVENT_RECEIVER
  owner: RUNTIME_PROGRAMMER
  readable: true
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_authority_receiver";

  method probe_notify owner: RUNTIME_PROGRAMMER
    "Attempt to send output through an inherited wizard helper to a foreign connection.";
    const {target_connection, message} = args;
    return this:_notify(target_connection, message, false, false, 'text_plain);
  endmethod

  method probe_present owner: RUNTIME_PROGRAMMER
    "Attempt to present output to a different player's connections.";
    const {target_player} = args;
    return this:_present(target_player, "authority-probe", "text/html", "tools", "authority presentation probe", []);
  endmethod

  method probe_event_log owner: RUNTIME_PROGRAMMER
    "Attempt to append output to a different player's history.";
    const {target_player} = args;
    return this:_event_log(target_player, "authority history probe", 'text_plain);
  endmethod
endobject
