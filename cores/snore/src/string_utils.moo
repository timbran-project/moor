object STRING_UTILS [
  import_export_id -> "string_utils"
]
  name: "string utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  property alphabet (owner: #2, flags: "rc") = "abcdefghijklmnopqrstuvwxyz";
  property ascii (owner: #2, flags: "rc") = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  property digits (owner: #2, flags: "rc") = "0123456789";
  property tab (owner: #2, flags: "rc") = "\t";
  property use_article_a (owner: HACKER, flags: "r") = {"unit", "unix", "one", "once", "utility"};
  property use_article_an (owner: HACKER, flags: "r") = {};

  override aliases (owner: #2, flags: "rc") = {"string", "utils"};
  override description (owner: #2, flags: "rc") = {
    "This is the string utilities utility package.  See `help $string_utils' for more details."
  };
  override help_msg (owner: #2, flags: "rc") = {
    "For a complete description of a given verb, do `help $string_utils:verbname'",
    "",
    "    Conversion routines:",
    "",
    ":from_list    (list [,sep])                          => \"foo1foo2foo3\"",
    ":english_list (str-list[,none-str[,and-str[, sep]]]) => \"foo1, foo2, and foo3\"",
    ":title_list*c (obj-list[,none-str[,and-str[, sep]]]) => \"foo1, foo2, and foo3\"",
    "                                                  or => \"Foo1, foo2, and foo3\"",
    ":from_value   (value [,quoteflag [,maxlistdepth]])   => \"{foo1, foo2, foo3}\"",
    ":print        (value)                                => value in string",
    ":abbreviated_value (value, options)                  => short value in string",
    "",
    ":to_value       (string)     => {boolean success, value or error message}",
    "Parses data literals without executing code, including maps, booleans, and UUID objects.",
    ":prefix_to_value(string)     => {rest of string, value} or {0, error message}",
    "",
    ":english_number(42)          => \"forty-two\"",
    ":english_ordinal(42)         => \"forty-second\"",
    ":ordinal(42)                 => \"42nd\"",
    ":group_number(42135 [,sep])  => \"42,135\"",
    ":from_ASCII(65)              => \"A\"",
    ":to_ASCII(\"A\")               => 65",
    ":from_seconds(number)        => string of rough time passed in large increments",
    "",
    ":name_and_number(obj [,sep]) => \"ObjectName (#obj)\"",
    ":name_and_number_list({obj1,obj2} [,sep])",
    "                             => \"ObjectName1 (#obj1) and ObjectName2 (#obj2)\"",
    ":nn is an alias for :name_and_number.",
    ":nn_list is an alias for :name_and_number_list.",
    "",
    "    Type checking:",
    "",
    ":is_integer   (string) => return true if string is composed entirely of digits",
    ":is_float     (string) => return true if string holds just a floating point",
    "",
    "    Parsing:",
    "",
    ":explode (string,char) -- string => list of words delimited by char",
    ":words   (string)      -- string => list of words (as with command line parser)",
    ":word_start (string)   -- string => list of start-end pairs.",
    ":first_word (string)   -- string => list {first word, rest of string} or {}",
    ":char_list  (string)   -- string => list of characters in string",
    "",
    ":parse_command (cmd_line [,player] => mimics action of builtin parser",
    "",
    "    Matching:",
    "",
    ":find_prefix  (prefix, string-list)=>list index of element starting with prefix",
    ":index_delimited(string,target[,case]) =>index of delimited string occurrence",
    ":index_all    (string, target string)          => list of all matched positions",
    ":common       (first string, second string)  => length of longest common prefix",
    ":match        (string, [obj-list, prop-name]+) => matching object",
    ":match_player (string-list[,me-object])        => list of matching players",
    ":match_object (string, location)               => default object match...",
    ":match_player_or_object (string, location) => object then player matching",
    ":literal_object (string)                       => match against #xxx, $foo",
    ":match_stringlist (string, targets)            => match against static strings",
    ":match_string (string, wildcard target,options)=> match against a wildcard",
    "",
    "    Pretty printing:",
    "",
    ":space         (n/string[,filler])     => n spaces",
    ":left          (string,width[,filler]) => left justified string in field ",
    ":right         (string,width[,filler]) => right justified string in field",
    ":center/re     (string,width[,lfiller[,rfiller]]) => centered string in field",
    ":columnize/se  (list,n[,width])        => list of strings in n columns",
    "",
    "    Substitutions",
    "",
    ":substitute (string,subst_list [,case])   -- general substitutions.",
    ":substitute_delimited (string,subst_list [,case])",
    "                                          -- like subst, but uses index_delim",
    ":pronoun_sub (string/list[,who[,thing[,location]]])",
    "                                          -- pronoun substitutions.",
    ":pronoun_sub_secure (string[,who[,thing[,location]]],default)",
    "                                          -- substitute and check for names.",
    ":pronoun_quote (string/list/subst_list)   -- quoting for pronoun substitutions.",
    "",
    "    Miscellaneous string munging:",
    "",
    ":trim         (string)       => string with outside whitespace removed.",
    ":triml        (string)       => string with leading whitespace removed.",
    ":trimr        (string)       => string with trailing whitespace removed.",
    ":strip_chars  (string,chars) => string with all chars in `chars' removed.",
    ":strip_all_but(string,chars) => string with all chars not in `chars' removed.",
    ":capitalize/se(string)       => string with first letter capitalized.",
    ":uppercase/lowercase(string) => string with all letters upper or lowercase.",
    ":names_of     (list of OBJ)  => string with names and object numbers of items.",
    ":a_or_an      (word)         => \"a\" or \"an\" as appropriate for that word.",
    ":reverse      (string)       => \"gnirts\"",
    ":incr_alpha   (string)       => \"increments\" the string alphabetically",
    "",
    "    A useful property:",
    "",
    ".alphabet                    => \"abcdefghijklmnopqrstuvwxyz\"",
    "",
    "Suspended versions (with _suspended at end of name) for",
    "     :print     :from_value     :columnize/se      :match"
  };
  override object_size (owner: HACKER, flags: "r") = {76712, 1084848672};

  method space owner: HACKER
    "Return abs(width) filler characters; negative widths anchor the filler on the right.";
    "A string width means its length. Return E_INVARG for widths over 1000 or empty filler.";
    let {width, ?fill = " "} = args;
    typeof(width) == TYPE_STR && (width = length(width));
    width > 1000 || width < -1000 || fill == "" && return E_INVARG;
    const count = abs(width);
    count == 0 && return "";
    while (length(fill) < count)
      fill = fill + fill;
    endwhile
    return width > 0 ? fill[1..count] | fill[$ - count + 1..$];
  endmethod

  method left owner: HACKER
    "Pad text on the right to abs(width); a negative width also truncates long text.";
    const {text, width, ?fill = " "} = args;
    const output = tostr(text);
    const count = abs(width);
    length(output) < count && return output + this:space(length(output) - count, fill);
    return width > 0 ? output | output[1..count];
  endmethod

  method right owner: HACKER
    "Pad text on the left to abs(width); a negative width also truncates on the left.";
    const {text, width, ?fill = " "} = args;
    const output = tostr(text);
    const count = abs(width);
    length(output) < count && return this:space(count - length(output), fill) + output;
    return width > 0 ? output | output[$ - count + 1..$];
  endmethod

  method "centre center" owner: HACKER
    "Center text in abs(width); negative width also truncates long text on the right.";
    "An odd padding character goes on the right. Each side can use its own filler.";
    const {text, width, ?left_fill = " ", ?right_fill = left_fill} = args;
    const output = tostr(text);
    const count = abs(width);
    const padding = count - length(output);
    if (padding > 0)
      return this:space(padding / 2, left_fill) + output + this:space(-(padding + 1) / 2, right_fill);
    endif
    return width > 0 ? output | output[1..count];
  endmethod

  method "columnize columnise" owner: HACKER
    "Arrange items down columns, clipping each row to width (default 79).";
    let {items, columns, ?width = 79} = args;
    columns > 0 || raise(E_INVARG, "Column count must be positive.");
    width >= 0 || raise(E_INVARG, "Width must not be negative.");
    const height = (length(items) + columns - 1) / columns;
    items = {@items, @$list_utils:make(height * columns - length(items), "")};
    let result = {};
    for row in [1..height]
      let line = tostr(items[row]);
      for column in [1..columns - 1]
        const stop = 1 - (width + 1) * column / columns;
        line = tostr(this:left(line, stop), " ", items[row + column * height]);
      endfor
      result = {@result, line[1..min($, width)]};
    endfor
    return result;
  endmethod

  method from_list owner: HACKER
    "Join string representations of list elements with separator (default empty).";
    const {items, ?separator = ""} = args;
    separator == "" && return tostr(@items);
    !items && return "";
    let result = tostr(items[1]);
    for item in (items[2..$])
      result = tostr(result, separator, item);
    endfor
    return result;
  endmethod

  method english_list owner: HACKER
    "Format a list as English text, with configurable empty, conjunction, and comma strings.";
    const {items, ?empty = "nothing", ?conjunction = " and ", ?separator = ", ", ?final_separator = ","} = args;
    const count = length(items);
    count == 0 && return empty;
    count == 1 && return tostr(items[1]);
    count == 2 && return tostr(items[1], conjunction, items[2]);
    return tostr(this:from_list(items[1..$ - 1], separator), final_separator, conjunction, items[$]);
  endmethod

  method names_of owner: HACKER
    "Join valid objects' names and opaque identifiers, separating entries with three spaces.";
    const {items} = args;
    const names = { tostr(item.name, "(", item, ")") for item in (items) if typeof(item) == TYPE_OBJ && valid(item) };
    return this:from_list(names, "   ");
  endmethod

  method from_seconds owner: HACKER
    "Describe elapsed seconds using the largest whole unit: days, hours, minutes, or seconds.";
    const {seconds} = args;
    for unit in ({{86400, "day", "a"}, {3600, "hour", "an"}, {60, "minute", "a"}, {1, "second", "a"}})
      if (seconds >= unit[1] || unit[1] == 1)
        const count = seconds / unit[1];
        return count == 1 ? unit[3] + " " + unit[2] | tostr(count, " ", unit[2], "s");
      endif
    endfor
  endmethod

  method trim owner: HACKER
    "Remove leading and trailing copies of one literal character (default space).";
    const {text, ?char = " "} = args;
    length(char) == 1 || raise(E_INVARG, "The trim character must have length one.");
    let first = 1;
    let last = length(text);
    while (first <= last && text[first] == char)
      first = first + 1;
    endwhile
    while (last >= first && text[last] == char)
      last = last - 1;
    endwhile
    return text[first..last];
  endmethod

  method triml owner: HACKER
    "Remove leading copies of one literal character (default space).";
    const {text, ?char = " "} = args;
    length(char) == 1 || raise(E_INVARG, "The trim character must have length one.");
    let first = 1;
    const last = length(text);
    while (first <= last && text[first] == char)
      first = first + 1;
    endwhile
    return text[first..last];
  endmethod

  method trimr owner: HACKER
    "Remove trailing copies of one literal character (default space).";
    const {text, ?char = " "} = args;
    length(char) == 1 || raise(E_INVARG, "The trim character must have length one.");
    const first = 1;
    let last = length(text);
    while (last >= first && text[last] == char)
      last = last - 1;
    endwhile
    return text[first..last];
  endmethod

  method strip_chars owner: HACKER
    "Remove all listed characters from text, using case-insensitive matching.";
    let {text, characters} = args;
    for position in [1..length(characters)]
      text = strsub(text, characters[position], "");
    endfor
    return text;
  endmethod

  method strip_all_but owner: HACKER
    "Keep runs matching a MOO regex character class. The second argument is class syntax.";
    "Put ] first, ^ anywhere except first, and - last when those characters are literal.";
    const {text, character_class} = args;
    return this:strip_all_but_seq(text, "[" + character_class + "]+");
  endmethod

  method "uppercase lowercase" owner: HACKER
    "Translate ASCII letters to upper or lower case, leaving other characters unchanged.";
    const {text} = args;
    const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const lower = "abcdefghijklmnopqrstuvwxyz";
    return verb == "uppercase" ? strtr(text, lower, upper, true) | strtr(text, upper, lower, true);
  endmethod

  method "capitalize capitalise" owner: HACKER
    "Capitalize the first character when it is an ASCII lowercase letter.";
    let {text} = args;
    !text && return text;
    const position = index("abcdefghijklmnopqrstuvwxyz", text[1], true);
    position && (text[1] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[position]);
    return text;
  endmethod

  method literal_object owner: HACKER
    "Resolve numbered or UUID literals, $property paths, ~players, and *mailing lists.";
    "Return $nothing for empty text, or $failed_match when no literal matches.";
    const {text} = args;
    !text && return $nothing;
    if (text[1] == "#")
      const object = $code_utils:toobj(text);
      object != E_TYPE && return object;
    elseif (text[1] == "~")
      return this:match_player(text[2..$], #0);
    elseif (text[1] == "*" && length(text) > 1)
      return $mail_agent:match_recipient(text);
    elseif (text[1] == "$")
      let remaining = text[2..$];
      let object = #0;
      while (remaining)
        const dot = index(remaining, ".");
        const prop = remaining[1..dot ? dot - 1 | $];
        if (!prop)
          break;
        endif
        !$object_utils:has_property(object, prop) && return $failed_match;
        object = object.(prop);
        typeof(object) != TYPE_OBJ && return $failed_match;
        remaining = dot ? remaining[dot + 1..$] | "";
      endwhile
      return object == #0 ? $failed_match | object;
    endif
    return $failed_match;
  endmethod

  method match owner: HACKER
    "Match text against (objects, property) pairs; property values are strings or lists.";
    "Exact matches beat prefixes; repeated matches on the same object are not ambiguous.";
    "Return $nothing for empty text, $failed_match if absent, or $ambiguous_match.";
    const subject = args[1];
    !subject && return $nothing;
    let exact = $failed_match;
    let partial = $failed_match;
    for pair in [1..length(args) / 2]
      const objects = args[2 * pair];
      const prop = args[2 * pair + 1];
      for object in (typeof(objects) == TYPE_LIST ? objects | {objects})
        if (valid(object))
          let names = `object.(prop) ! E_PERM, E_PROPNF => {}';
          typeof(names) != TYPE_LIST && (names = {names});
          if (subject in names)
            exact != $failed_match && exact != object && return $ambiguous_match;
            exact = object;
          else
            for name in (names)
              if (index(name, subject) == 1)
                partial = partial == $failed_match || partial == object ? object | $ambiguous_match;
              endif
            endfor
          endif
        endif
      endfor
    endfor
    return exact != $failed_match ? exact | partial;
  endmethod

  method "match_str*ing" owner: HACKER
    "Match wildcard text, returning captures, 1 for a match without captures, or 0.";
    "Optional numbers/booleans select case sensitivity; an optional string selects the wildcard.";
    "Matching is greedy between literal pieces and does not backtrack.";
    let {text, pattern, @options} = args;
    let wildcard = "*";
    let case_sensitive = false;
    for option in (options)
      if (typeof(option) == TYPE_STR)
        wildcard = option;
      elseif (typeof(option) in {TYPE_INT, TYPE_BOOL})
        case_sensitive = !!option;
      endif
    endfor
    length(wildcard) == 1 || raise(E_INVARG, "Wildcard must be one character.");
    text = text + "&^%$";
    pattern = pattern + "&^%$";
    let captures = {};
    while (pattern)
      const delimiter = index(pattern, wildcard);
      const boundary = delimiter || length(pattern);
      const part = delimiter ? pattern[1..delimiter - 1] | pattern;
      const position = part == "" ? 1 | index(text, part, case_sensitive);
      !position && return 0;
      captures = {@captures, text[1..position - 1]};
      text = text[boundary + position - 1..$];
      pattern = pattern[boundary + 1..$];
    endwhile
    !captures && return text == "" ? 1 | 0;
    captures == {""} && return 1;
    return captures[1] == "" ? captures[2..$] | 0;
  endmethod

  method match_object owner: HACKER
    "Resolve literals, me/here, and inventory/room names using their match hooks.";
    "Exact names beat prefixes. Otherwise prefer an inventory match over a room match.";
    const {text, room, ?who = player} = args;
    const literal = this:literal_object(text);
    literal != $failed_match && return literal;
    text == "me" && return who;
    text == "here" && return room;
    const carried = who:match(text);
    if (valid(carried) && text in {@carried.aliases, carried.name} || !valid(room))
      return carried;
    endif
    const nearby = room:match(text);
    if (valid(nearby) && text in {@nearby.aliases, nearby.name} || carried == $failed_match)
      return nearby;
    endif
    return carried;
  endmethod

  method match_player owner: HACKER
    "Resolve name[, me], a list of names[, me], or several name arguments.";
    "The first form returns one object; the others return lists, preserving match sentinels.";
    let me = player;
    let names = args;
    let scalar = false;
    if (length(args) < 2 || typeof(args[2]) == TYPE_OBJ)
      length(args) > 1 && (me = args[2]);
      !valid(me) || !is_player(me) && (me = $failed_match);
      scalar = typeof(args[1]) == TYPE_STR;
      names = scalar ? {args[1]} | args[1];
    endif
    let result = {};
    for name in (names)
      let found = $nothing;
      if (name == "me")
        found = me;
      elseif (name)
        found = this:literal_object(name);
        !valid(found) || !is_player(found) && (found = $player_db:find(name));
      endif
      result = {@result, found};
    endfor
    return scalar ? result[1] | result;
  endmethod

  method match_player_or_object owner: HACKER
    "Resolve each argument in the room, then as a player; report failed matches to player.";
    "Return successful room matches followed by successful player matches; no arguments returns 0.";
    !args && return 0;
    let unknown = {};
    let result = {};
    for name in (args)
      const object = player.location:match_object(name);
      if (valid(object))
        result = {@result, object};
      else
        unknown = {@unknown, name};
      endif
    endfor
    const players = this:match_player(unknown);
    for position in [1..length(players)]
      if (valid(players[position]))
        result = {@result, players[position]};
      else
        player:tell("Could not find ", unknown[position], " as either an object or a player.");
      endif
    endfor
    return result;
  endmethod

  method find_prefix owner: HACKER
    "Return the index of a unique prefix match, 0 if absent, or $ambiguous_match.";
    const {subject, choices} = args;
    let found = 0;
    for position in [1..length(choices)]
      if (index(choices[position], subject) == 1)
        found != 0 && return $ambiguous_match;
        found = position;
      endif
    endfor
    return found;
  endmethod

  method "index_d*elimited" owner: HACKER
    "Find literal target at word boundaries, with optional case sensitivity; return index or 0.";
    const {text, target, ?case_sensitive = false} = args;
    const pattern = "%(%W%|^%)" + this:regexp_quote(target) + "%(%W%|$%)";
    const found = match(text, pattern, case_sensitive ? 1 | 0);
    return found ? found[3][1][2] + 1 | 0;
  endmethod

  method "is_integer is_numeric" owner: HACKER
    "Return whether text is a signed decimal integer, allowing surrounding spaces.";
    return !!match(args[1], "^ *[-+]?[0-9]+ *$");
  endmethod

  method ordinal owner: HACKER
    "Append st, nd, rd, or th to an integer, including negative values.";
    const {number} = args;
    const text = tostr(number);
    const ending = abs(number % 100);
    if (ending / 10 != 1 && ending % 10 in {1, 2, 3})
      return text + {"st", "nd", "rd"}[ending % 10];
    endif
    return text + "th";
  endmethod

  method group_number owner: HACKER
    "Group integer digits with separator; floats accept precision, scientific, and separator.";
    "Float formatting follows floatstr; fractional digits and exponents are left intact.";
    let text = "";
    let separator = ",";
    if (typeof(args[1]) == TYPE_INT)
      const {number, ?sep = ","} = args;
      separator = sep;
      text = tostr(number);
    elseif (typeof(args[1]) == TYPE_FLOAT)
      const {number, ?precision = 4, ?scientific = false, ?sep = ","} = args;
      separator = sep;
      text = floatstr(number, precision, scientific);
    else
      return E_INVARG;
    endif
    let sign = "";
    if (text[1] == "-")
      sign = "-";
      text = text[2..$];
    endif
    const boundary = min(index(text + ".", "."), index(text + "e", "e"));
    let result = text[boundary..$];
    let whole = text[1..boundary - 1];
    while (length(whole) > 3)
      result = separator + whole[$ - 2..$] + result;
      whole = whole[1..$ - 3];
    endwhile
    return sign + whole + result;
  endmethod

  method english_number owner: HACKER
    "Spell an integer in English, using groups through quintillions.";
    const number = toint(args[1]);
    number == 0 && return "zero";
    const labels = {"", " thousand", " million", " billion", " trillion", " quadrillion", " quintillion"};
    let remaining = number;
    let result = "";
    let group = 1;
    while (remaining != 0)
      const part = abs(remaining % 1000);
      if (part)
        const hundreds = part / 100;
        const tens = part % 100;
        let text = this:english_tens(tens) + labels[group];
        if (hundreds)
          text = this:english_ones(hundreds) + " hundred" + (tens ? " " | "") + text;
        endif
        result = text + (result ? " " + result | "");
      endif
      remaining = remaining / 1000;
      group = group + 1;
    endwhile
    return (number < 0 ? "negative " | "") + result;
  endmethod

  method english_ordinal owner: HACKER
    "Spell an integer ordinal in English, including zero and negative values.";
    const number = toint(args[1]);
    number == 0 && return "zeroth";
    const ending = abs(number % 100);
    ending == 0 && return this:english_number(number) + "th";
    let prefix = number < 0 ? "negative " | "";
    if (number / 100 != 0)
      prefix = this:english_number(number / 100 * 100) + " ";
    endif
    const specials = {1, 2, 3, 5, 8, 9, 12, 20, 30, 40, 50, 60, 70, 80, 90};
    const ordinals = {"first", "second", "third", "fifth", "eighth", "ninth", "twelfth", "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth"};
    const special = ending in specials;
    special && return prefix + ordinals[special];
    const last_special = ending % 10 in specials;
    if (ending > 20 && last_special)
      return prefix + this:english_tens(ending / 10 * 10) + "-" + ordinals[last_special];
    endif
    return prefix + this:english_number(ending) + "th";
  endmethod

  method english_ones owner: HACKER
    "Spell a digit; zero is empty for use within larger numbers.";
    const {number} = args;
    return {"", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"}[number + 1];
  endmethod

  method english_tens owner: HACKER
    "Spell a number from zero through 99; zero is empty.";
    const {number} = args;
    number < 10 && return this:english_ones(number);
    const teens = {"ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"};
    number < 20 && return teens[number - 9];
    const tens = {"twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"};
    return tens[number / 10 - 1] + (number % 10 ? "-" | "") + this:english_ones(number % 10);
  endmethod

  method "subst*itute" owner: HACKER
    "Apply {target, replacement} pairs in parallel; replacement text is never searched.";
    "Leftmost matches win; at the same position the longest target wins.";
    "An optional third argument selects case sensitivity. Empty targets raise E_INVARG.";
    let {text, substitutions, ?case_sensitive = false} = args;
    typeof(text) != TYPE_STR && return text;
    let remaining_length = length(text);
    let positions = {};
    let pending = {};
    for substitution in (substitutions)
      substitution[1] != "" || raise(E_INVARG, "Substitution targets must not be empty.");
      const found = index(text, substitution[1], case_sensitive);
      if (found)
        const relative = found - remaining_length;
        let insertion = $list_utils:find_insert(positions, relative) - 1;
        while (insertion > 0 && positions[insertion] == relative && length(pending[insertion][1]) < length(substitution[1]))
          insertion = insertion - 1;
        endwhile
        positions = listappend(positions, relative, insertion);
        pending = listappend(pending, substitution, insertion);
      endif
    endfor
    let result = "";
    while (pending)
      const position = remaining_length + positions[1];
      const substitution = pending[1];
      positions = positions[2..$];
      pending = pending[2..$];
      if (position > 0)
        result = result + text[1..position - 1] + substitution[2];
        text = text[position + length(substitution[1])..$];
        remaining_length = length(text);
      endif
      const found = index(text, substitution[1], case_sensitive);
      if (found)
        const relative = found - remaining_length;
        let insertion = $list_utils:find_insert(positions, relative) - 1;
        while (insertion > 0 && positions[insertion] == relative && length(pending[insertion][1]) < length(substitution[1]))
          insertion = insertion - 1;
        endwhile
        positions = listappend(positions, relative, insertion);
        pending = listappend(pending, substitution, insertion);
      endif
    endwhile
    return result + text;
  endmethod

  verb "substitute_d*elimited" (none none none) owner: #2 flags: "rxd"
    "Apply {target, replacement} pairs in parallel; replacement text is never searched.";
    "Leftmost matches win; at the same position the longest target wins.";
    "An optional third argument selects case sensitivity. Empty targets raise E_INVARG.";
    let {text, substitutions, ?case_sensitive = false} = args;
    typeof(text) != TYPE_STR && return text;
    let remaining_length = length(text);
    let positions = {};
    let pending = {};
    for substitution in (substitutions)
      substitution[1] != "" || raise(E_INVARG, "Substitution targets must not be empty.");
      const found = this:index_delimited(text, substitution[1], case_sensitive);
      if (found)
        const relative = found - remaining_length;
        let insertion = $list_utils:find_insert(positions, relative) - 1;
        while (insertion > 0 && positions[insertion] == relative && length(pending[insertion][1]) < length(substitution[1]))
          insertion = insertion - 1;
        endwhile
        positions = listappend(positions, relative, insertion);
        pending = listappend(pending, substitution, insertion);
      endif
    endfor
    let result = "";
    while (pending)
      const position = remaining_length + positions[1];
      const substitution = pending[1];
      positions = positions[2..$];
      pending = pending[2..$];
      if (position > 0)
        result = result + text[1..position - 1] + substitution[2];
        text = text[position + length(substitution[1])..$];
        remaining_length = length(text);
      endif
      const found = this:index_delimited(text, substitution[1], case_sensitive);
      if (found)
        const relative = found - remaining_length;
        let insertion = $list_utils:find_insert(positions, relative) - 1;
        while (insertion > 0 && positions[insertion] == relative && length(pending[insertion][1]) < length(substitution[1]))
          insertion = insertion - 1;
        endwhile
        positions = listappend(positions, relative, insertion);
        pending = listappend(pending, substitution, insertion);
      endif
    endwhile
    return result + text;
  endverb

  method _cap_property owner: #2
    "Read a pronoun property, applying capitalization or the explicit property+c override.";
    "Empty property uses title/titlec. Lists become English lists; errors are returned as values.";
    "Property reads and title hooks run with the caller's permissions.";
    let {object, prop, ?capitalize = false} = args;
    set_task_perms(caller_perms());
    if (typeof(object) == TYPE_LIST)
      return this:english_list({ this:_cap_property(item, prop, capitalize) for item in (object) });
    endif
    capitalize = prop != "" && strcmp(prop, "a") < 0 || capitalize;
    if (prop == "")
      !valid(object) && return capitalize ? "Nothing" | "nothing";
      return capitalize ? object:titlec() | object:title();
    endif
    let value = E_PROPNF;
    capitalize && (value = `object.(prop + "c") ! ANY');
    if (!capitalize || typeof(value) == TYPE_ERR)
      if (prop == "name")
        value = valid(object) ? object.name | "nothing";
        capitalize = capitalize && !is_player(object);
      else
        value = `$object_utils:has_property(object, prop) ? object.(prop) | $player.(prop) ! ANY';
      endif
      if (capitalize && typeof(value) == TYPE_STR)
        value = this:capitalize(value);
      endif
    endif
    return typeof(value) == TYPE_ERR ? value | tostr(value);
  endmethod

  method pronoun_sub owner: #2
    "Expand pronouns, titles, %[object-property] forms, and %<verb> substitutions.";
    "Arguments are text[, who[, thing[, location[, direct[, indirect]]]]]. Lists are processed";
    "line by line.";
    "Reads and user hooks run as $no_one. Hook calls can suspend and commit.";
    const {text, ?who = player, ?thing = caller, ?location = $nothing, ?direct = dobj, ?indirect = iobj} = args;
    const where = valid(location) ? location | valid(who) ? who.location | location;
    set_task_perms($no_one);
    if (typeof(text) == TYPE_LIST)
      return { this:(verb)(line, who, thing, where, direct, indirect) for line in (text) };
    endif
    const object_codes = "nditl";
    const objects = {who, direct, indirect, thing, where};
    const pronoun_codes = "sopqrSOPQR";
    const pronoun_properties = {"ps", "po", "pp", "pq", "pr", "Ps", "Po", "Pp", "Pq", "Pr"};
    let remaining = tostr(text);
    let result = "";
    while (true)
      const percent = index(remaining, "%");
      if (!percent || percent == length(remaining))
        break;
      endif
      let consumed = percent + 1;
      let replacement = remaining[consumed];
      const verb_end = replacement == "<" ? index(remaining[consumed + 2..$], ">") | 0;
      if (verb_end)
        const boundary = consumed + 1 + verb_end;
        let verb_name = remaining[consumed + 1..boundary - 1];
        let subject = who;
        if (length(verb_name) > 2 && verb_name[2] == ":")
          subject = objects[index(object_codes, verb_name[1]) || 1];
          verb_name = verb_name[3..$];
        endif
        replacement = $object_utils:has_callable_verb(subject, "verb_sub") ? subject:verb_sub(verb_name) | $gender_utils:get_conj(verb_name, subject);
        consumed = boundary;
      else
        let property_args = {};
        const bracket = index("([", replacement);
        const object_index = index(object_codes, replacement);
        const pronoun_index = index(pronoun_codes, replacement, true);
        if (bracket)
          const end = index(remaining[consumed + 1..$], ")]"[bracket]);
          !end && return result + remaining;
          const prop = remaining[consumed + 1..consumed + end - 1];
          consumed = consumed + end;
          if (bracket == 1)
            property_args = {who, prop};
          elseif (length(prop) >= 2 && prop[1] == "#")
            const target = index(object_codes, prop[2]);
            replacement = target ? tostr(objects[target]) | "[" + prop + "]";
          elseif (prop != "" && index(object_codes, prop[1]))
            property_args = {objects[index(object_codes, prop[1])], prop[2..$], strcmp(prop[1], "a") < 0};
          else
            replacement = "[" + prop + "]";
          endif
        elseif (object_index)
          property_args = {objects[object_index], "", strcmp(replacement, "a") < 0};
        elseif (pronoun_index)
          property_args = {who, pronoun_properties[pronoun_index]};
        elseif (replacement == "#")
          replacement = tostr(who);
        elseif (replacement != "%")
          replacement = "%" + replacement;
        endif
        if (property_args)
          const value = this:_cap_property(@property_args);
          replacement = typeof(value) == TYPE_ERR ? "%(" + tostr(value) + ")" | value;
        endif
      endif
      result = result + remaining[1..percent - 1] + replacement;
      remaining = remaining[consumed + 1..$];
    endwhile
    return result + remaining;
  endmethod

  method pronoun_sub_secure owner: HACKER
    "Substitute pronouns; use the final default argument if the result omits who's name.";
    "Arguments before default have the same meaning as in pronoun_sub.";
    const who = length(args) > 2 ? args[2] | player;
    const fallback = args[$];
    const result = this:pronoun_sub(@args[1..$ - 1]);
    this:index_delimited(result, who.name) && return result;
    return this:pronoun_sub(fallback, @args[2..$ - 1]);
  endmethod

  method pronoun_quote owner: HACKER
    "Escape percent signs for pronoun_sub in text, text lists, or {key, text} pairs.";
    const {value} = args;
    typeof(value) == TYPE_STR && return strsub(value, "%", "%%");
    let result = {};
    for item in (value)
      const quoted = typeof(item) == TYPE_LIST ? listset(item, strsub(item[2], "%", "%%"), 2) | strsub(item, "%", "%%");
      result = {@result, quoted};
    endfor
    return result;
  endmethod

  verb alt_pronoun_sub (none none none) owner: #2 flags: "rxd"
    "Expand pronouns, titles, %[object-property] forms, and %<verb> substitutions.";
    "Arguments are text[, who[, thing[, location]]]. Lists are processed line by line.";
    "Reads and user hooks run as $no_one. Hook calls can suspend and commit.";
    const {text, ?who = player, ?thing = caller, ?location = $nothing} = args;
    const where = valid(who) ? who.location | location;
    set_task_perms($no_one);
    if (typeof(text) == TYPE_LIST)
      return { this:(verb)(line, who, thing, where) for line in (text) };
    endif
    const object_codes = "nditl";
    const objects = {who, dobj, iobj, thing, where};
    const pronoun_codes = "sopqrSOPQR";
    const pronoun_properties = {"ps", "po", "pp", "pq", "pr", "Ps", "Po", "Pp", "Pq", "Pr"};
    let remaining = tostr(text);
    let result = "";
    while (true)
      const percent = index(remaining, "%");
      if (!percent || percent == length(remaining))
        break;
      endif
      let consumed = percent + 1;
      let replacement = remaining[consumed];
      const verb_end = replacement == "<" ? index(remaining[consumed + 2..$], ">") | 0;
      if (verb_end)
        const boundary = consumed + 1 + verb_end;
        let verb_name = remaining[consumed + 1..boundary - 1];
        let subject = who;
        if (length(verb_name) > 2 && verb_name[2] == ":")
          subject = objects[index(object_codes, verb_name[1]) || 1];
          verb_name = verb_name[3..$];
        endif
        replacement = $object_utils:has_verb(subject, "verb_sub") ? subject:verb_sub(verb_name) | this:(verb)(verb_name, subject);
        consumed = boundary;
      else
        let property_args = {};
        const bracket = index("([", replacement);
        const object_index = index(object_codes, replacement);
        const pronoun_index = index(pronoun_codes, replacement, true);
        if (bracket)
          const end = index(remaining[consumed + 1..$], ")]"[bracket]);
          !end && return result + remaining;
          const prop = remaining[consumed + 1..consumed + end - 1];
          consumed = consumed + end;
          if (bracket == 1)
            property_args = {who, prop};
          elseif (length(prop) >= 2 && prop[1] == "#")
            const target = index(object_codes, prop[2]);
            replacement = target ? tostr(objects[target]) | "[" + prop + "]";
          elseif (prop != "" && index(object_codes, prop[1]))
            property_args = {objects[index(object_codes, prop[1])], prop[2..$], strcmp(prop[1], "a") < 0};
          else
            replacement = "[" + prop + "]";
          endif
        elseif (object_index)
          property_args = {objects[object_index], "", strcmp(replacement, "a") < 0};
        elseif (pronoun_index)
          property_args = {who, pronoun_properties[pronoun_index]};
        elseif (replacement == "#")
          replacement = tostr(who);
        elseif (replacement != "%")
          replacement = "%" + replacement;
        endif
        if (property_args)
          const value = this:_cap_property(@property_args);
          replacement = typeof(value) == TYPE_ERR ? "%(" + tostr(value) + ")" | value;
        endif
      endif
      result = result + remaining[1..percent - 1] + replacement;
      remaining = remaining[consumed + 1..$];
    endwhile
    return result + remaining;
  endverb

  method explode owner: HACKER
    "Split text on runs of delimiter[1], default space, omitting empty fields.";
    let {text, ?delimiter = " "} = args;
    delimiter = delimiter[1];
    text = text + delimiter;
    let result = {};
    while (text)
      const boundary = index(text, delimiter);
      boundary > 1 && (result = {@result, text[1..boundary - 1]});
      text = text[boundary + 1..$];
    endwhile
    return result;
  endmethod

  method words owner: HACKER
    "Split command text into arguments, interpreting double quotes and backslash escapes.";
    const {text} = args;
    let result = {};
    let token = "";
    let quoted = false;
    let escaped = false;
    let started = false;
    for position in [1..length(text)]
      const char = text[position];
      if (escaped)
        token = token + char;
        escaped = false;
      elseif (char == "\\")
        escaped = true;
        started = true;
      elseif (char == "\"")
        quoted = !quoted;
        started = true;
      elseif (char == " " && !quoted)
        started && (result = {@result, token});
        token = "";
        started = false;
      else
        token = token + char;
        started = true;
      endif
    endfor
    started && (result = {@result, token});
    return result;
  endmethod

  method word_start owner: HACKER
    "Return inclusive character spans for command arguments, including quotes and escapes.";
    const {text} = args;
    let result = {};
    let start = 0;
    let quoted = false;
    let escaped = false;
    for position in [1..length(text)]
      const char = text[position];
      if (escaped)
        escaped = false;
      elseif (char == "\\")
        escaped = true;
      elseif (char == "\"")
        quoted = !quoted;
      elseif (char == " " && !quoted)
        if (start)
          result = {@result, {start, position - 1}};
          start = 0;
        endif
        continue;
      endif
      !start && (start = position);
    endfor
    start && (result = {@result, {start, length(text)}});
    return result;
  endmethod

  method to_value owner: HACKER
    "Parse one mooR data literal without evaluating code; return {success, value_or_message}.";
    "Accept booleans, maps, symbols, and UUID objects as well as classic MOO values.";
    const {text} = args;
    try
      return {true, fromliteral(text)};
    except problem (E_INVARG)
      return {false, problem[2]};
    endtry
  endmethod

  method prefix_to_value owner: HACKER
    "Parse an initial data literal; return {remaining_text, value} or {0, message, position}.";
    "Lists, maps, and strings end at their closing delimiter; scalars end at the next space.";
    const {input} = args;
    const text = this:triml(input);
    !text && return {0, "empty string"};
    let boundary = length(text);
    if (index("{[\"", text[1]))
      let nesting = "";
      let quoted = false;
      let escaped = false;
      for position in [1..length(text)]
        const char = text[position];
        if (escaped)
          escaped = false;
        elseif (quoted && char == "\\")
          escaped = true;
        elseif (char == "\"")
          quoted = !quoted;
        elseif (!quoted && index("{[", char))
          nesting = char + nesting;
        elseif (!quoted && index("}]", char))
          const expected = "{["[index("}]", char)];
          if (!nesting || nesting[1] != expected)
            return {0, "mismatched delimiter", length(input) - length(text) + position};
          endif
          nesting = nesting[2..$];
        endif
        if (!quoted && !nesting)
          boundary = position;
          break;
        endif
      endfor
    else
      boundary = index(text + " ", " ") - 1;
    endif
    const parsed = this:to_value(text[1..boundary]);
    !parsed[1] && return {0, parsed[2], length(input) - length(text) + 1};
    return {text[boundary + 1..$], parsed[2]};
  endmethod

  method _tolist owner: HACKER
    "Parse list contents after an opening brace; return {remaining_text, list}.";
    "On failure return {remaining_length, message}; zero denotes a missing closing delimiter.";
    let remaining = this:triml(args[1]);
    let values = {};
    !remaining && return {0, values};
    remaining[1] == "}" && return {remaining[2..$], values};
    while (true)
      const length_before = length(remaining);
      const form = index("{\"", remaining[1]);
      if (form)
        const parsed = this:({"_tolist", "_unquote"}[form])(remaining[2..$]);
        typeof(parsed[1]) == TYPE_INT && return parsed;
        values = {@values, parsed[2]};
        remaining = parsed[1];
      else
        const boundary = min(index(remaining + ",", ","), index(remaining + "}", "}"));
        const value = this:_toscalar(remaining[1..boundary - 1]);
        typeof(value) == TYPE_STR && return {length_before, value};
        values = {@values, value};
        remaining = remaining[boundary..$];
      endif
      !remaining && return {0, values};
      remaining[1] == "}" && return {remaining[2..$], values};
      remaining[1] != "," && return {length(remaining), ", or } expected"};
      remaining = this:triml(remaining[2..$]);
      !remaining && return {0, values};
    endwhile
  endmethod

  method _unquote owner: HACKER
    "Parse text following an opening quote; return {remainder, unescaped_text}.";
    "Return {0, unescaped_text} when the closing quote is missing.";
    const {text} = args;
    let result = "";
    let escaped = false;
    for position in [1..length(text)]
      const char = text[position];
      if (escaped)
        result = result + char;
        escaped = false;
      elseif (char == "\\")
        escaped = true;
      elseif (char == "\"")
        return {text[position + 1..$], result};
      else
        result = result + char;
      endif
    endfor
    return {0, result};
  endmethod

  method _toscalar owner: HACKER
    "Parse a scalar literal; return a string error message on failure.";
    "Strings and collections are handled by the enclosing parser.";
    let TYPE_SYMBOL;
    const {text} = args;
    !text && return "missing value";
    const parsed = this:to_value(text);
    !parsed[1] && return parsed[2];
    const value = parsed[2];
    typeof(value) in {TYPE_INT, TYPE_FLOAT, TYPE_OBJ, TYPE_ERR, TYPE_BOOL, TYPE_SYMBOL} && return value;
    return "scalar value expected";
  endmethod

  method parse_command owner: #2
    "Return the LambdaCore command tuple, using the server parser and room matching hooks.";
    "Result: {verb, {dobj, text}, {prep, text}, {iobj, text}, {args, argstr}, {dset, pset, iset}}.";
    const {line, ?who = player} = args;
    !this:words(line) && return {};
    const parsed = parse_command(line, {});
    const direct_text = parsed['dobjstr];
    const indirect_text = parsed['iobjstr];
    const prep_text = parsed['prepstr];
    const location = who.location;
    set_task_perms(caller_perms());
    player = who;
    const direct = valid(location) ? location:match_object(direct_text) | this:match_object(direct_text, location, who);
    const indirect = prep_text == "" ? $nothing | valid(location) ? location:match_object(indirect_text) | this:match_object(indirect_text, location, who);
    const direct_specs = direct_text == "" ? {"any", "none"} | {"any"};
    const indirect_specs = indirect_text == "" ? {"any", "none"} | {"any"};
    const prep_specs = prep_text == "" ? {"any", "none"} | {"any", $code_utils:full_prep(prep_text)};
    return {tostr(parsed['verb]), {direct, direct_text}, {$code_utils:short_prep(prep_text), prep_text}, {indirect, indirect_text}, {parsed['args], parsed['argstr]}, {direct_specs, prep_specs, indirect_specs}};
  endmethod

  method from_value owner: #2
    "Format a value, optionally quoting strings and limiting list depth (default one).";
    "A depth of zero abbreviates nonempty lists; negative depth expands all levels.";
    const {value, ?quote_strings = false, ?list_depth = 1} = args;
    if (typeof(value) == TYPE_LIST)
      !value && return "{}";
      list_depth == 0 && return "{...}";
      let parts = {};
      for item in (value)
        parts = {@parts, this:from_value(item, quote_strings, list_depth - 1)};
      endfor
      return "{" + this:from_list(parts, ", ") + "}";
    endif
    return quote_strings ? toliteral(value) | tostr(value);
  endmethod

  method "print print_suspended" owner: HACKER
    "Return the literal representation of value. The suspended alias needs no yield.";
    return toliteral(args[1]);
  endmethod

  method reverse owner: HACKER
    "Reverse text by Unicode code points using the native sequence operation.";
    const {text} = args;
    typeof(text) == TYPE_STR || raise(E_TYPE);
    return reverse(text);
  endmethod

  method char_list owner: HACKER
    "Return the characters of text as a list, in order.";
    const {text} = args;
    return { text[position] for position in [1..length(text)] };
  endmethod

  method regexp_quote owner: HACKER
    "Escape MOO regular-expression metacharacters so text can be matched literally.";
    const {text} = args;
    let result = "";
    for position in [1..length(text)]
      const char = text[position];
      index("[]$^.*+?%", char) && (result = result + "%");
      result = result + char;
    endfor
    return result;
  endmethod

  method connection_hostname_bsd owner: HACKER
    "Extract the host from a BSD-style connection description; return empty on failure.";
    const found = `match(args[1], "^.* %(from%|to%) %([^, ]+%)") ! ANY => {}';
    return found ? substitute("%2", found) | "";
  endmethod

  method connection_hostname owner: HACKER
    "Extract a host name from the connection description using the configured format helper.";
    return this:connection_hostname_bsd(@args);
  endmethod

  method from_value_suspended owner: #2
    "Format a value, optionally quoting strings and limiting list depth (default one).";
    "A depth of zero abbreviates nonempty lists; negative depth expands all levels.";
    "Budget yields between list items commit the transaction; input values are local snapshots.";
    set_task_perms(caller_perms());
    const {value, ?quote_strings = false, ?list_depth = 1} = args;
    if (typeof(value) == TYPE_LIST)
      !value && return "{}";
      list_depth == 0 && return "{...}";
      let parts = {};
      for item in (value)
        parts = {@parts, this:from_value_suspended(item, quote_strings, list_depth - 1)};
        $command_utils:suspend_if_needed(0);
      endfor
      return "{" + this:from_list(parts, ", ") + "}";
    endif
    return quote_strings ? toliteral(value) | tostr(value);
  endmethod

  method end_expression owner: HACKER
    "Return the final position before a top-level stop character (default space).";
    "Return 0 for mismatched brackets or unterminated quotes; this does not validate MOO syntax.";
    const {text, ?stop_at = " "} = args;
    let nesting = "";
    let quoted = false;
    let escaped = false;
    for position in [1..length(text)]
      const char = text[position];
      if (quoted)
        if (escaped)
          escaped = false;
        elseif (char == "\\")
          escaped = true;
        elseif (char == "\"")
          quoted = false;
        endif
      elseif (char == "\"")
        quoted = true;
      elseif (index("([{", char))
        nesting = char + nesting;
      elseif (index(")]}", char))
        const expected = "([{"[index(")]}", char)];
        !nesting || nesting[1] != expected && return 0;
        nesting = nesting[2..$];
      elseif (!nesting && index(stop_at, char))
        return position - 1;
      endif
    endfor
    return quoted || nesting != "" ? 0 | length(text);
  endmethod

  method first_word owner: HACKER
    "Return {first command argument, remaining text}, or {} for blank input.";
    const {text} = args;
    const spans = this:word_start(text);
    !spans && return {};
    const first = spans[1];
    return {this:words(text[first[1]..first[2]])[1], this:triml(text[first[2] + 1..$])};
  endmethod

  method common owner: HACKER
    "Return the length of the longest case-insensitive common prefix.";
    const {first, second} = args;
    let high = min(length(first), length(second));
    let low = 1;
    while (high >= low)
      const middle = (high + low) / 2;
      if (first[low..middle] == second[low..middle])
        low = middle + 1;
      else
        high = middle - 1;
      endif
    endwhile
    return high;
  endmethod

  method "title_list*c list_title*c" owner: HACKER
    "Format object titles as an English list; the c aliases capitalize the first title.";
    "Remaining arguments are passed to english_list.";
    const objects = args[1];
    let english_args = args[2..$];
    const titles = $list_utils:map_verb(objects, "title");
    if (verb[$] == "c")
      if (titles)
        titles[1] = objects[1]:titlec();
      elseif (english_args)
        english_args[1] = this:capitalize(english_args[1]);
      else
        english_args = {"Nothing"};
      endif
    endif
    return this:english_list(titles, @english_args);
  endmethod

  method "name_and_number nn name_and_number_list nn_list" owner: HACKER
    "Format an object or object list as names with opaque identifiers in parentheses.";
    "The second argument separates name from identifier; remaining arguments go to english_list.";
    const {objects, ?separator = " ", @english_args} = args;
    let names = {};
    for object in (typeof(objects) == TYPE_LIST ? objects | {objects})
      const name = valid(object) ? object.name | {"<invalid>", "$nothing", "$ambiguous_match", "$failed_match"}[1 + (object in {$nothing, $ambiguous_match, $failed_match})];
      names = {@names, tostr(name, separator, "(", object, ")")};
    endfor
    return this:english_list(names, @english_args);
  endmethod

  method "columnize_suspended columnise_suspended" owner: HACKER
    "Arrange items down columns, clipping each row to width (default 79).";
    "The first argument is the budget-yield delay; each yield commits the transaction.";
    let {interval, items, columns, ?width = 79} = args;
    columns > 0 || raise(E_INVARG, "Column count must be positive.");
    width >= 0 || raise(E_INVARG, "Width must not be negative.");
    const height = (length(items) + columns - 1) / columns;
    items = {@items, @$list_utils:make(height * columns - length(items), "")};
    let result = {};
    for row in [1..height]
      let line = tostr(items[row]);
      for column in [1..columns - 1]
        const stop = 1 - (width + 1) * column / columns;
        line = tostr(this:left(line, stop), " ", items[row + column * height]);
      endfor
      result = {@result, line[1..min($, width)]};
      $command_utils:suspend_if_needed(interval);
    endfor
    return result;
  endmethod

  method a_or_an owner: HACKER
    "Choose an indefinite article, honoring player:a_or_an and the article exception lists.";
    "A player's hook returns 0 to request the default rules.";
    const {noun} = args;
    if ($object_utils:has_verb(player, "a_or_an"))
      const custom = player:a_or_an(noun);
      custom != 0 && return custom;
    endif
    noun in this.use_article_a && return "a";
    noun in this.use_article_an && return "an";
    !noun || !index("aeiou", noun[1]) && return "a";
    if (length(noun) > 2 && noun[1..2] == "un")
      !index("aeiou", noun[3]) && return "a";
      if (noun[3] == "i" && length(noun) > 3)
        index("aeioubcghqwyz", noun[4]) && return "a";
        length(noun) > 4 && index("eiy", noun[5]) && return "a";
      endif
    endif
    return "an";
  endmethod

  method index_all owner: HACKER
    "Return nonoverlapping literal match positions; return E_TYPE for nonstrings.";
    "An empty target has no occurrences.";
    const {text, target} = args;
    typeof(text) != TYPE_STR || typeof(target) != TYPE_STR && return E_TYPE;
    !target && return {};
    let result = {};
    let offset = 0;
    while (offset < length(text))
      const position = index(text[offset + 1..$], target);
      if (!position)
        break;
      endif
      result = {@result, offset + position};
      offset = offset + position + length(target) - 1;
    endwhile
    return result;
  endmethod

  method "match_stringlist match_string_list" owner: HACKER
    "Return the index of a unique exact match, falling back to a unique prefix.";
    "Return $nothing for empty inputs, $ambiguous_match for duplicates, or $failed_match.";
    const {subject, choices} = args;
    !subject || !choices && return $nothing;
    const exact = { position for position in [1..length(choices)] if choices[position] == subject };
    length(exact) > 1 && return $ambiguous_match;
    exact && return exact[1];
    const partial = this:find_prefix(subject, choices);
    return partial == 0 ? $failed_match | partial;
  endmethod

  method from_ASCII owner: HACKER
    "Convert a printable ASCII code (32 through 126) to a one-character string.";
    const {code} = args;
    return this.ascii[code - 31];
  endmethod

  method to_ASCII owner: HACKER
    "Return the printable ASCII code for a one-character string; otherwise raise E_INVARG.";
    const {char} = args;
    length(char) == 1 || raise(E_INVARG);
    const position = index(this.ascii, char, true);
    position > 0 || raise(E_INVARG);
    return position + 31;
  endmethod

  method abbreviated_value owner: HACKER
    "Format value with limits on output, list depth, list length, string length, and token length.";
    "All limits are optional in that order. Ellipses can make short results exceed the target";
    "size.";
    const {value, ?max_result = $maxint, ?max_depth = $maxint, ?max_items = $maxint, ?max_string = $maxint, ?max_token = $maxint} = args;
    return this:_abbreviated_value(value, max_result, max_depth, max_items, max_string, max_token);
  endmethod

  method _abbreviated_value owner: HACKER
    "Format one value within the abbreviated_value limits, preserving readable ellipses.";
    const {value, max_result, max_depth, max_items, max_string, max_token} = args;
    if (typeof(value) == TYPE_LIST)
      !value && return "{}";
      max_depth == 0 && return "{...}";
      let result = "{";
      let remaining = max_result - 2;
      let position = 1;
      let last_boundary = 1;
      while (position <= length(value) && position <= max_items)
        const separator = position == 1 ? "" | ", ";
        if (remaining <= length(separator))
          break;
        endif
        const part = this:_abbreviated_value(value[position], remaining, max_depth - 1, max_items, max_string, max_token);
        if (remaining < length(part) + length(separator))
          break;
        endif
        result = result + separator;
        remaining > 4 && (last_boundary = length(result));
        result = result + part;
        remaining = remaining - length(part) - length(separator);
        position = position + 1;
      endwhile
      position > length(value) && return result + "}";
      position == 1 && return "{...}";
      return remaining > 4 ? result + ", ...}" | result[1..last_boundary] + "...}";
    endif
    if (typeof(value) == TYPE_STR)
      const literal = toliteral(value);
      const limit = max(min(max_result, max_string + 2), 6);
      length(literal) <= limit && return literal;
      const boundary = limit - 5;
      let backslashes = 0;
      while (backslashes < boundary && literal[boundary - backslashes] == "\\")
        backslashes = backslashes + 1;
      endwhile
      return literal[1..boundary - backslashes % 2] + "\"+...";
    endif
    const text = typeof(value) == TYPE_ERR ? $code_utils:error_name(value) | tostr(value);
    const limit = max(4, min(max_result, max_token));
    return length(text) > limit ? text[1..limit - 3] + "..." | text;
  endmethod

  method match_suspended owner: HACKER
    "Match text against (objects, property) pairs; property values are strings or lists.";
    "Exact matches beat prefixes; repeated matches on the same object are not ambiguous.";
    "Return $nothing for empty text, $failed_match if absent, or $ambiguous_match.";
    "Budget yields commit between objects; this is not a snapshot across the entire scan.";
    const subject = args[1];
    !subject && return $nothing;
    let exact = $failed_match;
    let partial = $failed_match;
    for pair in [1..length(args) / 2]
      const objects = args[2 * pair];
      const prop = args[2 * pair + 1];
      for object in (typeof(objects) == TYPE_LIST ? objects | {objects})
        if (valid(object))
          let names = `object.(prop) ! E_PERM, E_PROPNF => {}';
          typeof(names) != TYPE_LIST && (names = {names});
          if (subject in names)
            exact != $failed_match && exact != object && return $ambiguous_match;
            exact = object;
          else
            for name in (names)
              if (index(name, subject) == 1)
                partial = partial == $failed_match || partial == object ? object | $ambiguous_match;
              endif
            endfor
          endif
        endif
        $command_utils:suspend_if_needed(0);
      endfor
    endfor
    return exact != $failed_match ? exact | partial;
  endmethod

  method incr_alpha owner: HACKER
    "Increment text in alphabet order, carrying the final character; empty text starts at";
    "alphabet[1].";
    "The alphabet defaults to lowercase ASCII letters.";
    let {text, ?alphabet = this.alphabet} = args;
    let position = length(text);
    while (position > 0 && text[position] == alphabet[$])
      text[position] = alphabet[1];
      position = position - 1;
    endwhile
    position == 0 && return alphabet[1] + text;
    const digit = index(alphabet, text[position]);
    text[position] = alphabet[digit + 1];
    return text;
  endmethod

  method is_float owner: HACKER
    "Return whether text is a complete decimal or exponent-form float, with surrounding spaces.";
    return !!match(args[1], "^ *[-+]?%(%([0-9]+%.[0-9]*%|[0-9]*%.[0-9]+%)%(e[-+]?[0-9]+%)?%|[0-9]+e[-+]?[0-9]+%) *$");
  endmethod

  method inside_quotes owner: HACKER
    "Return whether text ends inside double quotes, respecting backslash escapes.";
    const {text} = args;
    let quoted = false;
    let escaped = false;
    for position in [1..length(text)]
      const char = text[position];
      if (escaped)
        escaped = false;
      elseif (char == "\\")
        escaped = true;
      elseif (char == "\"")
        quoted = !quoted;
      endif
    endfor
    return quoted;
  endmethod

  method strip_all_but_seq owner: HACKER
    "Concatenate nonoverlapping matches of a MOO regular expression.";
    "Empty matches add no text and advance one character to ensure progress.";
    const {text, pattern} = args;
    let start = 1;
    let result = "";
    while (start <= length(text) + 1)
      const found = match(text, pattern, 0, start);
      if (!found)
        break;
      endif
      result = result + text[found[1]..found[2]];
      start = max(found[2] + 1, found[1] + 1);
    endwhile
    return result;
  endmethod
endobject
