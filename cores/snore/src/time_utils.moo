object TIME_UTILS [
  import_export_id -> "time_utils"
]
  name: "time utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property corr (owner: HACKER, flags: "rc") = -122;
  property ct (owner: HACKER, flags: "rc") = 7934;
  property ctcd (owner: HACKER, flags: "rc") = 7276;
  property dayabbrs (owner: HACKER, flags: "rc") = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  property days (owner: HACKER, flags: "rc") = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
  property monthabbrs (owner: HACKER, flags: "rc") = {
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  };
  property monthlens (owner: HACKER, flags: "rc") = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  property months (owner: HACKER, flags: "rc") = {
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  };
  property stsd (owner: HACKER, flags: "rc") = 2427;
  property time_units (owner: HACKER, flags: "rc") = {
    {31536000, "year", "years", "yr", "yrs"},
    {2628000, "month", "months", "mo", "mos"},
    {604800, "week", "weeks", "wk", "wks"},
    {86400, "day", "days", "dy", "dys"},
    {3600, "hour", "hours", "hr", "hrs"},
    {60, "minute", "minutes", "min", "mins"},
    {1, "second", "seconds", "sec", "secs"}
  };
  property timezones (owner: HACKER, flags: "rc") = {
    {"AuEST", -10},
    {"AuCST", -9},
    {"AuWST", -8},
    {"WET", -1},
    {"GMT", 0},
    {"UTC", 0},
    {"UT", 0},
    {"AST", 4},
    {"EDT", 4},
    {"EST", 5},
    {"CDT", 5},
    {"CST", 6},
    {"MDT", 6},
    {"MST", 7},
    {"PDT", 7},
    {"PST", 8},
    {"HST", 10}
  };
  property zones (owner: HACKER, flags: "rc") = {
    {{"est", "edt", "Massachusetts", "MA"}, 10800},
    {{"cst", "cdt"}, 7200},
    {{"mst", "mdt"}, 3600},
    {{"pst", "pdt", "California", "CA", "Lambda"}, 0},
    {{"gmt"}, 28800}
  };

  override aliases (owner: HACKER, flags: "rc") = {"time utilities", "time"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the time utilities utility package.  See `help $time_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "    Converting from seconds-since-1970    ",
    "dhms          (time)                 => string ...DD:HH:MM:SS",
    "english_time  (time[, reference time)=> string of y, m, d, h, m, s",
    "",
    "    Converting to seconds",
    "to_seconds    (\"hh:mm:ss\")           => seconds since 00:00:00",
    "from_ctime    (ctime)                => corresponding time-since-1970",
    "from_day      (day_of_week, which)   => time-since-1970 for the given day*",
    "from_month    (month, which[, day, reference]) => timestamp for the given month*",
    "    (* midnight in fixed PST, UTC-8; from_day accepts an optional reference)",
    "from_ctime accepts known zone names (including UTC) and numeric offsets such as +0530.",
    "Calendar parsing uses Gregorian years 1..9999 and rejects invalid dates.",
    "parse_english_time_interval(\"n1 u1 n2 u2...\")",
    "                                     => seconds in interval",
    "seconds_until_time(\"hh:mm:ss\")       => number of seconds from now until then",
    "seconds_until_date(\"month\",day,\"hh:mm:ss\",flag ",
    "                                     => number of seconds from now until then",
    "                                        (see verb help for details)",
    "",
    "    Converting to some standard English formats",
    "day           ([c]time)              => what day it is",
    "month         ([c]time)              => what month it is",
    "ampm          ([c]time[, precision]) => what time it is, with am or pm",
    "mmddyy        ([c]time)              => date in format MM/DD/YY",
    "ddmmyy        ([c]time)              => date in format DD/MM/YY",
    "",
    "    Substitution",
    "time_sub      (string, time)         => substitute time information",
    "",
    "    Miscellaneous",
    "sun           ([time])               => angle between sun and zenith",
    "dst_midnight  (time) => nearest midnight in the server timezone"
  };
  override object_size (owner: HACKER, flags: "r") = {22076, 1084848672};

  verb day (none none none) owner: HACKER flags: "rxd"
    "Return the full day name from a timestamp or ctime string.";
    const {value} = args;
    !(typeof(value) in {TYPE_INT, TYPE_STR}) && return E_TYPE;
    const fields = $string_utils:words(typeof(value) == TYPE_INT ? ctime(value) | value);
    length(fields) < 1 && return E_INVARG;
    const position = fields[1] in this.dayabbrs;
    return position ? this.days[position] | E_INVARG;
  endverb

  verb month (none none none) owner: HACKER flags: "rxd"
    "Return the full month name from a timestamp or ctime string.";
    const {value} = args;
    !(typeof(value) in {TYPE_INT, TYPE_STR}) && return E_TYPE;
    const fields = $string_utils:words(typeof(value) == TYPE_INT ? ctime(value) | value);
    length(fields) < 2 && return E_INVARG;
    const position = fields[2] in this.monthabbrs;
    return position ? this.months[position] | E_INVARG;
  endverb

  verb ampm (none none none) owner: HACKER flags: "rxd"
    "Format a timestamp or ctime string in 12-hour time; precision is 1, 2, or 3.";
    const {value, ?precision = 2} = args;
    !(typeof(value) in {TYPE_INT, TYPE_STR}) && return E_TYPE;
    !(precision in {1, 2, 3}) && return E_INVARG;
    const fields = $string_utils:words(typeof(value) == TYPE_INT ? ctime(value) | value);
    length(fields) < 4 && return E_INVARG;
    const clock = fields[4];
    typeof(this:to_seconds(clock)) == TYPE_ERR && return E_INVARG;
    const hour = toint(clock[1..2]);
    return tostr((hour + 11) % 12 + 1, clock[3..precision * 3 - 1], hour < 12 ? " a.m." | " p.m.");
  endverb

  method to_seconds owner: HACKER
    "Convert HH:MM:SS to seconds since midnight; malformed clocks return E_INVARG.";
    const {clock} = args;
    typeof(clock) != TYPE_STR && return E_TYPE;
    length(clock) != 8 || !match(clock, "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$") && return E_INVARG;
    const hour = toint(clock[1..2]);
    const minute = toint(clock[4..5]);
    const second = toint(clock[7..8]);
    hour > 23 || minute > 59 || second > 59 && return E_INVARG;
    return hour * 3600 + minute * 60 + second;
  endmethod

  method sun owner: HACKER
    "Return the retained solar-angle approximation, scaled by 10000.";
    const {?timestamp = time()} = args;
    const scale = 10000;
    const rounding = scale * scale + scale / 2;
    const daily = (timestamp + 120) % 86400 / 240;
    const annual = 5 * ((timestamp - 14957676) % 31556952) / 438291;
    const phase = annual + daily + this.corr;
    const cosine = $trig_utils:cos(annual);
    const sine_product = ($trig_utils:sin(phase) * $trig_utils:sin(annual) + rounding) / scale - scale;
    const cosine_product = ($trig_utils:cos(phase) * cosine + rounding) / scale - scale;
    return (this.stsd * cosine - this.ctcd * cosine_product - this.ct * sine_product + rounding) / scale - scale;
  endmethod

  method from_ctime owner: HACKER
    "Parse ctime text, including its fixed zone abbreviation or numeric +/-HHMM offset.";
    "Missing zones mean PST. Invalid dates or unknown zones return E_DIV.";
    const {text} = args;
    typeof(text) != TYPE_STR && return E_TYPE;
    let fields = $string_utils:words(text);
    length(fields) == 5 && (fields = {@fields, "PST"});
    length(fields) != 6 && return E_DIV;
    const month = fields[2] in this.monthabbrs;
    const clock = this:to_seconds(fields[4]);
    !month || typeof(clock) == TYPE_ERR && return E_DIV;
    !$string_utils:is_numeric(fields[3]) || !$string_utils:is_numeric(fields[5]) && return E_DIV;
    const zone = fields[6];
    let offset = 0;
    const named = $list_utils:assoc(zone, this.timezones);
    if (named)
      offset = named[2] * 60;
    elseif (length(zone) == 5 && match(zone, "^[+-][0-9][0-9][0-9][0-9]$"))
      const hours = toint(zone[2..3]);
      const minutes = toint(zone[4..5]);
      hours > 23 || minutes > 59 && return E_DIV;
      offset = (hours * 60 + minutes) * (zone[1] == "+" ? -1 | 1);
    else
      return E_DIV;
    endif
    const midnight = this:_date_seconds(toint(fields[5]), month, toint(fields[3]), offset);
    return typeof(midnight) == TYPE_ERR ? midnight | midnight + clock;
  endmethod

  method "dhms dayshoursminutesseconds" owner: HACKER
    "Format an integer duration as seconds, M:SS, H:MM:SS, or D:HH:MM:SS.";
    "Negative durations retain a leading minus, including the minimum integer.";
    const {seconds} = args;
    let remaining = seconds > 0 ? -seconds | seconds;
    let pieces = {};
    for radix in ({60, 60, 24})
      const part = -(remaining % radix);
      remaining = remaining / radix;
      if (!remaining)
        return tostr(seconds < 0 ? "-" | "", part, @pieces);
      endif
      pieces = {tostr(":", part < 10 ? "0" | "", part), @pieces};
    endfor
    return tostr(seconds < 0 ? "-" | "", -remaining, @pieces);
  endmethod

  method english_time owner: HACKER
    "Format a duration using calendar months starting with the reference month.";
    "The reference day is ignored. Whole 400-year cycles bound the work; this does not suspend.";
    const {duration, ?reference = time()} = args;
    duration < 1 && return "0 seconds";
    const fields = $string_utils:words(typeof(reference) == TYPE_INT ? ctime(reference) | reference);
    length(fields) < 5 && return E_INVARG;
    let month = fields[2] in this.monthabbrs;
    let year = toint(fields[5]);
    !month || year < 1 && return E_INVARG;
    let days = duration / 86400;
    let months = days / 146097 * 4800;
    days = days % 146097;
    while (true)
      const leap_year = year + (month > 2 ? 1 | 0);
      const year_days = 337 + this:_month_days(leap_year, 2);
      if (days < year_days)
        break;
      endif
      days = days - year_days;
      year = year + 1;
      months = months + 12;
    endwhile
    while (true)
      const month_days = this:_month_days(year, month);
      if (days < month_days)
        break;
      endif
      days = days - month_days;
      months = months + 1;
      month = month % 12 + 1;
      month == 1 && (year = year + 1);
    endwhile
    const values = {months / 12, months % 12, days, duration / 3600 % 24, duration / 60 % 60, duration % 60};
    const labels = {"year", "month", "day", "hour", "minute", "second"};
    let phrases = {};
    for position in [1..6]
      const value = values[position];
      value && (phrases = {@phrases, tostr(value, " ", labels[position], value == 1 ? "" | "s")});
    endfor
    return $string_utils:english_list(phrases);
  endmethod

  method from_day owner: HACKER
    "Return fixed PST (UTC-8) midnight for a weekday name or Sunday=1 through Saturday=7.";
    "Direction 0 chooses nearest; +1 is next; -1 is most recent, including exact midnight.";
    "Larger directions count weeks. An optional reference timestamp defaults to now.";
    let {day, ?direction = 0, ?reference = time()} = args;
    if (typeof(day) == TYPE_STR)
      day = $string_utils:is_numeric(day) ? toint(day) | $string_utils:find_prefix(day, this.days);
    endif
    typeof(day) != TYPE_INT || day < 1 || day > 7 && return E_DIV;
    const anchor = {288000, 374400, 460800, 547200, 28800, 115200, 201600}[day];
    const elapsed = reference - anchor;
    const week = direction ? $math_utils:div(elapsed, 604800) + (direction > 0 ? direction | direction + 1) | $math_utils:div(elapsed + 302400, 604800);
    return week * 604800 + anchor;
  endmethod

  method from_month owner: HACKER
    "Return fixed PST midnight for a month name or number, direction, and optional day (default 1).";
    "Direction 0 chooses nearest; +1 is next; -1 is most recent, including exact midnight.";
    "Larger directions count years. Optional fourth argument is the reference timestamp.";
    "Invalid dates, including February 29 in a selected non-leap year, return E_DIV.";
    let {month, ?direction = 0, ?day = 1, ?reference = time()} = args;
    if (typeof(month) == TYPE_STR)
      month = $string_utils:is_numeric(month) ? toint(month) | $string_utils:find_prefix(month, this.months);
    endif
    typeof(month) != TYPE_INT || month < 1 || month > 12 && return E_DIV;
    const calendar = this:_calendar(reference - 28800);
    typeof(calendar) == TYPE_ERR && return calendar;
    let year = calendar[1];
    const candidate = this:_date_seconds(year, month, day, 480);
    typeof(candidate) == TYPE_ERR && return candidate;
    if (direction)
      year = year + (candidate > reference ? -1 | 0) + (direction > 0 ? direction | direction + 1);
      return this:_date_seconds(year, month, day, 480);
    endif
    const other = this:_date_seconds(year + (candidate > reference ? -1 | 1), month, day, 480);
    typeof(other) == TYPE_ERR && return candidate;
    return abs(candidate - reference) < abs(other - reference) ? candidate | other;
  endmethod

  method dst_midnight owner: HACKER
    "Adjust a timestamp to the nearest server-local midnight, accounting for offset changes.";
    "The server timezone determines daylight saving; this does not select a timezone.";
    let {timestamp} = args;
    for attempt in [1..3]
      const clock = this:to_seconds(ctime(timestamp)[12..19]);
      !clock && return timestamp;
      timestamp = timestamp - clock + (clock >= 43200 ? 86400 | 0);
    endfor
    return this:to_seconds(ctime(timestamp)[12..19]) == 0 ? timestamp | E_INVARG;
  endmethod

  method time_sub owner: HACKER
    "Substitute ctime fields: H/M/S padded clock, h/m/s unpadded; O/o twelve-hour hour.";
    "D/d weekday, N/n month, Y/y year, Z zone, P/p AM/PM; uppercase uses the long form.";
    "T/t date with/without spaces; 1/2 numeric month with/without zero; 3 zero-filled date.";
    "$$ inserts a dollar; unknown codes and a terminal dollar disappear.";
    let {text, ?timestamp = time()} = args;
    if (typeof(text) != TYPE_STR || typeof(timestamp) != TYPE_INT)
      player:tell("Bad arguments to time_subst.");
      return 0;
    endif
    const stamp = ctime(timestamp);
    const fields = $string_utils:words(stamp);
    const month = fields[2] in this.monthabbrs;
    const hour = toint(stamp[12..13]);
    const twelve = (hour + 11) % 12 + 1;
    const codes = "HhMmSsDdNnTtOoPpYyZ123$";
    const values = {stamp[12..13], tostr(hour), stamp[15..16], tostr(toint(stamp[15..16])), stamp[18..19], tostr(toint(stamp[18..19])), this:day(stamp), fields[1], this.months[month], fields[2], stamp[9..10], fields[3], $string_utils:right(tostr(twelve), 2, "0"), tostr(twelve), hour < 12 ? "AM" | "PM", hour < 12 ? "am" | "pm", fields[5], fields[5][$ - 1..$], fields[6], $string_utils:right(tostr(month), 2, "0"), tostr(month), $string_utils:right(fields[3], 2, "0"), "$"};
    let result = "";
    while (true)
      const dollar = index(text, "$");
      !dollar && return result + text;
      result = result + text[1..dollar - 1];
      dollar == length(text) && return result;
      const position = index(codes, text[dollar + 1], true);
      position && (result = result + values[position]);
      text = text[dollar + 2..$];
    endwhile
  endmethod

  method "mmddyy ddmmyy" owner: HACKER
    "Format a timestamp or ctime string as month/day/year or day/month/year, with an optional separator.";
    const {value, ?separator = "/"} = args;
    !(typeof(value) in {TYPE_INT, TYPE_STR}) && return E_TYPE;
    const fields = $string_utils:words(typeof(value) == TYPE_INT ? ctime(value) | value);
    length(fields) < 5 && return E_INVARG;
    const month = fields[2] in this.monthabbrs;
    !month && return E_INVARG;
    const month_text = $string_utils:right(tostr(month), 2, "0");
    const day_text = $string_utils:right(fields[3], 2, "0");
    const year_text = fields[5][$ - 1..$];
    return index(verb, "mm") == 1 ? tostr(month_text, separator, day_text, separator, year_text) | tostr(day_text, separator, month_text, separator, year_text);
  endmethod

  method parse_english_time_interval owner: HACKER
    "Parse integer amounts and units, as one string or separate string arguments.";
    "Allow a/an, no, commas, and 'and'. Month and year lengths come from time_units.";
    "Return E_ARGS for an incomplete pair, E_INVARG for unknown words, E_RANGE for overflow.";
    let words = length(args) == 1 ? $string_utils:words(args[1]) | args;
    words = { item for item in (words) if item != "and" };
    length(words) % 2 && return E_ARGS;
    let result = 0;
    for position in [1..length(words) / 2]
      const amount_text = words[position * 2 - 1];
      let amount = 0;
      if (amount_text in {"a", "an"})
        amount = 1;
      elseif (amount_text != "no")
        $string_utils:is_numeric(amount_text) || return E_INVARG;
        amount = `fromliteral(amount_text) ! E_INVARG => E_RANGE';
        typeof(amount) != TYPE_INT && return E_RANGE;
      endif
      let unit = words[position * 2];
      unit && unit[$] == "," && (unit = unit[1..$ - 1]);
      let found = false;
      for entry in (this.time_units)
        if (unit in entry[2..$])
          amount > (9223372036854775807 - result) / entry[1] && return E_RANGE;
          result = result + amount * entry[1];
          found = true;
          break;
        endif
      endfor
      found || return E_INVARG;
    endfor
    return result;
  endmethod

  method seconds_until_date owner: HACKER
    "Return seconds to a fixed PST calendar date and HH:MM:SS clock.";
    "Direction selects the year as in from_month; optional fifth argument is the reference.";
    const {month, day, clock, direction, ?reference = time()} = args;
    const midnight = this:from_month(month, direction, day, reference);
    typeof(midnight) == TYPE_ERR && return midnight;
    const seconds = this:to_seconds(clock);
    return typeof(seconds) == TYPE_ERR ? seconds | midnight + seconds - reference;
  endmethod

  method seconds_until_time owner: HACKER
    "Return a signed clock difference within the server-local day; do not roll to tomorrow.";
    const {clock, ?reference = time()} = args;
    const requested = this:to_seconds(clock);
    typeof(requested) == TYPE_ERR && return requested;
    return requested - this:to_seconds(ctime(reference)[12..19]);
  endmethod

  method rfc822_ctime owner: #2
    "Format ctime as weekday, day month year clock zone, retaining the server's zone abbreviation.";
    const fields = $string_utils:words(ctime(@args));
    return tostr(fields[1], ", ", fields[3], " ", fields[2], " ", fields[5], " ", fields[4], " ", fields[6]);
  endmethod

  method "mmddyyyy ddmmyyyy" owner: HACKER
    "Format a timestamp or ctime string as month/day/year or day/month/year, with an optional separator.";
    const {value, ?separator = "/"} = args;
    !(typeof(value) in {TYPE_INT, TYPE_STR}) && return E_TYPE;
    const fields = $string_utils:words(typeof(value) == TYPE_INT ? ctime(value) | value);
    length(fields) < 5 && return E_INVARG;
    const month = fields[2] in this.monthabbrs;
    !month && return E_INVARG;
    const month_text = $string_utils:right(tostr(month), 2, "0");
    const day_text = $string_utils:right(fields[3], 2, "0");
    const year_text = fields[5];
    return index(verb, "mm") == 1 ? tostr(month_text, separator, day_text, separator, year_text) | tostr(day_text, separator, month_text, separator, year_text);
  endmethod

  method _month_days owner: HACKER
    "Internal Gregorian month length; year may extend beyond the timestamp parser's range.";
    const {year, month} = args;
    const leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return this.monthlens[month] + (month == 2 && leap ? 1 | 0);
  endmethod

  method _days_before_year owner: HACKER
    "Internal day number of January 1, relative to 1970, for positive Gregorian years.";
    const {year} = args;
    const previous = year - 1;
    return 365 * (year - 1970) + previous / 4 - previous / 100 + previous / 400 - 477;
  endmethod

  method _date_seconds owner: HACKER
    "Internal Gregorian date to timestamp, years 1..9999; offset is minutes west of UTC.";
    "Return E_DIV for invalid dates instead of normalizing them into another month.";
    const {year, month, day, ?offset = 0} = args;
    year < 1 || year > 9999 || month < 1 || month > 12 && return E_DIV;
    day < 1 || day > this:_month_days(year, month) && return E_DIV;
    let days = this:_days_before_year(year) + day - 1;
    for prior_month in [1..month - 1]
      days = days + this:_month_days(year, prior_month);
    endfor
    return days * 86400 + offset * 60;
  endmethod

  method _calendar owner: HACKER
    "Internal UTC timestamp to {year, month, day}, within Gregorian years 1..9999.";
    const {timestamp} = args;
    let days = $math_utils:div(timestamp, 86400);
    days < this:_days_before_year(1) || days >= this:_days_before_year(10000) && return E_DIV;
    let low = 1;
    let high = 10000;
    while (high - low > 1)
      const middle = (low + high) / 2;
      if (this:_days_before_year(middle) <= days)
        low = middle;
      else
        high = middle;
      endif
    endwhile
    days = days - this:_days_before_year(low);
    let month = 1;
    while (days >= this:_month_days(low, month))
      days = days - this:_month_days(low, month);
      month = month + 1;
    endwhile
    return {low, month, days + 1};
  endmethod
endobject
