object MATH_UTILS [
  import_export_id -> "math_utils"
]
  name: "Math Utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property base_alphabet (owner: HACKER, flags: "rc") = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
  property e (owner: HACKER, flags: "rc") = 2.71828182845905;
  property e_string (owner: HACKER, flags: "rc") = "2.718281828459045235360287471352662497757247093699959574966967627724076630353547594571382178525166427427466391932003059921817413596629043572900334295260595630738132328627943490763233829880753195251019";
  property phi (owner: HACKER, flags: "rc") = 1.618033988749895;
  property pi (owner: HACKER, flags: "rc") = 3.141592653589793;

  override aliases (owner: HACKER, flags: "rc") = {"Math Utilities", "Math_Utils", "trigonometric utilites", "trig_utils"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the Math Utilities utility package.  See `help $math_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "Trigonometric/Exponential functions:",
    "  sin(a),cos(a),tan(a) -- returns 10000*(the value of the corresponding",
    "       trigonometric function) angle a is in degrees.",
    "  arctan(x) -- scaled integer input returns {degrees, minutes}.",
    "       Float trig inputs and results use radians.",
    "  exp(x[,n]) -- calculates e^x with an nth order taylor polynomial",
    "  aexp(x) -- calculates 10000 e^(x/10000)",
    "",
    "Statistical functions:",
    "  combinations(n,r) -- returns the number of combinations given n objects",
    "       taken r at a time.",
    "  permutations(n,r) -- returns the number of permutations possible given",
    "       n objects taken r at a time.",
    "",
    "Number decomposition:",
    "  div(n,d) -- correct version of / (handles negative numbers correctly)",
    "  mod(n,d) -- correct version of % (handles negative numbers correctly)",
    "  divmod(n,d) -- {div(n,d),mod(n,d)}",
    "  parts(n,q[,i]) -- returns a list of two elements {integer,decimal fraction}",
    "",
    "Other math functions:",
    "  sqrt(x)      -- returns the largest integer n <= the square root of x",
    "  pow(x,n)     -- returns x^n",
    "  factorial(x) -- returns x!",
    "  norm(a,b,c,d,...) -- returns sqrt(a^2+b^2+c^2+...)",
    "  sum(a,b,c,d,...) -- returns the sum of all arguments.",
    "",
    "Series:",
    "  fibonacci(n) -- returns the 1st n fibonacci numbers in a list",
    "  geometric(x,n) -- returns the value of the nth order geometric series at x",
    "",
    "Integer Properties:",
    "  gcd(a,b) -- find the greatest common divisor of the two numbers",
    "  lcm(a,b) -- find the least common multiple of the two numbers",
    "  are_relatively_prime(a,b) -- return true if a and b are relatively prime",
    "  is_prime(n) -- returns a boolean primality result",
    "  ",
    "Miscellaneous:",
    "  random(n) -- returns a random number from 0..n if n > 0 or n..0 if n < 0",
    "  random_range(n[,mean]) -- returns a random number from mean - n..mean + n",
    "      with mean defaulting to 0",
    "  simpson({a,b},{f(a),f((a+b)/2),f(b)}) -- returns the numerical",
    "      approximation of an integral using simpson's rule",
    "  base_conversion(num|string, oldbase, newbase [,sens]) -- converts the number",
    "      given as first arg from oldbase to the newbase.",
    "",
    "Bitwise Arithmetic:",
    "  AND(x,y) -- returns x AND y",
    "  OR(x,y) -- returns x OR y",
    "  XOR(x,y) -- returns x XOR y (XOR is the exclusive-or function)",
    "  NOT(x) -- returns the complement of x",
    "      These helpers use the low 32 bits. Native operators use the full integer width.",
    "",
    "Bitwise Conversions:",
    "  BlFromInt(d) -- converts a decimal number d to a list of 1's and 0's, 32-bit",
    "  IntFromBl(b) -- converts a list of 1's and 0's (any precision) to decimal"
  };
  override object_size (owner: HACKER, flags: "r") = {36400, 1084848672};

  method xsin owner: HACKER
    "Return sine of integer degrees, scaled by 10000.";
    const {degrees} = args;
    typeof(degrees) != TYPE_INT && return E_TYPE;
    return this:sin(degrees);
  endmethod

  method xcos owner: HACKER
    "Return cosine of integer degrees, scaled by 10000.";
    const {degrees} = args;
    typeof(degrees) != TYPE_INT && return E_TYPE;
    return this:cos(degrees);
  endmethod

  method factorial owner: HACKER
    "Return n! for a nonnegative integer; raise E_RANGE when the result cannot fit.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    number < 0 && return E_INVARG;
    let result = 1;
    for factor in [2..number]
      result <= 9223372036854775807 / factor || raise(E_RANGE, "Factorial exceeds integer range.");
      result = result * factor;
    endfor
    return result;
  endmethod

  method pow owner: HACKER
    "Raise a number to a nonnegative power; integer bases require integer exponents.";
    const {base, exponent} = args;
    !(typeof(base) in {TYPE_INT, TYPE_FLOAT}) || !(typeof(exponent) in {TYPE_INT, TYPE_FLOAT}) && return E_TYPE;
    typeof(base) == TYPE_INT && typeof(exponent) != TYPE_INT && return E_TYPE;
    exponent < (typeof(exponent) == TYPE_INT ? 0 | 0.0) && return E_INVARG;
    return base ^ exponent;
  endmethod

  method fibonacci owner: HACKER
    "Return Fibonacci terms zero through n, including {0} for n = 0.";
    "Return E_INVARG for negative n; raise E_RANGE if a term cannot fit an integer.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    number < 0 && return E_INVARG;
    number == 0 && return {0};
    let result = {0, 1};
    for position in [2..number]
      result[$ - 1] <= 9223372036854775807 - result[$] || raise(E_RANGE, "Fibonacci term exceeds integer range.");
      result = {@result, result[$ - 1] + result[$]};
    endfor
    return result;
  endmethod

  method geometric owner: HACKER
    "Return 1 + x + ... + x^order; order defaults to five and may be zero.";
    const {number, ?order = 5} = args;
    !(typeof(number) in {TYPE_INT, TYPE_FLOAT}) || typeof(order) != TYPE_INT && return E_TYPE;
    order < 0 && return E_INVARG;
    const one = typeof(number) == TYPE_FLOAT ? 1.0 | 1;
    let result = one;
    for term in [1..order]
      result = result * number + one;
    endfor
    return result;
  endmethod

  method divmod owner: HACKER
    "Return floor quotient and remainder; a nonzero remainder has the divisor's sign.";
    "Return E_TYPE for nonintegers; division by zero and quotient overflow raise errors.";
    const {numerator, denominator} = args;
    typeof(numerator) != TYPE_INT || typeof(denominator) != TYPE_INT && return E_TYPE;
    numerator == -9223372036854775807 - 1 && denominator == -1 && raise(E_RANGE);
    let quotient = numerator / denominator;
    let remainder = numerator % denominator;
    if (remainder != 0 && remainder < 0 != (denominator < 0))
      quotient = quotient - 1;
      remainder = remainder + denominator;
    endif
    return {quotient, remainder};
  endmethod

  method combinations owner: HACKER
    "Return n choose r; impossible selections return zero. Results must fit an integer.";
    const {number, chosen} = args;
    typeof(number) != TYPE_INT || typeof(chosen) != TYPE_INT && return E_TYPE;
    number < 0 || chosen < 0 || chosen > number && return 0;
    const count = min(chosen, number - chosen);
    let result = 1;
    for position in [1..count]
      let factor = number - count + position;
      let divisor = position;
      const common = this:gcd(factor, divisor);
      factor = factor / common;
      divisor = divisor / common;
      result = result / divisor;
      result <= 9223372036854775807 / factor || raise(E_RANGE, "Combination count exceeds integer range.");
      result = result * factor;
    endfor
    return result;
  endmethod

  method permutations owner: HACKER
    "Return the number of ordered selections of r items from n; selecting zero items gives one.";
    const {number, chosen} = args;
    typeof(number) != TYPE_INT || typeof(chosen) != TYPE_INT && return E_TYPE;
    number < 0 || chosen < 0 || chosen > number && return 0;
    let result = 1;
    for offset in [0..chosen - 1]
      const factor = number - offset;
      result <= 9223372036854775807 / factor || raise(E_RANGE, "Permutation count exceeds integer range.");
      result = result * factor;
    endfor
    return result;
  endmethod

  method simpson owner: HACKER
    "Apply Simpson's rule to {a, b} and {f(a), f((a+b)/2), f(b)}.";
    "Integer inputs return parts(numerator, 6); a true third argument requests a float.";
    const {points, values, ?as_float = false} = args;
    if (!as_float && typeof(points[1]) == TYPE_INT)
      const numerator = (points[2] - points[1]) * (values[1] + 4 * values[2] + values[3]);
      return this:parts(numerator, 6);
    endif
    return (tofloat(points[2]) - tofloat(points[1])) * (tofloat(values[1]) + 4.0 * tofloat(values[2]) + tofloat(values[3])) / 6.0;
  endmethod

  method parts owner: HACKER
    "Return {whole, decimal_digits} for numerator/divisor, truncating toward zero.";
    "Precision defaults to five. Scaled remainder and result must fit signed integers.";
    const {numerator, divisor, ?precision = 5} = args;
    typeof(numerator) != TYPE_INT || typeof(divisor) != TYPE_INT || typeof(precision) != TYPE_INT && return E_TYPE;
    precision < 0 || precision > 18 && return E_INVARG;
    numerator == -9223372036854775807 - 1 && divisor == -1 && raise(E_RANGE);
    const whole = numerator / divisor;
    const remainder = divisor == -1 ? 0 | numerator % divisor;
    const scale = 10 ^ precision;
    remainder > 9223372036854775807 / scale || remainder < (-9223372036854775807 - 1) / scale && raise(E_RANGE);
    return {whole, remainder * scale / divisor};
  endmethod

  method sqrt owner: HACKER
    "Return a float square root, or the exact floor square root for an integer.";
    const {number} = args;
    typeof(number) != TYPE_INT && return sqrt(number);
    number < 0 && raise(E_INVARG);
    number == 0 && return 0;
    let root = toint(sqrt(tofloat(number)));
    while (root > number / root)
      root = root - 1;
    endwhile
    while (root + 1 <= number / (root + 1))
      root = root + 1;
    endwhile
    return root;
  endmethod

  method div owner: HACKER
    "Return integer floor division, including for operands with different signs.";
    const result = this:divmod(@args);
    return typeof(result) == TYPE_ERR ? result | result[1];
  endmethod

  method mod owner: HACKER
    "Return an integer remainder with the divisor's sign, or zero for an exact division.";
    const {numerator, denominator} = args;
    typeof(numerator) != TYPE_INT || typeof(denominator) != TYPE_INT && return E_TYPE;
    denominator == -1 && return 0;
    return this:divmod(numerator, denominator)[2];
  endmethod

  method exp owner: HACKER
    "Floats use native exp. Integers return decimal parts of a Taylor approximation.";
    "The optional nonnegative order defaults to five; integer intermediates must fit.";
    const {number, ?order = 5} = args;
    typeof(number) == TYPE_FLOAT && return exp(number);
    typeof(number) != TYPE_INT || typeof(order) != TYPE_INT && return E_TYPE;
    order < 0 && return E_INVARG;
    let numerator = 1;
    let factorial = 1;
    for offset in [0..order - 1]
      const factor = order - offset;
      factorial <= 9223372036854775807 / factor || raise(E_RANGE);
      factorial = factorial * factor;
      if (numerator > 0)
        if (number > 0)
          numerator <= 9223372036854775807 / number || raise(E_RANGE);
        elseif (number < 0)
          number >= (-9223372036854775807 - 1) / numerator || raise(E_RANGE);
        endif
      elseif (numerator < 0)
        if (number > 0)
          numerator >= (-9223372036854775807 - 1) / number || raise(E_RANGE);
        elseif (number < 0)
          numerator >= 9223372036854775807 / number || raise(E_RANGE);
        endif
      endif
      const product = numerator * number;
      product <= 9223372036854775807 - factorial || raise(E_RANGE);
      numerator = product + factorial;
    endfor
    return this:parts(numerator, factorial);
  endmethod

  method aexp owner: HACKER
    "Return exp(x/10000) scaled by 10000 and rounded; saturate at the core's $maxint.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    const exponent = tofloat(number) / 10000.0;
    exponent >= log(tofloat($maxint) / 10000.0) && return $maxint;
    return toint(this:rint(exp(exponent) * 10000.0));
  endmethod

  method random owner: HACKER
    "Return a uniform integer between zero and bound, inclusive, in either direction.";
    const {bound} = args;
    typeof(bound) != TYPE_INT && return E_TYPE;
    return this:_random_between(min(0, bound), max(0, bound));
  endmethod

  method random_range owner: HACKER
    "Return a uniform integer in mean-radius through mean+radius; mean defaults to zero.";
    const {radius, ?mean = 0} = args;
    typeof(radius) != TYPE_INT || typeof(mean) != TYPE_INT && return E_TYPE;
    radius == -9223372036854775807 - 1 && raise(E_RANGE);
    const distance = abs(radius);
    mean > 9223372036854775807 - distance || mean < -9223372036854775807 - 1 + distance && raise(E_RANGE);
    return this:_random_between(mean - distance, mean + distance);
  endmethod

  method is_prime owner: HACKER
    "Return whether a positive integer is prime; noninteger input returns E_TYPE.";
    "Long searches yield only near the tick or time budget; every yield commits the transaction.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    number == 2 && return true;
    number < 2 || number % 2 == 0 && return false;
    let divisor = 3;
    let checked = 0;
    while (divisor <= number / divisor)
      number % divisor == 0 && return false;
      divisor = divisor + 2;
      checked = checked + 1;
      if (checked % 64 == 0)
        if (seconds_left() < 2)
          suspend(0);
        else
          suspend_if_needed();
        endif
      endif
    endwhile
    return true;
  endmethod

  method "AND XOR" owner: HACKER
    "Apply AND or XOR to the low 32 bits; return a signed 32-bit integer.";
    const {first, second} = args;
    typeof(first) != TYPE_INT || typeof(second) != TYPE_INT && return E_TYPE;
    const value = (verb == "AND" ? first &. second | first ^. second) &. 4294967295;
    return value >= 2147483648 ? value - 4294967296 | value;
  endmethod

  method OR owner: HACKER
    "Apply OR to the low 32 bits; return a signed 32-bit integer.";
    const {first, second} = args;
    typeof(first) != TYPE_INT || typeof(second) != TYPE_INT && return E_TYPE;
    const value = (first |. second) &. 4294967295;
    return value >= 2147483648 ? value - 4294967296 | value;
  endmethod

  method NOT owner: HACKER
    "Complement the low 32 bits; return a signed 32-bit integer.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    const value = ~number &. 4294967295;
    return value >= 2147483648 ? value - 4294967296 | value;
  endmethod

  method BLFromInt owner: HACKER
    "Return the low 32 bits as integer digits, most significant first.";
    const {number} = args;
    typeof(number) != TYPE_INT && return E_TYPE;
    return { number >> 31 - position &. 1 for position in [0..31] };
  endmethod

  method IntFromBL owner: HACKER
    "Interpret integer binary digits as an unsigned value; empty input is zero.";
    "Raise E_RANGE if the value exceeds the signed integer range.";
    const {bits} = args;
    let result = 0;
    for bit in (bits)
      typeof(bit) == TYPE_INT && bit in {0, 1} || raise(E_INVARG, "Expected binary digits.");
      result <= (9223372036854775807 - bit) / 2 || raise(E_RANGE);
      result = result * 2 + bit;
    endfor
    return result;
  endmethod

  method "gcd greatest_common_divisor" owner: HACKER
    "Return the nonnegative greatest common divisor; gcd(0, 0) is zero.";
    "Raise E_RANGE only when the positive result cannot fit an integer.";
    let {first, second} = args;
    typeof(first) != TYPE_INT || typeof(second) != TYPE_INT && return E_TYPE;
    first > 0 && (first = -first);
    second > 0 && (second = -second);
    while (second != 0)
      const remainder = second == -1 ? 0 | first % second;
      first = second;
      second = remainder;
    endwhile
    first == -9223372036854775807 - 1 && raise(E_RANGE);
    return -first;
  endmethod

  method "lcm least_common_multiple" owner: HACKER
    "Return the nonnegative least common multiple; either zero input gives zero.";
    const {first, second} = args;
    typeof(first) != TYPE_INT || typeof(second) != TYPE_INT && return E_TYPE;
    first == 0 || second == 0 && return 0;
    first == -9223372036854775807 - 1 || second == -9223372036854775807 - 1 && raise(E_RANGE);
    const factor = abs(first) / this:gcd(first, second);
    const other = abs(second);
    factor <= 9223372036854775807 / other || raise(E_RANGE);
    return factor * other;
  endmethod

  method "are_rel_prime are_relatively_prime" owner: HACKER
    "Return whether two integers have greatest common divisor one.";
    const common = this:gcd(@args);
    return typeof(common) == TYPE_ERR ? common | common == 1;
  endmethod

  method base_conversion owner: HACKER
    "Convert nonnegative integer text between bases 2 through 62; return a string.";
    "The optional case flag distinguishes a-z from A-Z. Invalid text returns E_INVARG.";
    "The parsed value must fit a signed integer; overflow raises E_RANGE.";
    length(args) < 3 && return E_INVARG;
    const {input, source, target, ?case_sensitive = false} = args;
    const source_base = toint(source);
    const target_base = toint(target);
    source_base < 2 || source_base > 62 || target_base < 2 || target_base > 62 && return E_INVARG;
    const text = tostr(input);
    const alphabet = this.base_alphabet;
    let value = 0;
    for position in [1..length(text)]
      const digit = index(alphabet, text[position], case_sensitive) - 1;
      digit < 0 || digit >= source_base && return E_INVARG;
      value <= (9223372036854775807 - digit) / source_base || raise(E_RANGE);
      value = value * source_base + digit;
    endfor
    value == 0 && return "0";
    let result = "";
    while (value > 0)
      result = alphabet[value % target_base + 1] + result;
      value = value / target_base;
    endwhile
    return result;
  endmethod

  method norm owner: HACKER
    "Return the integer part of the Euclidean norm of integer arguments.";
    "Use exact integer squares when they fit; larger inputs use a scaled float approximation.";
    !args && raise(E_ARGS);
    let largest = 0.0;
    let square_sum = 0;
    let exact = true;
    for number in (args)
      typeof(number) == TYPE_INT || raise(E_TYPE);
      largest = max(largest, abs(tofloat(number)));
      if (exact)
        if (number < -3037000499 || number > 3037000499)
          exact = false;
        else
          const square = number * number;
          if (square_sum > 9223372036854775807 - square)
            exact = false;
          else
            square_sum = square_sum + square;
          endif
        endif
      endif
    endfor
    exact && return this:sqrt(square_sum);
    let scaled_sum = 0.0;
    for number in (args)
      const scaled = tofloat(number) / largest;
      scaled_sum = scaled_sum + scaled * scaled;
    endfor
    return toint(largest * sqrt(scaled_sum));
  endmethod

  method sin owner: HACKER
    "Float arguments use radians and return floats; integers use degrees and return 10000-scaled values.";
    "A {degrees, minutes} pair also requests the scaled interface.";
    const {angle} = args;
    typeof(angle) == TYPE_FLOAT && return sin(angle);
    let degrees = 0.0;
    if (typeof(angle) == TYPE_INT)
      degrees = tofloat(angle % 360);
    elseif (typeof(angle) == TYPE_LIST)
      const {whole, minutes} = angle;
      typeof(whole) != TYPE_INT || typeof(minutes) != TYPE_INT && return E_TYPE;
      degrees = tofloat(whole % 360) + tofloat(minutes % 21600) / 60.0;
    else
      return E_INVARG;
    endif
    return toint(this:rint(sin(this:deg2rad(degrees)) * 10000.0));
  endmethod

  method cos owner: HACKER
    "Float arguments use radians and return floats; integers use degrees and return 10000-scaled values.";
    "A {degrees, minutes} pair also requests the scaled interface.";
    const {angle} = args;
    typeof(angle) == TYPE_FLOAT && return cos(angle);
    let degrees = 0.0;
    if (typeof(angle) == TYPE_INT)
      degrees = tofloat(angle % 360);
    elseif (typeof(angle) == TYPE_LIST)
      const {whole, minutes} = angle;
      typeof(whole) != TYPE_INT || typeof(minutes) != TYPE_INT && return E_TYPE;
      degrees = tofloat(whole % 360) + tofloat(minutes % 21600) / 60.0;
    else
      return E_INVARG;
    endif
    return toint(this:rint(cos(this:deg2rad(degrees)) * 10000.0));
  endmethod

  method tan owner: HACKER
    "Float arguments use radians and return floats; integers use degrees and return 10000-scaled values.";
    "A {degrees, minutes} pair also requests the scaled interface.";
    const {angle} = args;
    typeof(angle) == TYPE_FLOAT && return tan(angle);
    let degrees = 0.0;
    if (typeof(angle) == TYPE_INT)
      degrees = tofloat(angle % 360);
    elseif (typeof(angle) == TYPE_LIST)
      const {whole, minutes} = angle;
      typeof(whole) != TYPE_INT || typeof(minutes) != TYPE_INT && return E_TYPE;
      degrees = tofloat(whole % 360) + tofloat(minutes % 21600) / 60.0;
    else
      return E_INVARG;
    endif
    abs(degrees % 180.0) == 90.0 && raise(E_DIV);
    return toint(this:rint(tan(this:deg2rad(degrees)) * 10000.0));
  endmethod

  method "arcsin asin" owner: HACKER
    "Float arguments return radians. Scaled integer inputs return {degrees, minutes}.";
    "Minutes are rounded to the nearest minute; negative angles use signed components.";
    const {number} = args;
    typeof(number) == TYPE_FLOAT && return asin(number);
    typeof(number) != TYPE_INT && return E_TYPE;
    number < -10000 || number > 10000 && return E_RANGE;
    const angle = this:rad2deg(asin(tofloat(number) / 10000.0));
    const minutes = toint(this:rint(angle * 60.0));
    return {minutes / 60, minutes % 60};
  endmethod

  method "arccos acos" owner: HACKER
    "Float arguments return radians. Scaled integer inputs return {degrees, minutes}.";
    "Minutes are rounded to the nearest minute; negative angles use signed components.";
    const {number} = args;
    typeof(number) == TYPE_FLOAT && return acos(number);
    typeof(number) != TYPE_INT && return E_TYPE;
    number < -10000 || number > 10000 && return E_RANGE;
    const angle = this:rad2deg(acos(tofloat(number) / 10000.0));
    const minutes = toint(this:rint(angle * 60.0));
    return {minutes / 60, minutes % 60};
  endmethod

  method "arctan atan" owner: HACKER
    "Float arguments return radians. Scaled integer inputs return {degrees, minutes}.";
    "Minutes are rounded to the nearest minute; negative angles use signed components.";
    const {number} = args;
    typeof(number) == TYPE_FLOAT && return atan(number);
    typeof(number) != TYPE_INT && return E_TYPE;
    const angle = this:rad2deg(atan(tofloat(number) / 10000.0));
    const minutes = toint(this:rint(angle * 60.0));
    return {minutes / 60, minutes % 60};
  endmethod

  method "deg2rads deg2rad" owner: HACKER
    "Convert degrees to radians as a float.";
    return tofloat(args[1]) * (this.pi / 180.0);
  endmethod

  method "rads2deg rad2deg" owner: HACKER
    "Convert radians to degrees as a float.";
    return tofloat(args[1]) * (180.0 / this.pi);
  endmethod

  method precision owner: HACKER
    "Round a float to the requested decimal places; ties round away from zero.";
    const {number, digits} = args;
    const scale = 10.0 ^ digits;
    return this:rint(number * scale) / scale;
  endmethod

  method round owner: HACKER
    "Round an integer to a positive integer multiple; ties go toward positive infinity.";
    const {number, multiple} = args;
    typeof(number) != TYPE_INT || typeof(multiple) != TYPE_INT && return E_TYPE;
    multiple <= 0 && return E_INVARG;
    const remainder = this:mod(number, multiple);
    if (remainder < multiple - remainder)
      number >= -9223372036854775807 - 1 + remainder || raise(E_RANGE);
      return number - remainder;
    endif
    const increment = multiple - remainder;
    number <= 9223372036854775807 - increment || raise(E_RANGE);
    return number + increment;
  endmethod

  method "mean average" owner: HACKER
    "Return the arithmetic mean of a list or positional arguments; integers truncate toward zero.";
    const values = args && typeof(args[1]) == TYPE_LIST ? args[1] | args;
    !values && raise(E_DIV);
    const total = this:sum(values);
    return typeof(total) == TYPE_FLOAT ? total / tofloat(length(values)) | total / length(values);
  endmethod

  method sum_float owner: HACKER
    "Sum a list or positional arguments, preserving the first item's numeric type.";
    "Empty input returns 0.0. Nonempty inputs must use compatible numeric types.";
    const values = args && typeof(args[1]) == TYPE_LIST ? args[1] | args;
    !values && return 0.0;
    let total = values[1];
    for number in (values[2..$])
      total = total + number;
    endfor
    return total;
  endmethod

  method "sum_int sum" owner: HACKER
    "Sum a list or positional arguments, preserving the first item's numeric type.";
    "Empty input returns 0. Nonempty inputs must use compatible numeric types.";
    const values = args && typeof(args[1]) == TYPE_LIST ? args[1] | args;
    !values && return 0;
    let total = values[1];
    for number in (values[2..$])
      total = total + number;
    endfor
    return total;
  endmethod

  method rint owner: HACKER
    "Round a float to the nearest integer-valued float; ties round away from zero.";
    const {number} = args;
    return trunc(number > 0.0 ? number + 0.5 | number - 0.5);
  endmethod

  method _random_between owner: HACKER
    "Internal inclusive integer sampling; native random requires strictly positive bounds.";
    const {low, high} = args;
    low > high && raise(E_INVARG);
    low == high && return low;
    if (low >= 0 || high < 0 || high < 9223372036854775807 + low)
      const width = high - low;
      width < 9223372036854775807 && return low + (random(width + 1) - 1);
    endif
    "Wide ranges cover at least half the integer space. Rejection avoids overflow and modulo bias.";
    while (true)
      const sample = random(4294967296) - 1 << 32 |. random(4294967296) - 1;
      sample >= low && sample <= high && return sample;
    endwhile
  endmethod
endobject
