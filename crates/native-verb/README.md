# moor-native-verb

TLDR: The C interface between the mooR daemon and native verb libraries, `include/moor_native.h`,
and a Rust wrapper and macro for writing those libraries.

Downstream uses:

- The kernel loads native verb libraries and implements the function table the header defines.
- A native verb library in C includes the header; one in Rust depends on this crate and declares its
  functions with `native_verb_library!`.
