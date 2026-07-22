object SYM_PROTO [
  import_export_id -> "sym_proto",
  import_export_hierarchy -> {"types"}
]
  name: "Symbol Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Prototype object for symbol utility methods.";

  method as_string owner: HACKER
    "Return the symbol's text.";
    {sym} = args;
    typeof(sym) == TYPE_SYM || raise(E_TYPE, "Method must be called on symbol");
    return tostr(sym);
  endmethod

  method starts_with owner: HACKER
    "Return whether the symbol text starts with prefix.";
    {sym, prefix} = args;
    typeof(sym) == TYPE_SYM || raise(E_TYPE, "Method must be called on symbol");
    if (typeof(prefix) == TYPE_SYM)
      prefix = tostr(prefix);
    endif
    typeof(prefix) == TYPE_STR || raise(E_TYPE, "Prefix must be a string or symbol");
    return tostr(sym):starts_with(prefix);
  endmethod

  method ends_with owner: HACKER
    "Return whether the symbol text ends with suffix.";
    {sym, suffix} = args;
    typeof(sym) == TYPE_SYM || raise(E_TYPE, "Method must be called on symbol");
    if (typeof(suffix) == TYPE_SYM)
      suffix = tostr(suffix);
    endif
    typeof(suffix) == TYPE_STR || raise(E_TYPE, "Suffix must be a string or symbol");
    return tostr(sym):ends_with(suffix);
  endmethod

  method contains owner: HACKER
    "Return whether the symbol text contains needle.";
    {sym, needle} = args;
    typeof(sym) == TYPE_SYM || raise(E_TYPE, "Method must be called on symbol");
    if (typeof(needle) == TYPE_SYM)
      needle = tostr(needle);
    endif
    typeof(needle) == TYPE_STR || raise(E_TYPE, "Needle must be a string or symbol");
    return tostr(sym):contains(needle);
  endmethod

  method test_symbol_text_helpers owner: HACKER
    "Cover symbol text projection and matching helpers.";
    $test_utils:assert_eq('topic_say:as_string(), "topic_say", "as_string returns symbol text");
    $test_utils:assert_true('topic_say:starts_with('topic_), "starts_with accepts symbol prefix");
    $test_utils:assert_true('topic_say:starts_with("topic_"), "starts_with accepts string prefix");
    $test_utils:assert_false('say_topic:starts_with('topic_), "starts_with rejects non-prefix");
    $test_utils:assert_true('topic_say:ends_with('say), "ends_with accepts symbol suffix");
    $test_utils:assert_false('topic_say:ends_with('topic), "ends_with rejects non-suffix");
    $test_utils:assert_true('topic_say:contains('ic_s), "contains accepts symbol needle");
    $test_utils:assert_false('topic_say:contains("emote"), "contains rejects absent needle");
    $test_utils:assert_raises(E_TYPE, 'topic_say, "starts_with", {1}, "starts_with rejects non-text prefix");
    return true;
  endmethod
endobject
