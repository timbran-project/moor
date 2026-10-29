# mooR Native Verb Library Exception

Version 1, 2026-10-29.

This exception is an additional permission under section 7 of the GNU Affero General Public License,
version 3 ("AGPL"), granted by the copyright holders of mooR.

## Definitions

"mooR" means the software in this repository that is licensed under the AGPL.

"Native Verb Interface" means the interface through which the mooR daemon loads a library and calls
its functions: the `moor_native_library` entry point, the descriptor it returns, the table of
functions the daemon passes it, and the calling convention for native verb functions, as defined by
the `moor-native-verb` crate, its `moor_native.h` header, and their documentation.

"Interface Libraries" means the parts of mooR licensed under the GNU Lesser General Public License,
version 3 or later ("LGPL"): the `moor-native-verb` crate, including its `moor_native.h` header.

A "Native Verb Library" is a library that mooR loads only through the Native Verb Interface, and
that contains no part of mooR other than Interface Libraries, used under the terms of the LGPL.

## Grant of additional permission

You may create, use and convey a Native Verb Library under terms of your choice. Loading a Native
Verb Library into mooR, and exchanging values with it through the Native Verb Interface, does not by
itself make the library a work based on mooR, and does not make the AGPL apply to the library.

Your use of the Interface Libraries remains subject to the LGPL.

## Scope

This exception does not change the license of mooR itself. mooR, and any modification of it, remain
under the AGPL, including a modification that changes the Native Verb Interface. A library that uses
any other part of mooR, or that mooR reaches other than through the Native Verb Interface, is not a
Native Verb Library.

When you convey a copy or modification of mooR, you may keep or remove this exception for that copy,
as section 7 of the AGPL allows for additional permissions.
