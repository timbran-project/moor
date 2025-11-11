object STR_PROTO
  name: "String Utilities"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property _character_set (owner: HACKER, flags: "rc") = "\t !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  property _character_set_in_ascii (owner: HACKER, flags: "rc") = {
    8,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
    121,
    122,
    123,
    124,
    125,
    126
  };
  property _character_set_in_hex_ascii (owner: HACKER, flags: "rc") = {
    "08",
    "20",
    "21",
    "22",
    "23",
    "24",
    "25",
    "26",
    "27",
    "28",
    "29",
    "2A",
    "2B",
    "2C",
    "2D",
    "2E",
    "2F",
    "30",
    "31",
    "32",
    "33",
    "34",
    "35",
    "36",
    "37",
    "38",
    "39",
    "3A",
    "3B",
    "3C",
    "3D",
    "3E",
    "3F",
    "40",
    "41",
    "42",
    "43",
    "44",
    "45",
    "46",
    "47",
    "48",
    "49",
    "4A",
    "4B",
    "4C",
    "4D",
    "4E",
    "4F",
    "50",
    "51",
    "52",
    "53",
    "54",
    "55",
    "56",
    "57",
    "58",
    "59",
    "5A",
    "5B",
    "5C",
    "5D",
    "5E",
    "5F",
    "60",
    "61",
    "62",
    "63",
    "64",
    "65",
    "66",
    "67",
    "68",
    "69",
    "6A",
    "6B",
    "6C",
    "6D",
    "6E",
    "6F",
    "70",
    "71",
    "72",
    "73",
    "74",
    "75",
    "76",
    "77",
    "78",
    "79",
    "7A",
    "7B",
    "7C",
    "7D",
    "7E"
  };
  property alphabet (owner: HACKER, flags: "rc") = "abcdefghijklmnopqrstuvwxyz";
  property ascii (owner: HACKER, flags: "rc") = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  property digits (owner: HACKER, flags: "rc") = "0123456789";
  property tab (owner: HACKER, flags: "rc") = "\t";

  override description = "Prototype object for string utility methods and text manipulation operations.";
  override import_export_id = "str_proto";

  verb "capitalize capitalise" (this none this) owner: HACKER flags: "rxd"
    "Capitalizes its argument.";
    string = args[1];
    if (string)
      let i = index("abcdefghijklmnopqrstuvwxyz", string[1], 1);
      if (i)
        string[1] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i];
      endif
    endif
    return string;
  endverb

  verb initial_lowercase (this none this) owner: HACKER flags: "rxd"
    "Lowercases the first character of its argument.";
    string = args[1];
    if (string)
      let i = index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", string[1], 1);
      if (i)
        string[1] = "abcdefghijklmnopqrstuvwxyz"[i];
      endif
    endif
    return string;
  endverb

  verb "centre center" (this none this) owner: HACKER flags: "rxd"
    {text, len, ?lfill = " ", ?rfill = lfill} = args;
    out = tostr(text);
    abslen = abs(len);
    if (length(out) < abslen)
      return this:space((abslen - length(out)) / 2, lfill) + out + this:space((abslen - length(out) + 1) / -2, rfill);
    else
      return len > 0 ? out | out[1..abslen];
    endif
  endverb

  verb is_numeric (this none this) owner: HACKER flags: "rxd"
    "Usage:  is_numeric(string)";
    "Is string numeric (composed of one or more digits possibly preceded by a minus sign)?";
    "Return true or false.";
    return match(args[1], "^ *[-+]?[0-9]+ *$");
  endverb

  verb literal_object (this none this) owner: HACKER flags: "rxd"
    string = args[1];
    if (!string)
      return $nothing;
    elseif (string[1] == "#")
      let object = this:toobj();
      if (E_TYPE != object)
        return object;
      endif
    elseif (string[1] == "@")
      return this:match_player(string[2..$], #0);
    elseif (string[1] == "$")
      string = string[2..$];
      let object = #0;
      while properties(1)
        let dot = index(string, ".");
        let pn = dot ? string[1..dot - 1] | string;
        try
          object = object.(pn);
        except (ANY)
          return $failed_match;
        endtry
        if (dot)
          string = string[dot + 1..$];
        else
          break properties;
        endif
      endwhile
      if (typeof(object) == OBJ)
        return object;
      else
        return $failed_match;
      endif
    else
      return $failed_match;
    endif
  endverb

  verb render_as (this none this) owner: HACKER flags: "rxd"
    "Render the given string part down into a proper string for the given content-type. For now this just returns it back, unmodified. Future versions could do escaping etc for HTML";
    return this;
  endverb

  verb space (this none this) owner: HACKER flags: "rxd"
    "space(len,fill) returns a string of length abs(len) consisting of copies of fill.  If len is negative, fill is anchored on the right instead of the left.";
    "len has an upper limit of 100,000.";
    {n, ?fill = " "} = args;
    if (typeof(n) == STR)
      n = length(n);
    endif
    if ((n = abs(n)) > 100000)
      raise(E_INVARG);
    endif
    if (fill != " ")
      fill = fill + fill;
      fill = fill + fill;
      fill = fill + fill;
    elseif (n < 70)
      return "                                                                      "[1..n];
    else
      fill = "                                                                      ";
    endif
    m = (n - 1) / length(fill);
    while (m)
      fill = fill + fill;
      m = m / 2;
    endwhile
    f = length(fill);
    return n > 0 ? fill[1..n] | fill[f + 1 + n..f];
  endverb

  verb to_list (this none this) owner: HACKER flags: "rxd"
    "Usage:  $string:to_list(str <subject>[, str <separator>])";
    "";
    "Returns a list of those substrings of <subject> separated by <separator>.  <separator> defaults to space.";
    "";
    "Differs from $string:explode in that";
    "";
    "  * <separator> can effectively be longer than one character.";
    "  * runs of <separator> are not treated as single occurrences.";
    "";
    "$string:to_list  (string, separator) is the inverse of";
    "$string:from_list(list  , separator)";
    {subject, ?separator = " "} = args;
    breaklen = length(separator);
    parts = {};
    i = 0;
    while (i = index(subject, separator))
      parts = {@parts, subject[1..i - 1]};
      subject = subject[i + breaklen..$];
    endwhile
    return {@parts, subject};
  endverb

  verb toobj (this none this) owner: HACKER flags: "rxd"
    ":toobj(objectid as string) => objectid";
    s = args[1];
    return match(s, "^ *#[-+]?[0-9]+ *$") ? toobj(s) | E_TYPE;
  endverb

  verb match_objid (this none this) owner: HACKER flags: "rxd"
    "Find the first object identifier (#number or #uuid) within the given string.";
    "Returns a map with start/end offsets (1-based, inclusive), the matched text, and the identifier type.";
    "If no object identifier is present, returns false.";
    {s, ?anchored = false} = args;
    typeof(s) == STR || raise(E_TYPE, "match_objid expects a string argument");
    len = length(s);
    if (len == 0)
      return false;
    endif
    fn is_digit(digit_char)
      return typeof(digit_char) == STR && length(digit_char) == 1 && index("0123456789", digit_char) != 0;
    endfn
    fn is_hex(hex_char)
      return typeof(hex_char) == STR && length(hex_char) == 1 && index("0123456789ABCDEFabcdef", hex_char) != 0;
    endfn
    fn is_alnum(alnum_char)
      return typeof(alnum_char) == STR && length(alnum_char) == 1 && index("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", alnum_char) != 0;
    endfn
    for idx in [1..len]
      if (s[idx] != "#")
        continue;
      endif
      if (idx > 1 && is_alnum(s[idx - 1]))
        continue;
      endif
      let uuid_bounds = this:match_uuobjid_at(s, idx);
      let end_index = 0;
      let match_type = 'numbered;
      if (uuid_bounds)
        end_index = uuid_bounds[2];
        match_type = 'uuid;
      else
        let pos = idx + 1;
        if (pos <= len && index("+-", s[pos]))
          pos = pos + 1;
        endif
        let digits_start = pos;
        while (pos <= len && is_digit(s[pos]))
          pos = pos + 1;
        endwhile
        if (pos > digits_start)
          end_index = pos - 1;
          match_type = 'numbered;
        endif
      endif
      if (!end_index)
        continue;
      endif
      if (end_index < len && is_alnum(s[end_index + 1]))
        continue;
      endif
      if (anchored)
        let prefix = idx > 1 ? s[1..idx - 1] | "";
        let suffix = end_index < len ? s[end_index + 1..$] | "";
        if (prefix:trim() || suffix:trim())
          continue;
        endif
      endif
      return ['text -> s[idx..end_index], 'start -> idx, 'end -> end_index, 'type -> match_type];
    endfor
    return false;
  endverb

  verb match_uuobjid_at (this none this) owner: HACKER flags: "rxd"
    "Check for a uuobjid starting at position start_index, returning {start,end} or false.";
    {s, start_index} = args;
    typeof(s) == STR || raise(E_TYPE, "Source must be string");
    typeof(start_index) == INT || raise(E_TYPE, "Start index must be integer");
    start_index >= 1 || raise(E_INVARG);
    len = length(s);
    end_index = start_index + 17;
    if (end_index > len)
      return false;
    endif
    for offset in [1..6]
      if (!index("0123456789ABCDEFabcdef", s[start_index + offset]))
        return false;
      endif
    endfor
    if (s[start_index + 7] != "-")
      return false;
    endif
    for offset in [8..17]
      if (!index("0123456789ABCDEFabcdef", s[start_index + offset]))
        return false;
      endif
    endfor
    if (end_index < len && index("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", s[end_index + 1]))
      return false;
    endif
    if (start_index > 1 && index("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", s[start_index - 1]))
      return false;
    endif
    return {start_index, end_index};
  endverb

  verb parse_name_aliases (this none this) owner: HACKER flags: "rxd"
    "Parse a name/alias specification. Supports both 'name:alias,alias' and 'name,alias,alias' formats.";
    {spec} = args;
    typeof(spec) == STR || raise(E_TYPE, "Specification must be a string");
    trimmed = spec:trim();
    if (!trimmed)
      return {"", {}};
    endif
    fn tokenize(input)
      let tokens = {};
      let current = "";
      let in_quotes = false;
      let i = 1;
      while (i <= length(input))
        let ch = input[i];
        if (ch == "\\" && i < length(input))
          current = current + input[i + 1];
          i = i + 2;
          continue;
        endif
        if (ch == "\"")
          in_quotes = !in_quotes;
          current = current + ch;
          i = i + 1;
          continue;
        endif
        if (!in_quotes && ch == ",")
          tokens = {@tokens, current};
          current = "";
          i = i + 1;
          continue;
        endif
        current = current + ch;
        i = i + 1;
      endwhile
      tokens = {@tokens, current};
      return tokens;
    endfn
    fn unquote(text)
      let s = text:trim();
      if (length(s) >= 2 && s[1] == "\"" && s[$] == "\"")
        let inner = "";
        let i = 2;
        let limit = length(s) - 1;
        while (i <= limit)
          let ch = s[i];
          if (ch == "\\" && i < limit)
            inner = inner + s[i + 1];
            i = i + 2;
            continue;
          endif
          inner = inner + ch;
          i = i + 1;
        endwhile
        return inner;
      endif
      return s;
    endfn
    "Check if colon-separated format (name:alias,alias)";
    colon_parts = this:to_list(trimmed, ":");
    if (length(colon_parts) >= 2)
      primary = unquote(colon_parts[1]);
      alias_tokens = tokenize(colon_parts[2]);
    else
      "Comma-separated format (name,alias,alias)";
      all_tokens = tokenize(trimmed);
      if (!all_tokens)
        return {"", {}};
      endif
      primary = unquote(all_tokens[1]);
      alias_tokens = length(all_tokens) > 1 ? all_tokens[2..$] | {};
    endif
    aliases = {};
    for alias in (alias_tokens)
      alias = unquote(alias);
      if (!alias || alias == primary)
        continue;
      endif
      if (!(alias in aliases))
        aliases = {@aliases, alias};
      endif
    endfor
    if (!primary)
      primary = aliases ? aliases[1] | "";
      aliases = primary ? aliases[2..$] | {};
    endif
    return {primary, aliases};
  endverb

  verb test_parse_name_aliases (this none this) owner: HACKER flags: "rxd"
    "Test parse_name_aliases with various formats";
    result = $str_proto:parse_name_aliases("simple");
    result != {"simple", {}} && raise(E_ASSERT, "Failed simple name: " + toliteral(result));
    result = $str_proto:parse_name_aliases("box,container,chest");
    result != {"box", {"container", "chest"}} && raise(E_ASSERT, "Failed comma-separated: " + toliteral(result));
    result = $str_proto:parse_name_aliases("box:container,chest");
    result != {"box", {"container", "chest"}} && raise(E_ASSERT, "Failed colon-separated: " + toliteral(result));
    result = $str_proto:parse_name_aliases("\"secret box (totally absolutely secret, not joking)\",box");
    result != {"secret box (totally absolutely secret, not joking)", {"box"}} && raise(E_ASSERT, "Failed quoted name with comma: " + toliteral(result));
    result = $str_proto:parse_name_aliases("\"box with \\\"quotes\\\"\",container");
    result != {"box with \"quotes\"", {"container"}} && raise(E_ASSERT, "Failed escaped quotes: " + toliteral(result));
    result = $str_proto:parse_name_aliases("\"name\":alias1,alias2");
    result != {"name", {"alias1", "alias2"}} && raise(E_ASSERT, "Failed quoted name with colon: " + toliteral(result));
    result = $str_proto:parse_name_aliases("  spaced  ,  also  ");
    result != {"spaced", {"also"}} && raise(E_ASSERT, "Failed whitespace trimming: " + toliteral(result));
  endverb

  verb trim (this none this) owner: HACKER flags: "rxd"
    ":trim (string [, space]) -- remove leading and trailing spaces";
    "";
    "`space' should be a character (single-character string); it defaults to \" \".  Returns a copy of string with all leading and trailing copies of that character removed.  For example, $string:trim(\"***foo***\", \"*\") => \"foo\".";
    {string, ?space = " "} = args;
    m = match(string, tostr("[^", space, "]%(.*[^", space, "]%)?%|$"));
    return string[m[1]..m[2]];
  endverb

  verb triml (this none this) owner: HACKER flags: "rxd"
    ":triml(string [, space]) -- remove leading spaces";
    "";
    "`space' should be a character (single-character string); it defaults to \" \".  Returns a copy of string with all leading copies of that character removed.  For example, $string:triml(\"***foo***\", \"*\") => \"foo***\".";
    {string, ?space = " "} = args;
    return string[match(string, tostr("[^", space, "]%|$"))[1]..length(string)];
  endverb

  verb trimr (this none this) owner: HACKER flags: "rxd"
    ":trimr(string [, space]) -- remove trailing spaces";
    "";
    "`space' should be a character (single-character string); it defaults to \" \".  Returns a copy of string with all trailing copies of that character removed.  For example, $string:trimr(\"***foo***\", \"*\") => \"***foo\".";
    {string, ?space = " "} = args;
    return string[1..rmatch(string, tostr("[^", space, "]%|^"))[2]];
  endverb

  verb "uppercase lowercase" (this none this) owner: HACKER flags: "rxd"
    "lowercase(string) -- returns a lowercase version of the string.";
    "uppercase(string) -- returns the uppercase version of the string.";
    string = args[1];
    caps = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    lower = "abcdefghijklmnopqrstuvwxyz";
    from = caps;
    to = lower;
    if (verb == "uppercase")
      from = lower;
      to = caps;
    endif
    for i in [1..26]
      string = strsub(string, from[i], to[i], 1);
    endfor
    return string;
  endverb

  verb word_start (this none this) owner: HACKER flags: "rxd"
    "This breaks up the argument string into words, returning a list of indices into argstr corresponding to the starting points of each of the arguments.";
    rest = args[1];
    wstart = match(rest, "[^ ]%|$")[1];
    wbefore = wstart - 1;
    rest[1..wbefore] = "";
    if (!rest)
      return {};
    endif
    quote = 0;
    wslist = {};
    pattern = " +%|\\.?%|\"";
    m = 0;
    char = 0;
    while (m = match(rest, pattern))
      char = rest[m[1]];
      if (char == " ")
        wslist = {@wslist, {wstart, wbefore + m[1] - 1}};
        wstart = wbefore + m[2] + 1;
      elseif (char == "\"")
        pattern = (quote = !quote) ? "\\.?%|\"" | " +%|\\.?%|\"";
      endif
      rest[1..m[2]] = "";
      wbefore = wbefore + m[2];
    endwhile
    return rest || char != " " ? {@wslist, {wstart, wbefore + length(rest)}} | wslist;
  endverb

  verb words (this none this) owner: HACKER flags: "rxd"
    "This breaks up the argument string into words, the resulting list being obtained exactly the way the command line parser obtains `args' from `argstr'.";
    rest = args[1];
    rest[1..match(rest, "^ *")[2]] = "";
    if (!rest)
      return {};
    endif
    quote = 0;
    toklist = {};
    token = "";
    pattern = " +%|\\.?%|\"";
    m = 0;
    char = 0;
    while (m = match(rest, pattern))
      char = rest[m[1]];
      token = token + rest[1..m[1] - 1];
      if (char == " ")
        toklist = {@toklist, token};
        token = "";
      elseif (char == "\"")
        pattern = (quote = !quote) ? "\\.?%|\"" | " +%|\\.?%|\"";
      elseif (m[1] < m[2])
        token = token + rest[m[2]];
      endif
      rest[1..m[2]] = "";
    endwhile
    return rest || char != " " ? {@toklist, token + rest} | toklist;
  endverb

  verb append_to_paragraph (this none this) owner: HACKER flags: "rxd"
    "Given arguments which are list of strings, appends.";
    "e.g.  \"dog\":append_to_paragraph() => {\"dog\"}";
    "      \"dog\":append_to_paragraph(\"cats and\") => {\"cats and dogs\"}";
    "      \"dog\":append_to_paragraph(\"cats get chased by:\", \"\") => { \"cats get chased by:\", \"dogs\"}";
    length(args) == 1 && return args;
    length(args) == 2 && return {args[2] + args[1]};
    head = args[2..length(args) - 1];
    tail = args[length(args)] + args[1];
    return {@head, tail};
  endverb

  verb test_append_to_paragraph (this none this) owner: HACKER flags: "rxd"
    "":append_to_paragraph() != {""} && raise(E_ASSERT, "Failed empty append");
    "dog":append_to_paragraph("") != {"dog"} && raise(E_ASSERT, "Failed empty append");
    (a = "dog":append_to_paragraph("cats and ")) != {"cats and dog"} && raise(E_ASSERT, "Failed single line append; got " + toliteral(a));
    (a = "dog":append_to_paragraph("cats and, also...", "a ")) != {"cats and, also...", "a dog"} && raise(E_ASSERT, "Failed single line append; got " + toliteral(a));
    (a = "dog":append_to_paragraph("cats and, also...", "a ", "")) != {"cats and, also...", "a ", "dog"} && raise(E_ASSERT, "Failed single line append; got " + toliteral(a));
  endverb

  verb parse_verbref (this none this) owner: HACKER flags: "rxd"
    "Parses string as a MOO-code verb reference, returning {object-string, verb-name-string} for a successful parse and false otherwise.  It always returns the right object-string to pass to, for example, this-room:match_object().";
    s = args[1];
    colon = index(s, ":");
    !colon && return false;
    {object, verbname} = {s[1..colon - 1], s[colon + 1..length(s)]};
    !(object && verbname) && return false;
    if (object[1] == "$" && 0)
      let pname = object[2..length(object)];
      if (!(pname in properties(#0)) || typeof(object = #0.(pname)) != OBJ)
        return false;
      endif
      object = tostr(object);
    endif
    return {object, verbname};
  endverb

  verb test_parse_verbref (this none this) owner: HACKER flags: "rxd"
    begin
      let {result, should} = {"#1":parse_verbref(), false};
      result != should && raise(E_ASSERT, "#1 should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {":":parse_verbref(), false};
      result != should && raise(E_ASSERT, ": should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {"$string:look_self":parse_verbref(), {"$string", "look_self"}};
      result != should && raise(E_ASSERT, "$string:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {"#1:look_self":parse_verbref(), {"#1", "look_self"}};
      result != should && raise(E_ASSERT, "#1:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {"honk:look_self":parse_verbref(), {"honk", "look_self"}};
      result != should && raise(E_ASSERT, "honk:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
  endverb

  verb split (this none this) owner: HACKER flags: "rxd"
    "split(string, delimiter) => list of substrings split by delimiter";
    "Example: \"a,b,c\":split(\",\") => {\"a\", \"b\", \"c\"}";
    {string, delimiter} = args;
    fn split_string(text, delim)
      if (delim == "")
        return {text};
      endif
      let parts = {};
      let remaining = text;
      let index_pos = 0;
      while (index_pos = index(remaining, delim))
        parts = {@parts, remaining[1..index_pos - 1]};
        remaining = remaining[index_pos + length(delim)..$];
      endwhile
      return {@parts, remaining};
    endfn
    return split_string(string, delimiter);
  endverb

  verb join_list (this none this) owner: HACKER flags: "rxd"
    "join_list(list, separator) => string with list elements joined by separator";
    "Example: {\"a\", \"b\", \"c\"}:join_list(\",\") => \"a,b,c\"";
    {lst, separator} = args;
    return lst:join(separator);
  endverb

  verb starts_with (this none this) owner: HACKER flags: "rxd"
    "starts_with(string, prefix) => true if string starts with prefix";
    "Example: \"hello world\":starts_with(\"hello\") => true";
    return length(args[2]) <= length(args[1]) && (args[1])[1..length(args[2])] == args[2];
  endverb

  verb ends_with (this none this) owner: HACKER flags: "rxd"
    "ends_with(string, suffix) => true if string ends with suffix";
    "Example: \"hello world\":ends_with(\"world\") => true";
    return length(args[2]) <= length(args[1]) && (args[1])[length(args[1]) - length(args[2]) + 1..$] == args[2];
  endverb

  verb contains (this none this) owner: HACKER flags: "rxd"
    "contains(string, substring) => true if string contains substring";
    "Example: \"hello world\":contains(\"lo wo\") => true";
    return index(args[1], args[2]) != 0;
  endverb

  verb replace_all (this none this) owner: HACKER flags: "rxd"
    "replace_all(string, old, new) => string with all occurrences of old replaced with new";
    "Example: \"hello world\":replace_all(\"l\", \"x\") => \"hexxo worxd\"";
    s = args[1];
    old_part = args[2];
    new_part = args[3];
    parts = this:split(s, old_part);
    return parts:join(new_part);
  endverb

  verb reverse (this none this) owner: HACKER flags: "rxd"
    "reverse(string) => string with characters in reverse order";
    "Example: \"hello\":reverse() => \"olleh\"";
    {instr} = args;
    out = "";
    for i in [1..length(instr)]
      out = instr[i] + out;
    endfor
    return out;
  endverb

  verb repeat (this none this) owner: HACKER flags: "rxd"
    "repeat(string, count) => string repeated count times";
    "Example: \"ab\":repeat(3) => \"ababab\"";
    {string, count} = args;
    if (count <= 0)
      return "";
    endif
    result = "";
    for i in [1..count]
      result = result + string;
    endfor
    return result;
  endverb

  verb char_count (this none this) owner: HACKER flags: "rxd"
    "char_count(string, character) => count of character occurrences in string";
    "Example: \"hello\":char_count(\"l\") => 2";
    {string, char} = args;
    count = 0;
    for i in [1..length(string)]
      if (string[i] == char)
        count = count + 1;
      endif
    endfor
    return count;
  endverb

  verb substring (this none this) owner: HACKER flags: "rxd"
    "substring(string, start, length) => substring starting at start for length characters";
    "Example: \"hello world\":substring(7, 5) => \"world\"";
    {string, start, len} = args;
    return string[start..start + len - 1];
  endverb

  verb pad_left (this none this) owner: HACKER flags: "rxd"
    "pad_left(string, width, fill) => string padded on left to width with fill character";
    "Example: \"hello\":pad_left(10, \"*\") => \"*****hello\"";
    {string, width, ?fill = " "} = args;
    padding_needed = width - length(string);
    if (padding_needed <= 0)
      return string;
    endif
    return this:space(padding_needed, fill) + string;
  endverb

  verb pad_right (this none this) owner: HACKER flags: "rxd"
    "pad_right(string, width, fill) => string padded on right to width with fill character";
    "Example: \"hello\":pad_right(10, \"*\") => \"hello*****\"";
    {string, width, ?fill = " "} = args;
    padding_needed = width - length(string);
    if (padding_needed <= 0)
      return string;
    endif
    return string + this:space(padding_needed, fill);
  endverb

  verb words_list (this none this) owner: HACKER flags: "rxd"
    "words_list(string) => list of words split by whitespace using modern approach";
    "Example: \"hello world test\":words_list() => {\"hello\", \"world\", \"test\"}";
    string = args[1];
    return this:split(this:trim(string), " "):filter({w} => w != "");
  endverb

  verb map_chars (this none this) owner: HACKER flags: "rxd"
    "map_chars(string, function) => string with function applied to each character";
    "Example: \"hello\":map_chars({c} => uppercase(c)) => \"HELLO\"";
    {string, func} = args;
    result = "";
    for i in [1..length(string)]
      result = result + func(string[i]);
    endfor
    return result;
  endverb

  verb filter_chars (this none this) owner: HACKER flags: "rxd"
    "filter_chars(string, predicate) => string with only characters matching predicate";
    "Example: \"abc123def\":filter_chars({c} => c in \"abcdefghijklmnopqrstuvwxyz\") => \"abcdef\"";
    {string, pred} = args;
    result = "";
    for i in [1..length(string)]
      if (pred(string[i]))
        result = result + string[i];
      endif
    endfor
    return result;
  endverb

  verb title_case (this none this) owner: HACKER flags: "rxd"
    "title_case(string) => string with first letter of each word capitalized";
    "Example: \"hello world\":title_case() => \"Hello World\"";
    string = args[1];
    words = this:words_list(string);
    result = {};
    for word in (words)
      result = {@result, this:capitalize(word)};
    endfor
    return result:join(" ");
  endverb

  verb parse_verbref (this none this) owner: HACKER flags: "rxd"
    "Parses string as a MOO-code verb reference, returning {object-string, verb-name-string} for a successful parse and false otherwise.  It always returns the right object-string to pass to, for example, this-room:match_object().";
    s = args[1];
    colon = index(s, ":");
    colon || return false;
    object = s[1..colon - 1];
    verbname = s[colon + 1..$];
    object && verbname || return false;
    if (object[1] == "$")
      pname = object[2..$];
      if (!(pname in properties(#0)) || typeof(object = #0.(pname)) != OBJ)
        return false;
      endif
      object = tostr(object);
    endif
    return {object, verbname};
  endverb

  verb from_seconds (this none this) owner: HACKER flags: "rxd"
    ":from_seconds(number of seconds) => returns a string containing the rough increment of days, or hours if less than a day, or minutes if less than an hour, or lastly in seconds.";
    ":from_seconds(86400) => \"a day\"";
    ":from_seconds(7200)  => \"two hours\"";
    minute = 60;
    hour = 60 * minute;
    day = 24 * hour;
    secs = args[1];
    if (secs > day)
      count = secs / day;
      unit = "day";
      article = "a";
    elseif (secs > hour)
      count = secs / hour;
      unit = "hour";
      article = "an";
    elseif (secs > minute)
      count = secs / minute;
      unit = "minute";
      article = "a";
    else
      count = secs;
      unit = "second";
      article = "a";
    endif
    if (count == 1)
      time = tostr(article, " ", unit);
    else
      time = tostr(count, " ", unit, "s");
    endif
    return time;
  endverb

  verb parse_time_of_day (this none this) owner: HACKER flags: "rxd"
    "Parse HH:MM:SS time string and return next occurrence as Unix timestamp.";
    "Example: \"14:30:00\":parse_time_of_day() returns timestamp for next 2:30 PM.";
    {time_str} = args;
    typeof(time_str) == STR || raise(E_TYPE, "Time must be string");
    parts = time_str:split(":");
    length(parts) == 3 || raise(E_INVARG, "Time must be HH:MM:SS format");
    hours = toint(parts[1]);
    minutes = toint(parts[2]);
    seconds = toint(parts[3]);
    hours >= 0 && hours < 24 || raise(E_INVARG, "Hours must be 0-23");
    minutes >= 0 && minutes < 60 || raise(E_INVARG, "Minutes must be 0-59");
    seconds >= 0 && seconds < 60 || raise(E_INVARG, "Seconds must be 0-59");
    "Calculate seconds from midnight";
    target_seconds = hours * 3600 + minutes * 60 + seconds;
    "Get current time and calculate today's occurrence";
    now = time();
    ct = ctime(now);
    current_hour = toint(ct[12..13]);
    current_minute = toint(ct[15..16]);
    current_second = toint(ct[18..19]);
    current_seconds = current_hour * 3600 + current_minute * 60 + current_second;
    "If target time has passed today, schedule for tomorrow";
    if (target_seconds <= current_seconds)
      return now + (86400 - current_seconds + target_seconds);
    else
      return now + (target_seconds - current_seconds);
    endif
  endverb

  verb test_parse_time_of_day (this none this) owner: HACKER flags: "rxd"
    "Test parsing daily time strings.";
    "Test valid time";
    next_run = "14:30:00":parse_time_of_day();
    typeof(next_run) == INT || raise(E_ASSERT, "Should return timestamp");
    next_run > time() || raise(E_ASSERT, "Should be in future");
    "Test invalid formats";
    caught = `"25:00:00":parse_time_of_day() ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject invalid hours");
    caught = `"12:60:00":parse_time_of_day() ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject invalid minutes");
    caught = `"12:30":parse_time_of_day() ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject missing seconds");
    "Test midnight";
    next_run = "00:00:00":parse_time_of_day();
    typeof(next_run) == INT || raise(E_ASSERT, "Midnight should return timestamp");
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    return args[1];
  endverb

  verb test_split (this none this) owner: HACKER flags: "rxd"
    "Test the split function";
    result = 0;
    result = "a,b,c":split(",");
    result != {"a", "b", "c"} && raise(E_ASSERT, "Basic split failed, got " + toliteral(result));
    result = "a,,c":split(",");
    result != {"a", "", "c"} && raise(E_ASSERT, "Empty parts split failed, got " + toliteral(result));
    result = "hello":split(",");
    result != {"hello"} && raise(E_ASSERT, "No delimiter split failed, got " + toliteral(result));
    result = "":split(",");
    result != {""} && raise(E_ASSERT, "Empty string split failed, got " + toliteral(result));
    result = "a::b::c":split("::");
    result != {"a", "b", "c"} && raise(E_ASSERT, "Multi-char delimiter split failed, got " + toliteral(result));
  endverb

  verb test_starts_with (this none this) owner: HACKER flags: "rxd"
    "Test the starts_with function";
    result = 0;
    result = "hello world":starts_with("hello");
    result != true && raise(E_ASSERT, "Positive starts_with failed, got " + toliteral(result));
    result = "hello world":starts_with("world");
    result != false && raise(E_ASSERT, "Negative starts_with failed, got " + toliteral(result));
    result = "hello":starts_with("");
    result != true && raise(E_ASSERT, "Empty prefix starts_with failed, got " + toliteral(result));
    result = "hi":starts_with("hello");
    result != false && raise(E_ASSERT, "Long prefix starts_with failed, got " + toliteral(result));
    result = "hello":starts_with("hello");
    result != true && raise(E_ASSERT, "Exact match starts_with failed, got " + toliteral(result));
  endverb

  verb test_ends_with (this none this) owner: HACKER flags: "rxd"
    "Test the ends_with function";
    result = 0;
    result = "hello world":ends_with("world");
    result != true && raise(E_ASSERT, "Positive ends_with failed, got " + toliteral(result));
    result = "hello world":ends_with("hello");
    result != false && raise(E_ASSERT, "Negative ends_with failed, got " + toliteral(result));
    result = "hello":ends_with("");
    result != true && raise(E_ASSERT, "Empty suffix ends_with failed, got " + toliteral(result));
    result = "hi":ends_with("hello");
    result != false && raise(E_ASSERT, "Long suffix ends_with failed, got " + toliteral(result));
    result = "hello":ends_with("hello");
    result != true && raise(E_ASSERT, "Exact match ends_with failed, got " + toliteral(result));
  endverb

  verb test_contains (this none this) owner: HACKER flags: "rxd"
    "Test the contains function";
    result = 0;
    result = "hello world":contains("lo wo");
    result != true && raise(E_ASSERT, "Positive contains failed, got " + toliteral(result));
    result = "hello world":contains("xyz");
    result != false && raise(E_ASSERT, "Negative contains failed, got " + toliteral(result));
    result = "hello":contains("");
    result != true && raise(E_ASSERT, "Empty substring contains failed, got " + toliteral(result));
    result = "hello":contains("hello");
    result != true && raise(E_ASSERT, "Exact match contains failed, got " + toliteral(result));
  endverb

  verb test_replace_all (this none this) owner: HACKER flags: "rxd"
    "Test the replace_all function";
    result = 0;
    result = "hello world":replace_all("l", "x");
    result != "hexxo worxd" && raise(E_ASSERT, "Basic replace_all failed, got " + toliteral(result));
    result = "hello":replace_all("z", "x");
    result != "hello" && raise(E_ASSERT, "No matches replace_all failed, got " + toliteral(result));
    result = "hello":replace_all("l", "");
    result != "heo" && raise(E_ASSERT, "Empty replacement replace_all failed, got " + toliteral(result));
    result = "hello":replace_all("", "x");
    result != "hello" && raise(E_ASSERT, "Empty old string replace_all failed, got " + toliteral(result));
    result = "hello world":replace_all("llo", "y");
    result != "hey world" && raise(E_ASSERT, "Multi-char replace_all failed, got " + toliteral(result));
  endverb

  verb test_reverse (this none this) owner: HACKER flags: "rxd"
    "Test the reverse function";
    result = 0;
    result = "hello":reverse();
    result != "olleh" && raise(E_ASSERT, "Basic reverse failed, got " + toliteral(result));
    result = "":reverse();
    result != "" && raise(E_ASSERT, "Empty string reverse failed, got " + toliteral(result));
    result = "a":reverse();
    result != "a" && raise(E_ASSERT, "Single char reverse failed, got " + toliteral(result));
    result = "aba":reverse();
    result != "aba" && raise(E_ASSERT, "Palindrome reverse failed, got " + toliteral(result));
  endverb

  verb test_repeat (this none this) owner: HACKER flags: "rxd"
    "Test the repeat function";
    result = 0;
    result = "ab":repeat(3);
    result != "ababab" && raise(E_ASSERT, "Basic repeat failed, got " + toliteral(result));
    result = "hello":repeat(0);
    result != "" && raise(E_ASSERT, "Zero repeat failed, got " + toliteral(result));
    result = "hello":repeat(-1);
    result != "" && raise(E_ASSERT, "Negative repeat failed, got " + toliteral(result));
    result = "hello":repeat(1);
    result != "hello" && raise(E_ASSERT, "One repeat failed, got " + toliteral(result));
    result = "":repeat(5);
    result != "" && raise(E_ASSERT, "Empty string repeat failed, got " + toliteral(result));
  endverb

  verb test_char_count (this none this) owner: HACKER flags: "rxd"
    "Test the char_count function";
    result = 0;
    result = "hello":char_count("l");
    result != 2 && raise(E_ASSERT, "Basic char_count failed, got " + toliteral(result));
    result = "hello":char_count("z");
    result != 0 && raise(E_ASSERT, "No matches char_count failed, got " + toliteral(result));
    result = "aaa":char_count("a");
    result != 3 && raise(E_ASSERT, "All matches char_count failed, got " + toliteral(result));
    result = "":char_count("a");
    result != 0 && raise(E_ASSERT, "Empty string char_count failed, got " + toliteral(result));
  endverb

  verb test_substring (this none this) owner: HACKER flags: "rxd"
    "Test the substring function";
    result = 0;
    result = "hello world":substring(7, 5);
    result != "world" && raise(E_ASSERT, "Basic substring failed, got " + toliteral(result));
    result = "hello":substring(1, 3);
    result != "hel" && raise(E_ASSERT, "From beginning substring failed, got " + toliteral(result));
    result = "hello":substring(2, 1);
    result != "e" && raise(E_ASSERT, "Single char substring failed, got " + toliteral(result));
    result = "hello":substring(1, 5);
    result != "hello" && raise(E_ASSERT, "Whole string substring failed, got " + toliteral(result));
  endverb

  verb test_pad_left (this none this) owner: HACKER flags: "rxd"
    "Test the pad_left function";
    result = 0;
    result = "hello":pad_left(10, "*");
    result != "*****hello" && raise(E_ASSERT, "Basic pad_left failed, got " + toliteral(result));
    result = "hello":pad_left(3, "*");
    result != "hello" && raise(E_ASSERT, "No padding pad_left failed, got " + toliteral(result));
    result = "hi":pad_left(5);
    result != "   hi" && raise(E_ASSERT, "Default padding pad_left failed, got " + toliteral(result));
    result = "hello":pad_left(5, "*");
    result != "hello" && raise(E_ASSERT, "Exact width pad_left failed, got " + toliteral(result));
  endverb

  verb test_pad_right (this none this) owner: HACKER flags: "rxd"
    "Test the pad_right function";
    result = 0;
    result = "hello":pad_right(10, "*");
    result != "hello*****" && raise(E_ASSERT, "Basic pad_right failed, got " + toliteral(result));
    result = "hello":pad_right(3, "*");
    result != "hello" && raise(E_ASSERT, "No padding pad_right failed, got " + toliteral(result));
    result = "hi":pad_right(5);
    result != "hi   " && raise(E_ASSERT, "Default padding pad_right failed, got " + toliteral(result));
    result = "hello":pad_right(5, "*");
    result != "hello" && raise(E_ASSERT, "Exact width pad_right failed, got " + toliteral(result));
  endverb

  verb test_title_case (this none this) owner: HACKER flags: "rxd"
    "Test the title_case function";
    result = 0;
    result = "hello world":title_case();
    result != "Hello World" && raise(E_ASSERT, "Basic title_case failed, got " + toliteral(result));
    result = "hello":title_case();
    result != "Hello" && raise(E_ASSERT, "Single word title_case failed, got " + toliteral(result));
    result = "Hello World":title_case();
    result != "Hello World" && raise(E_ASSERT, "Already capitalized title_case failed, got " + toliteral(result));
    result = "hELLo WoRLd":title_case();
    result != "Hello World" && raise(E_ASSERT, "Mixed case title_case failed, got " + toliteral(result));
  endverb

  verb test_map_chars (this none this) owner: HACKER flags: "rxd"
    "Test the map_chars function";
    result = 0;
    result = "hello":map_chars({c0} => this:uppercase(c0));
    result != "HELLO" && raise(E_ASSERT, "Uppercase map_chars failed, got " + toliteral(result));
    result = "abc":map_chars({c1} => c1 == "b" ? "X" | c1);
    result != "aXc" && raise(E_ASSERT, "Character replacement map_chars failed, got " + toliteral(result));
    result = "":map_chars({c2} => c2);
    result != "" && raise(E_ASSERT, "Empty string map_chars failed, got " + toliteral(result));
  endverb

  verb test_filter_chars (this none this) owner: HACKER flags: "rxd"
    "Test the filter_chars function";
    result = 0;
    result = "abc123def":filter_chars({c3} => c3 in "abcdefghijklmnopqrstuvwxyz");
    result != "abcdef" && raise(E_ASSERT, "Letter filtering failed, got " + toliteral(result));
    result = "abc123def":filter_chars({c4} => c4 in "0123456789");
    result != "123" && raise(E_ASSERT, "Digit filtering failed, got " + toliteral(result));
    result = "abc":filter_chars({c5} => c5 in "123");
    result != "" && raise(E_ASSERT, "No matches filter_chars failed, got " + toliteral(result));
    result = "abc":filter_chars({c6} => c6 in "abcdef");
    result != "abc" && raise(E_ASSERT, "All matches filter_chars failed, got " + toliteral(result));
  endverb

  verb test_match_objid_numeric (this none this) owner: HACKER flags: "rxd"
    "Ensure match_objid identifies numeric object identifiers.";
    result = this:match_objid("#42");
    if (!result)
      raise(E_ASSERT("no numeric match: " + toliteral(result)));
    endif
    result['type] != 'numbered || result['text] != "#42" || result['start] != 1 || result['end] != 3 && raise(E_ASSERT("numeric mismatch: " + toliteral(result)));
    result = this:match_objid("Before #123 after");
    !result || result['type] != 'numbered || result['text] != "#123" || result['start] != 8 || result['end] != 11 && raise(E_ASSERT("context mismatch: " + toliteral(result)));
    result = this:match_objid("   #77   ", true);
    !result || result['type] != 'numbered || result['start] != 4 || result['end] != 6 && raise(E_ASSERT("anchored mismatch: " + toliteral(result)));
    this:match_objid("no ids here") && raise(E_ASSERT);
    this:match_objid("#notanumber") && raise(E_ASSERT);
    return true;
  endverb

  verb test_match_objid_uuid (this none this) owner: HACKER flags: "rxd"
    "Ensure match_objid identifies UUID-style object identifiers.";
    uuid_str = "#00007D-99E53ABE55";
    result = this:match_objid(uuid_str);
    !result || result['type] != 'uuid || result['text] != uuid_str || result['start] != 1 || result['end] != 18 && raise(E_ASSERT("uuid mismatch: " + toliteral(result)));
    mixed = "prefix " + uuid_str + " suffix";
    result = this:match_objid(mixed);
    !result || result['start] != 8 || result['end] != 25 && raise(E_ASSERT);
    result = this:match_objid(uuid_str[2..$]);
    result && raise(E_ASSERT);
    return true;
  endverb

  verb test_parse_name_aliases (this none this) owner: HACKER flags: "rxd"
    "Test colon-separated format (name:alias,alias)";
    {primary, aliases} = this:parse_name_aliases("lamp:light, lamp,shiny");
    primary != "lamp" && raise(E_ASSERT, "Primary should be 'lamp': " + toliteral(primary));
    aliases != {"light", "shiny"} && raise(E_ASSERT, "Aliases dedupe/trim failed: " + toliteral(aliases));
    {primary, aliases} = this:parse_name_aliases(":alpha,beta");
    primary != "alpha" && raise(E_ASSERT, "First alias should become primary when name missing: " + toliteral(primary));
    aliases != {"beta"} && raise(E_ASSERT, "Remaining alias list incorrect: " + toliteral(aliases));
    {primary, aliases} = this:parse_name_aliases("Porcupine:\"Karl Porcupine\",\"You can pet this Porcupine, I bet!\"");
    primary != "Porcupine" && raise(E_ASSERT, "Quoted name parsing wrong: " + toliteral(primary));
    aliases != {"Karl Porcupine", "You can pet this Porcupine, I bet!"} && raise(E_ASSERT, "Quoted alias handling failed: " + toliteral(aliases));
    {primary, aliases} = this:parse_name_aliases("\"Standalone Thing\"");
    primary != "Standalone Thing" && raise(E_ASSERT, "Standalone quoted name parsing failed: " + toliteral(primary));
    aliases != {} && raise(E_ASSERT, "Standalone quoted name should not record aliases: " + toliteral(aliases));
    "Test comma-only format (name,alias,alias) - LambdaCore style";
    {primary, aliases} = this:parse_name_aliases("test,bonk");
    primary != "test" && raise(E_ASSERT, "Comma format: primary should be 'test': " + toliteral(primary));
    aliases != {"bonk"} && raise(E_ASSERT, "Comma format: aliases should be {\"bonk\"}: " + toliteral(aliases));
    {primary, aliases} = this:parse_name_aliases("lamp,light,shiny");
    primary != "lamp" && raise(E_ASSERT, "Comma format: primary should be 'lamp': " + toliteral(primary));
    aliases != {"light", "shiny"} && raise(E_ASSERT, "Comma format: aliases failed: " + toliteral(aliases));
    {primary, aliases} = this:parse_name_aliases("\"Quoted Thing\",alias1,alias2");
    primary != "Quoted Thing" && raise(E_ASSERT, "Comma format: quoted primary failed: " + toliteral(primary));
    aliases != {"alias1", "alias2"} && raise(E_ASSERT, "Comma format: quoted with aliases failed: " + toliteral(aliases));
    "Empty/whitespace tests";
    {primary, aliases} = this:parse_name_aliases("  ");
    primary != "" && raise(E_ASSERT, "Blank spec should return empty primary: " + toliteral(primary));
    aliases != {} && raise(E_ASSERT, "Blank spec should have empty alias list: " + toliteral(aliases));
    return true;
  endverb

  verb indefinite_article (this none this) owner: HACKER flags: "rxd"
    "Return the appropriate indefinite article ('a' or 'an') for this string based on first letter.";
    s = args[1];
    typeof(s) == STR || raise(E_TYPE("Expected string"));
    !s && return "a";
    first_char = s[1..1]:lowercase();
    return first_char in {"a", "e", "i", "o", "u"} ? "an" | "a";
  endverb

  verb with_indefinite_article (this none this) owner: HACKER flags: "rxd"
    "Return this string prefixed with the appropriate indefinite article.";
    s = args[1];
    typeof(s) == STR || raise(E_TYPE("Expected string"));
    !s && return "a ";
    return s:indefinite_article() + " " + s;
  endverb
endobject