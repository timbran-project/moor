object ANSI
  name: "ANSI"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Utility object for generating ANSI escape sequences for terminal colors and formatting.";
  override import_export_hierarchy = {"format"};
  override import_export_id = "ansi";

  verb reset (this none this) owner: HACKER flags: "rxd"
    "Reset all formatting and colors";
    return "\x1B[0m";
  endverb

  verb bold (this none this) owner: HACKER flags: "rxd"
    "Enable bold text";
    return "\x1B[1m";
  endverb

  verb dim (this none this) owner: HACKER flags: "rxd"
    "Enable dim/faint text";
    return "\x1B[2m";
  endverb

  verb italic (this none this) owner: HACKER flags: "rxd"
    "Enable italic text";
    return "\x1B[3m";
  endverb

  verb underline (this none this) owner: HACKER flags: "rxd"
    "Enable underline";
    return "\x1B[4m";
  endverb

  verb blink (this none this) owner: HACKER flags: "rxd"
    "Enable blinking text (slow)";
    return "\x1B[5m";
  endverb

  verb reverse (this none this) owner: HACKER flags: "rxd"
    "Reverse video (swap foreground/background)";
    return "\x1B[7m";
  endverb

  verb hidden (this none this) owner: HACKER flags: "rxd"
    "Hide text (concealed)";
    return "\x1B[8m";
  endverb

  verb strikethrough (this none this) owner: HACKER flags: "rxd"
    "Enable strikethrough";
    return "\x1B[9m";
  endverb

  verb black (this none this) owner: HACKER flags: "rxd"
    "Black foreground color";
    return "\x1B[30m";
  endverb

  verb red (this none this) owner: HACKER flags: "rxd"
    "Red foreground color";
    return "\x1B[31m";
  endverb

  verb green (this none this) owner: HACKER flags: "rxd"
    "Green foreground color";
    return "\x1B[32m";
  endverb

  verb yellow (this none this) owner: HACKER flags: "rxd"
    "Yellow foreground color";
    return "\x1B[33m";
  endverb

  verb blue (this none this) owner: HACKER flags: "rxd"
    "Blue foreground color";
    return "\x1B[34m";
  endverb

  verb magenta (this none this) owner: HACKER flags: "rxd"
    "Magenta foreground color";
    return "\x1B[35m";
  endverb

  verb cyan (this none this) owner: HACKER flags: "rxd"
    "Cyan foreground color";
    return "\x1B[36m";
  endverb

  verb white (this none this) owner: HACKER flags: "rxd"
    "White foreground color";
    return "\x1B[37m";
  endverb

  verb bg_black (this none this) owner: HACKER flags: "rxd"
    "Black background color";
    return "\x1B[40m";
  endverb

  verb bg_red (this none this) owner: HACKER flags: "rxd"
    "Red background color";
    return "\x1B[41m";
  endverb

  verb bg_green (this none this) owner: HACKER flags: "rxd"
    "Green background color";
    return "\x1B[42m";
  endverb

  verb bg_yellow (this none this) owner: HACKER flags: "rxd"
    "Yellow background color";
    return "\x1B[43m";
  endverb

  verb bg_blue (this none this) owner: HACKER flags: "rxd"
    "Blue background color";
    return "\x1B[44m";
  endverb

  verb bg_magenta (this none this) owner: HACKER flags: "rxd"
    "Magenta background color";
    return "\x1B[45m";
  endverb

  verb bg_cyan (this none this) owner: HACKER flags: "rxd"
    "Cyan background color";
    return "\x1B[46m";
  endverb

  verb bg_white (this none this) owner: HACKER flags: "rxd"
    "White background color";
    return "\x1B[47m";
  endverb

  verb bright_black (this none this) owner: HACKER flags: "rxd"
    "Bright black (gray) foreground color";
    return "\x1B[90m";
  endverb

  verb bright_red (this none this) owner: HACKER flags: "rxd"
    "Bright red foreground color";
    return "\x1B[91m";
  endverb

  verb bright_green (this none this) owner: HACKER flags: "rxd"
    "Bright green foreground color";
    return "\x1B[92m";
  endverb

  verb bright_yellow (this none this) owner: HACKER flags: "rxd"
    "Bright yellow foreground color";
    return "\x1B[93m";
  endverb

  verb bright_blue (this none this) owner: HACKER flags: "rxd"
    "Bright blue foreground color";
    return "\x1B[94m";
  endverb

  verb bright_magenta (this none this) owner: HACKER flags: "rxd"
    "Bright magenta foreground color";
    return "\x1B[95m";
  endverb

  verb bright_cyan (this none this) owner: HACKER flags: "rxd"
    "Bright cyan foreground color";
    return "\x1B[96m";
  endverb

  verb bright_white (this none this) owner: HACKER flags: "rxd"
    "Bright white foreground color";
    return "\x1B[97m";
  endverb

  verb bg_bright_black (this none this) owner: HACKER flags: "rxd"
    "Bright black (gray) background color";
    return "\x1B[100m";
  endverb

  verb bg_bright_red (this none this) owner: HACKER flags: "rxd"
    "Bright red background color";
    return "\x1B[101m";
  endverb

  verb bg_bright_green (this none this) owner: HACKER flags: "rxd"
    "Bright green background color";
    return "\x1B[102m";
  endverb

  verb bg_bright_yellow (this none this) owner: HACKER flags: "rxd"
    "Bright yellow background color";
    return "\x1B[103m";
  endverb

  verb bg_bright_blue (this none this) owner: HACKER flags: "rxd"
    "Bright blue background color";
    return "\x1B[104m";
  endverb

  verb bg_bright_magenta (this none this) owner: HACKER flags: "rxd"
    "Bright magenta background color";
    return "\x1B[105m";
  endverb

  verb bg_bright_cyan (this none this) owner: HACKER flags: "rxd"
    "Bright cyan background color";
    return "\x1B[106m";
  endverb

  verb bg_bright_white (this none this) owner: HACKER flags: "rxd"
    "Bright white background color";
    return "\x1B[107m";
  endverb

  verb "color_256 colour_256" (this none this) owner: HACKER flags: "rxd"
    "Foreground color using 256-color palette (0-255)";
    {color_code} = args;
    typeof(color_code) == TYPE_INT || raise(E_TYPE("Color code must be an integer"));
    color_code >= 0 && color_code <= 255 || raise(E_RANGE("Color code must be 0-255"));
    return "\x1B[38;5;" + tostr(color_code) + "m";
  endverb

  verb "bg_color_256 bg_colour_256" (this none this) owner: HACKER flags: "rxd"
    "Background color using 256-color palette (0-255)";
    {color_code} = args;
    typeof(color_code) == TYPE_INT || raise(E_TYPE("Color code must be an integer"));
    color_code >= 0 && color_code <= 255 || raise(E_RANGE("Color code must be 0-255"));
    return "\x1B[48;5;" + tostr(color_code) + "m";
  endverb

  verb rgb (this none this) owner: HACKER flags: "rxd"
    "Foreground color using RGB values (0-255 each)";
    {r, g, b} = args;
    typeof(r) == TYPE_INT || raise(E_TYPE("R value must be an integer"));
    typeof(g) == TYPE_INT || raise(E_TYPE("G value must be an integer"));
    typeof(b) == TYPE_INT || raise(E_TYPE("B value must be an integer"));
    r >= 0 && r <= 255 || raise(E_RANGE("R must be 0-255"));
    g >= 0 && g <= 255 || raise(E_RANGE("G must be 0-255"));
    b >= 0 && b <= 255 || raise(E_RANGE("B must be 0-255"));
    return "\x1B[38;2;" + tostr(r) + ";" + tostr(g) + ";" + tostr(b) + "m";
  endverb

  verb bg_rgb (this none this) owner: HACKER flags: "rxd"
    "Background color using RGB values (0-255 each)";
    {r, g, b} = args;
    typeof(r) == TYPE_INT || raise(E_TYPE("R value must be an integer"));
    typeof(g) == TYPE_INT || raise(E_TYPE("G value must be an integer"));
    typeof(b) == TYPE_INT || raise(E_TYPE("B value must be an integer"));
    r >= 0 && r <= 255 || raise(E_RANGE("R must be 0-255"));
    g >= 0 && g <= 255 || raise(E_RANGE("G must be 0-255"));
    b >= 0 && b <= 255 || raise(E_RANGE("B must be 0-255"));
    return "\x1B[48;2;" + tostr(r) + ";" + tostr(g) + ";" + tostr(b) + "m";
  endverb

  verb "colorize colourize" (this none this) owner: HACKER flags: "rxd"
    "Wrap text in colour codes and reset. Usage: colorize(text, color_code) or colorize(text, 'red)";
    {text, color} = args;
    typeof(text) == TYPE_STR || raise(E_TYPE("Text must be a string"));
    "Handle symbolic color names";
    if (typeof(color) == TYPE_SYM)
      color_str = tostr(color);
      if (respond_to(this, color_str))
        prefix = this:(color_str)();
      else
        raise(E_INVARG("Unknown color name: " + color_str));
      endif
    elseif (typeof(color) == TYPE_INT)
      prefix = this:color_256(color);
    else
      raise(E_TYPE("Color must be a symbol or integer"));
    endif
    return prefix + text + this:reset();
  endverb

  verb wrap (this none this) owner: HACKER flags: "rxd"
    "Wrap text with ANSI codes. Usage: wrap(text, codes...) where codes are strings or symbols";
    {text, @codes} = args;
    typeof(text) == TYPE_STR || raise(E_TYPE("Text must be a string"));
    prefix = "";
    for code in (codes)
      if (typeof(code) == TYPE_STR)
        prefix = prefix + code;
      elseif (typeof(code) == TYPE_SYM)
        code_str = tostr(code);
        if (respond_to(this, code_str))
          prefix = prefix + this:(code_str)();
        else
          raise(E_INVARG("Unknown ANSI code: " + code_str));
        endif
      else
        raise(E_TYPE("Codes must be strings or symbols"));
      endif
    endfor
    return prefix + text + this:reset();
  endverb

  verb strip (this none this) owner: HACKER flags: "rxd"
    "Remove all ANSI escape sequences from text";
    {text} = args;
    typeof(text) == TYPE_STR || raise(E_TYPE("Text must be a string"));
    "Replace all ANSI escape sequences with empty string";
    "Pattern: ESC[ followed by any number of parameters and letter";
    result = text;
    while (index(result, "\x1B["))
      start = index(result, "\x1B[");
      "Find the end of the escape sequence (first letter after [)";
      end = start + 1;
      while (end <= length(result))
        char = result[end..end];
        if (char >= "A" && char <= "Z" || char >= "a" && char <= "z")
          "Found the end";
          break;
        endif
        end = end + 1;
      endwhile
      "Remove the sequence";
      result = result[1..start - 1] + result[end + 1..$];
    endwhile
    return result;
  endverb
endobject