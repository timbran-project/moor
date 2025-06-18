object STR_PROTO
  name: "String Utilities"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property _character_set (owner: HACKER, flags: "rc") = "	 !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
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
  property tab (owner: HACKER, flags: "rc") = "	";

  verb "capitalize capitalise" (this none this) owner: HACKER flags: "rxd"
    "Capitalizes its argument.";
    if ((string = args[1]) && (i = index("abcdefghijklmnopqrstuvwxyz", string[1], 1)))
      string[1] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i];
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
    return 0;
  endverb

  verb is_numeric (this none this) owner: HACKER flags: "rxd"
    "Usage:  is_numeric(string)";
    "Is string numeric (composed of one or more digits possibly preceded by a minus sign)?";
    "Return true or false.";
    return match(args[1], "^ *[-+]?[0-9]+ *$");
    digits = "1234567890";
    if (!(string = args[1]))
      return false;
    endif
    if (string[1] == "-")
      string = string[2..length(string)];
    endif
    for i in [1..length(string)]
      if (!index(digits, string[i]))
        return false;
      endif
    endfor
    return true;
  endverb

  verb literal_object (this none this) owner: HACKER flags: "rxd"
    string = args[1];
    if (!string)
      return $nothing;
    elseif (string[1] == "#" && E_TYPE != (object = this:toobj()))
      return object;
    elseif (string[1] == "~")
      return this:match_player(string[2..$], #0);
    elseif (string[1] == "*")
      return $mail_agent:match_recipient(string);
    elseif (string[1] == "$")
      string = string[2..$];
      object = #0;
    while properties(1)
        dot = index(string, ".");
        pn = dot ? string[1..dot - 1] | string;
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
    return n > 0 ? fill[1..n] | fill[(f = length(fill)) + 1 + n..f];
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
    while (i = index(subject, separator))
      parts = {@parts, subject[1..i - 1]};
      subject = subject[i + breaklen..$];
    endwhile
    return {@parts, subject};
  endverb

  verb toobj (this none this) owner: HACKER flags: "rxd"
    ":toobj(objectid as string) => objectid";
    return match(s = args[1], "^ *#[-+]?[0-9]+ *$") ? toobj(s) | E_TYPE;
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
    from = caps = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    to = lower = "abcdefghijklmnopqrstuvwxyz";
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
    "... find first nonspace...";
    wstart = match(rest, "[^ ]%|$")[1];
    wbefore = wstart - 1;
    rest[1..wbefore] = "";
    if (!rest)
      return {};
    endif
    quote = 0;
    wslist = {};
    pattern = " +%|\\.?%|\"";
    while (m = match(rest, pattern))
      "... find the next occurence of a special character, either";
      "... a block of spaces, a quote or a backslash escape sequence...";
      char = rest[m[1]];
      if (char == " ")
        wslist = {@wslist, {wstart, wbefore + m[1] - 1}};
        wstart = wbefore + m[2] + 1;
      elseif (char == "\"")
        "... beginning or end of quoted string...";
        "... within a quoted string spaces aren't special...";
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
    "...trim leading blanks...";
    rest[1..match(rest, "^ *")[2]] = "";
    if (!rest)
      return {};
    endif
    quote = 0;
    toklist = {};
    token = "";
    pattern = " +%|\\.?%|\"";
    while (m = match(rest, pattern))
      "... find the next occurence of a special character, either";
      "... a block of spaces, a quote or a backslash escape sequence...";
      char = rest[m[1]];
      token = token + rest[1..m[1] - 1];
      if (char == " ")
        toklist = {@toklist, token};
        token = "";
      elseif (char == "\"")
        "... beginning or end of quoted string...";
        "... within a quoted string spaces aren't special...";
        pattern = (quote = !quote) ? "\\.?%|\"" | " +%|\\.?%|\"";
      elseif (m[1] < m[2])
        "... char has to be a backslash...";
        "... include next char literally if there is one";
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
      pname = object[2..length(object)];
      if (!(pname in properties(#0)) || typeof(object = #0.(pname)) != OBJ)
        return false;
      endif
      object = tostr(object);
    endif
    return {object, tosym(verbname)};
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
      let {result, should} = {"$string:look_self":parse_verbref(), {"$string", 'look_self}};
      result != should && raise(E_ASSERT, "$string:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {"#1:look_self":parse_verbref(), {"#1", 'look_self}};
      result != should && raise(E_ASSERT, "#1:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
    begin
      let {result, should} = {"honk:look_self":parse_verbref(), {"honk", 'look_self}};
      result != should && raise(E_ASSERT, "honk:look_self should be " + toliteral(should) + " was: " + toliteral(result));
    end
  endverb
endobject
