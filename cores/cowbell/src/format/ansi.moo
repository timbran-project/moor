object ANSI [
  import_export_id -> "ansi",
  import_export_hierarchy -> {"format"}
]
  name: "ANSI"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Utility object for generating ANSI escape sequences for terminal colors and formatting.";

  method reset owner: HACKER
    "Reset all formatting and colors";
    return "\x1B[0m";
  endmethod

  method bold owner: HACKER
    "Enable bold text";
    return "\x1B[1m";
  endmethod

  method dim owner: HACKER
    "Enable dim/faint text";
    return "\x1B[2m";
  endmethod

  method italic owner: HACKER
    "Enable italic text";
    return "\x1B[3m";
  endmethod

  method underline owner: HACKER
    "Enable underline";
    return "\x1B[4m";
  endmethod

  method blink owner: HACKER
    "Enable blinking text (slow)";
    return "\x1B[5m";
  endmethod

  method reverse owner: HACKER
    "Reverse video (swap foreground/background)";
    return "\x1B[7m";
  endmethod

  method hidden owner: HACKER
    "Hide text (concealed)";
    return "\x1B[8m";
  endmethod

  method strikethrough owner: HACKER
    "Enable strikethrough";
    return "\x1B[9m";
  endmethod

  method black owner: HACKER
    "Black foreground color";
    return "\x1B[30m";
  endmethod

  method red owner: HACKER
    "Red foreground color";
    return "\x1B[31m";
  endmethod

  method green owner: HACKER
    "Green foreground color";
    return "\x1B[32m";
  endmethod

  method yellow owner: HACKER
    "Yellow foreground color";
    return "\x1B[33m";
  endmethod

  method blue owner: HACKER
    "Blue foreground color";
    return "\x1B[34m";
  endmethod

  method magenta owner: HACKER
    "Magenta foreground color";
    return "\x1B[35m";
  endmethod

  method cyan owner: HACKER
    "Cyan foreground color";
    return "\x1B[36m";
  endmethod

  method white owner: HACKER
    "White foreground color";
    return "\x1B[37m";
  endmethod

  method bg_black owner: HACKER
    "Black background color";
    return "\x1B[40m";
  endmethod

  method bg_red owner: HACKER
    "Red background color";
    return "\x1B[41m";
  endmethod

  method bg_green owner: HACKER
    "Green background color";
    return "\x1B[42m";
  endmethod

  method bg_yellow owner: HACKER
    "Yellow background color";
    return "\x1B[43m";
  endmethod

  method bg_blue owner: HACKER
    "Blue background color";
    return "\x1B[44m";
  endmethod

  method bg_magenta owner: HACKER
    "Magenta background color";
    return "\x1B[45m";
  endmethod

  method bg_cyan owner: HACKER
    "Cyan background color";
    return "\x1B[46m";
  endmethod

  method bg_white owner: HACKER
    "White background color";
    return "\x1B[47m";
  endmethod

  method bright_black owner: HACKER
    "Bright black (gray) foreground color";
    return "\x1B[90m";
  endmethod

  method bright_red owner: HACKER
    "Bright red foreground color";
    return "\x1B[91m";
  endmethod

  method bright_green owner: HACKER
    "Bright green foreground color";
    return "\x1B[92m";
  endmethod

  method bright_yellow owner: HACKER
    "Bright yellow foreground color";
    return "\x1B[93m";
  endmethod

  method bright_blue owner: HACKER
    "Bright blue foreground color";
    return "\x1B[94m";
  endmethod

  method bright_magenta owner: HACKER
    "Bright magenta foreground color";
    return "\x1B[95m";
  endmethod

  method bright_cyan owner: HACKER
    "Bright cyan foreground color";
    return "\x1B[96m";
  endmethod

  method bright_white owner: HACKER
    "Bright white foreground color";
    return "\x1B[97m";
  endmethod

  method bg_bright_black owner: HACKER
    "Bright black (gray) background color";
    return "\x1B[100m";
  endmethod

  method bg_bright_red owner: HACKER
    "Bright red background color";
    return "\x1B[101m";
  endmethod

  method bg_bright_green owner: HACKER
    "Bright green background color";
    return "\x1B[102m";
  endmethod

  method bg_bright_yellow owner: HACKER
    "Bright yellow background color";
    return "\x1B[103m";
  endmethod

  method bg_bright_blue owner: HACKER
    "Bright blue background color";
    return "\x1B[104m";
  endmethod

  method bg_bright_magenta owner: HACKER
    "Bright magenta background color";
    return "\x1B[105m";
  endmethod

  method bg_bright_cyan owner: HACKER
    "Bright cyan background color";
    return "\x1B[106m";
  endmethod

  method bg_bright_white owner: HACKER
    "Bright white background color";
    return "\x1B[107m";
  endmethod

  method "color_256 colour_256" owner: HACKER
    "Foreground color using 256-color palette (0-255)";
    {color_code} = args;
    typeof(color_code) == TYPE_INT || raise(E_TYPE("Color code must be an integer"));
    color_code >= 0 && color_code <= 255 || raise(E_RANGE("Color code must be 0-255"));
    return "\x1B[38;5;" + tostr(color_code) + "m";
  endmethod

  method "bg_color_256 bg_colour_256" owner: HACKER
    "Background color using 256-color palette (0-255)";
    {color_code} = args;
    typeof(color_code) == TYPE_INT || raise(E_TYPE("Color code must be an integer"));
    color_code >= 0 && color_code <= 255 || raise(E_RANGE("Color code must be 0-255"));
    return "\x1B[48;5;" + tostr(color_code) + "m";
  endmethod

  method rgb owner: HACKER
    "Foreground color using RGB values (0-255 each)";
    {r, g, b} = args;
    typeof(r) == TYPE_INT || raise(E_TYPE("R value must be an integer"));
    typeof(g) == TYPE_INT || raise(E_TYPE("G value must be an integer"));
    typeof(b) == TYPE_INT || raise(E_TYPE("B value must be an integer"));
    r >= 0 && r <= 255 || raise(E_RANGE("R must be 0-255"));
    g >= 0 && g <= 255 || raise(E_RANGE("G must be 0-255"));
    b >= 0 && b <= 255 || raise(E_RANGE("B must be 0-255"));
    return "\x1B[38;2;" + tostr(r) + ";" + tostr(g) + ";" + tostr(b) + "m";
  endmethod

  method bg_rgb owner: HACKER
    "Background color using RGB values (0-255 each)";
    {r, g, b} = args;
    typeof(r) == TYPE_INT || raise(E_TYPE("R value must be an integer"));
    typeof(g) == TYPE_INT || raise(E_TYPE("G value must be an integer"));
    typeof(b) == TYPE_INT || raise(E_TYPE("B value must be an integer"));
    r >= 0 && r <= 255 || raise(E_RANGE("R must be 0-255"));
    g >= 0 && g <= 255 || raise(E_RANGE("G must be 0-255"));
    b >= 0 && b <= 255 || raise(E_RANGE("B must be 0-255"));
    return "\x1B[48;2;" + tostr(r) + ";" + tostr(g) + ";" + tostr(b) + "m";
  endmethod

  method "colorize colourize" owner: HACKER
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
  endmethod

  method wrap owner: HACKER
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
  endmethod

  method strip owner: HACKER
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
  endmethod

  method test_basic_sequences owner: HACKER
    this:red() + "red text" + this:reset() == "\x1B[31mred text\x1B[0m" || raise(E_ASSERT, "red color sequence mismatch");
    this:blue() + "blue text" + this:reset() == "\x1B[34mblue text\x1B[0m" || raise(E_ASSERT, "blue color sequence mismatch");
    this:bold() + "bold" + this:reset() == "\x1B[1mbold\x1B[0m" || raise(E_ASSERT, "bold sequence mismatch");
    this:italic() + "italic" + this:reset() == "\x1B[3mitalic\x1B[0m" || raise(E_ASSERT, "italic sequence mismatch");
    return true;
  endmethod

  method test_extended_color_sequences owner: HACKER
    this:color_256(196) == "\x1B[38;5;196m" || raise(E_ASSERT, "256-color foreground sequence mismatch");
    this:bg_color_256(27) == "\x1B[48;5;27m" || raise(E_ASSERT, "256-color background sequence mismatch");
    this:rgb(255, 0, 128) == "\x1B[38;2;255;0;128m" || raise(E_ASSERT, "RGB foreground sequence mismatch");
    this:bg_rgb(0, 128, 255) == "\x1B[48;2;0;128;255m" || raise(E_ASSERT, "RGB background sequence mismatch");
    return true;
  endmethod

  method test_wrapping_and_stripping owner: HACKER
    this:colorize("hello", 'red) == "\x1B[31mhello\x1B[0m" || raise(E_ASSERT, "symbol colorize mismatch");
    this:colorize("world", 196) == "\x1B[38;5;196mworld\x1B[0m" || raise(E_ASSERT, "integer colorize mismatch");
    this:wrap("text", 'bold, 'red) == "\x1B[1m\x1B[31mtext\x1B[0m" || raise(E_ASSERT, "wrap sequence mismatch");
    this:strip("\x1B[31mred\x1B[0m text") == "red text" || raise(E_ASSERT, "simple strip mismatch");
    this:strip("\x1B[1m\x1B[31mbold red\x1B[0m") == "bold red" || raise(E_ASSERT, "complex strip mismatch");
    return true;
  endmethod

  method test_british_aliases owner: HACKER
    this:colour_256(196) == "\x1B[38;5;196m" || raise(E_ASSERT, "British 256-colour foreground sequence mismatch");
    this:bg_colour_256(27) == "\x1B[48;5;27m" || raise(E_ASSERT, "British 256-colour background sequence mismatch");
    this:colourize("hello", 'red) == "\x1B[31mhello\x1B[0m" || raise(E_ASSERT, "British colourize mismatch");
    return true;
  endmethod
endobject
