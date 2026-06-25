# Manipulating MOO Values

There are several functions for performing primitive operations on MOO values, and they can be
cleanly split into two kinds: those that do various very general operations that apply to all types
of values, and those that are specific to one particular type. There are so many operations
concerned with objects that we do not list them in this section but rather give them their own
section following this one.

## General Operations Applicable to All Values

### `typeof`

```
int typeof(value)
```

Takes any MOO value and returns an integer representing the type of value.

The result can be compared against the type constant literals: `TYPE_INT`, `TYPE_FLOAT`, `TYPE_STR`,
`TYPE_LIST`, `TYPE_OBJ`, `TYPE_ERR`, `TYPE_BOOL`, `TYPE_MAP`, `TYPE_FLYWEIGHT`, `TYPE_SYM`. Thus,
one usually writes code like this:

```
if (typeof(x) == TYPE_LIST) ...
```

and not like this:

```
if (typeof(x) == 4) ...
```

because the former is much more readable than the latter.

### `tostr`

```
str tostr(value, ...)
```

Converts all of the given MOO values into strings and returns the concatenation of the results.

```
tostr(17)                  =>   "17"
tostr(1.0/3.0)             =>   "0.333333333333333"
tostr(#17)                 =>   "#17"
tostr("foo")               =>   "foo"
tostr({1, 2})              =>   "{list}"
tostr([1 -> 2]             =>   "[map]"
tostr(E_PERM)              =>   "Permission denied"
tostr("3 + 4 = ", 3 + 4)   =>   "3 + 4 = 7"
```

Warning `tostr()` does not do a good job of converting lists and maps into strings; all lists,
including the empty list, are converted into the string `"{list}"` and all maps are converted into
the string `"[map]"`. The function `toliteral()`, below, is better for this purpose.

### `toliteral`

```
str toliteral(value)
```

Returns a string containing a MOO literal expression that, when evaluated, would be equal to value.

```
toliteral(17)         =>   "17"
toliteral(1.0/3.0)    =>   "0.333333333333333"
toliteral(#17)        =>   "#17"
toliteral("foo")      =>   "\"foo\""
toliteral({1, 2})     =>   "{1, 2}"
toliteral([1 -> 2]    =>   "[1 -> 2]"
toliteral(E_PERM)     =>   "E_PERM"
```

### `fromliteral`

```
any fromliteral(str)
```

Parses a string containing one MOO literal value and returns that value. This is the inverse of
`toliteral()` for values that have literal representations.

`fromliteral()` parses data, not code. It is the right tool for accepting serialized values from
players, files, web requests, or other untrusted sources where using `eval()` would run arbitrary
MOO code.

```
fromliteral("17")                    =>   17
fromliteral("\"foo\"")               =>   "foo"
fromliteral("{1, \"two\", #-1}")     =>   {1, "two", #-1}
fromliteral("E_PERM")                =>   E_PERM
fromliteral("1 + 2")                 =>   raises E_INVARG
```

If the argument is not a string, `fromliteral()` raises `E_TYPE`. If the string is not exactly one
valid literal value, it raises `E_INVARG`.

### `toint`

```
int toint(value)
```

Converts the given MOO value into an integer and returns that integer.

