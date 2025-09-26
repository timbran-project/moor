object INT_PROTO
  name: "Integer Prototype"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb format_time_seconds (this none this) owner: HACKER flags: "rxd"
    "Convert integer seconds to human-readable time format";
    "Usage: seconds_value:format_time_seconds()";
    {seconds} = args;
    typeof(seconds) != INT && raise(E_TYPE, "Method must be called on integer");
    seconds < 0 && raise(E_INVARG, "Seconds cannot be negative");
    seconds < 60 && return tostr(seconds, "s");
    minutes = seconds / 60;
    remaining_seconds = seconds % 60;
    minutes < 60 && return tostr(minutes, "m", remaining_seconds, "s");
    hours = minutes / 60;
    remaining_minutes = minutes % 60;
    hours < 24 && return tostr(hours, "h", remaining_minutes, "m");
    days = hours / 24;
    remaining_hours = hours % 24;
    return tostr(days, "d", remaining_hours, "h");
  endverb

  verb test_format_time_seconds_basic (this none this) owner: HACKER flags: "rxd"
    "Test basic time formatting for seconds, minutes, hours";
    "Test seconds only";
    30:format_time_seconds() != "30s" && return E_ASSERT;
    0:format_time_seconds() != "0s" && return E_ASSERT;
    59:format_time_seconds() != "59s" && return E_ASSERT;
    "Test minutes and seconds";
    60:format_time_seconds() != "1m0s" && return E_ASSERT;
    90:format_time_seconds() != "1m30s" && return E_ASSERT;
    3599:format_time_seconds() != "59m59s" && return E_ASSERT;
    "Test hours and minutes";
    3600:format_time_seconds() != "1h0m" && return E_ASSERT;
    7890:format_time_seconds() != "2h11m" && return E_ASSERT;
    return true;
  endverb

  verb test_format_time_seconds_edge_cases (this none this) owner: HACKER flags: "rxd"
    "Test edge cases and error conditions";
    "Test days";
    86400:format_time_seconds() != "1d0h" && return E_ASSERT;
    90061:format_time_seconds() != "1d1h" && return E_ASSERT;
    "Test error conditions";
    try
      -1:format_time_seconds();
      return E_ASSERT;
    except e (E_INVARG)
      "Expected error for negative seconds";
    endtry
    return true;
  endverb

  verb test_format_time_seconds_realistic (this none this) owner: HACKER flags: "rxd"
    "Test realistic idle/connection times";
    "Test typical idle times";
    180:format_time_seconds() != "3m0s" && return E_ASSERT;
    1800:format_time_seconds() != "30m0s" && return E_ASSERT;
    5400:format_time_seconds() != "1h30m" && return E_ASSERT;
    "Test long connection times";
    28800:format_time_seconds() != "8h0m" && return E_ASSERT;
    172800:format_time_seconds() != "2d0h" && return E_ASSERT;
    return true;
  endverb
endobject