Floating-point numbers are rounded toward zero, truncating their fractional parts. Object numbers
are converted into the equivalent integers. Strings are trimmed and parsed as the decimal encoding
of a real number which is then converted to an integer. Errors are converted into integers obeying
the same ordering (with respect to `<=` as the errors themselves. `toint()` raises `E_TYPE` if value
is a list. If value is a string but the string does not contain a syntactically-correct number, then
`toint()` returns 0.

```
toint(34.7)        =>   34
toint(-34.7)       =>   -34
toint(#34)         =>   34
toint("34")        =>   34
toint("34.7")      =>   34
toint(" - 34  ")   =>   -34
toint(E_TYPE)      =>   1
```

### `toobj`

```
obj toobj(value)
```

Converts the given MOO value into an object number and returns that object number.

The conversions are very similar to those for `toint()` except that for strings, the number _may_ be
preceded by `#`.

```
toobj("34")       =>   #34
toobj("#34")      =>   #34
toobj("foo")      =>   #0
toobj({1, 2})     =>   E_TYPE (error)
```

### `tofloat`

```
float tofloat(value)
```

Converts the given MOO value into a floating-point number and returns that number.

Integers and object numbers are converted into the corresponding integral floating-point numbers.
Strings are trimmed and parsed as the decimal encoding of a real number which is then represented as
closely as possible as a floating-point number. Errors are first converted to integers as in
`toint()` and then converted as integers are. `tofloat()` raises `E_TYPE` if value is a list. If
value is a string but the string does not contain a syntactically-correct number, then `tofloat()`
returns 0.

```
tofloat(34)          =>   34.0
tofloat(#34)         =>   34.0
tofloat("34")        =>   34.0
tofloat("34.7")      =>   34.7
tofloat(E_TYPE)      =>   1.0
```

### `equal`

```
int equal(value, value2)
```

Returns true if value1 is completely indistinguishable from value2.

This is much the same operation as `value1 == value2` except that, unlike `==`, the `equal()`
function does not treat upper- and lower-case characters in strings as equal and thus, is
case-sensitive.

```
"Foo" == "foo"         =>   1
equal("Foo", "foo")    =>   0
equal("Foo", "Foo")    =>   1
```

### `value_bytes`

```
int value_bytes(value)
```

Returns the number of bytes of the server's memory required to store the given value.

### `value_hash`

```
str|binary value_hash(value [, str algorithm] [, int binary])
```

Returns a hash of the value's canonical mooR CBOR representation.

By default this returns an uppercase hexadecimal SHA256 digest. If `binary` is true, the return
value is a binary value containing the raw digest bytes. See the description of `string_hash()` for
the supported algorithms.

This is useful when you want to tell whether two MOO values have the same stored structure without
keeping the whole value around. For example, a package loader might record the hash of an imported
property value and later compare it with the current value to see whether that property has changed.

`value_hash()` is a mooR extension. It is not part of the original LambdaMOO builtin set.

### `value_diff`

```
map value_diff(old, new [, options])
```

Returns a bounded structural diff between two MOO values. See
[Structural Value Diffs](./value-diffs.md) for the result format, options, and examples.

### `value_diff3`

```
map value_diff3(base, local, incoming [, options])
```

Performs a conservative three-way structural comparison. It returns an automatically resolved value
when only one side changed, or a manual conflict containing separate local and incoming diffs. See
[Structural Value Diffs](./value-diffs.md).

### `encode_cbor`

```
binary encode_cbor(value)
```

Encodes a value as mooR's canonical CBOR representation and returns the encoded bytes as a binary
value.

[CBOR](https://en.wikipedia.org/wiki/CBOR) stands for Concise Binary Object Representation. It is a
binary serialization format: instead of turning a value into human-readable text, it turns the value
into bytes that another program can store, transmit, or decode later. It is roughly in the same
family of ideas as JSON, but it is binary rather than text.

mooR uses a specific CBOR representation for MOO values. That representation preserves mooR-specific
distinctions such as strings versus symbols and integers versus objects. It is also the
representation used by `value_hash()`, so the following two values will only have the same
`value_hash()` result if their encoded structure is the same.

Use `encode_cbor()` when you want a compact, round-trippable form of a MOO value and you do not need
people to read or edit it directly. Typical uses include storing an opaque value blob in another
property, writing values to an external file or service, passing values to a non-MOO tool that knows
mooR's CBOR layout, or recording the exact value that was hashed by `value_hash()`.

```
blob = encode_cbor({#17, "score", 42});
decode_cbor(blob)   =>   {#17, "score", 42}
```

CBOR is not a replacement for every textual representation. Use `toliteral()` and `fromliteral()`
when you want a small value format that programmers can read or type. Use objdef output when you
want to dump or restore objects. Use JSON when you are talking to software that expects ordinary
JSON data. Use CBOR when preserving the MOO value structure matters more than readability.

Lambda values are not currently supported by this representation and raise `E_INVARG`.

These functions are mooR extensions. They are not part of the original LambdaMOO builtin set.

### `decode_cbor`

```
any decode_cbor(binary value)
```

Decodes a binary value produced by `encode_cbor()` and returns the original value. Invalid CBOR,
unsupported representation versions, and trailing bytes raise `E_INVARG`.

### `value_hmac`

```
str value_hmac(value, STR key [, STR algo [, binary]])
```

Returns the same string as string_hmac(toliteral(value), key)

See the description of string_hmac() for details.
