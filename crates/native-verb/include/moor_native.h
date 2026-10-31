// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

/*
 * The interface between the mooR daemon and native verb libraries.
 *
 * A library exports `moor_native_library`. The daemon calls it once at startup with the table of
 * functions it offers, `moor_api`, and the library returns its descriptor, `moor_library`: its
 * name, its version, and the functions verbs can name.
 *
 * A `moor_value` is any MOO value. An integer, float, boolean or object is held in it directly.
 * Anything else, a string, symbol, list, map, error, flyweight, binary or lambda, stays in the
 * daemon, and the value holds a `moor_ref` to it, read and made only through the table. A ref the
 * library gets during a call is valid until the call returns; `retain` gives one that stays valid
 * until `release`. A string's bytes are borrowed from the daemon for as long as its ref.
 *
 * A native verb runs in steps. It is called at step 0, and either returns, raises, or asks to call
 * a verb or builtin, naming the step to resume at and a value to carry. It is then called again
 * at that step, with that value as `state` and the callee's result as `result`. Its state between
 * steps is only that value, so a task can suspend in the callee and resume after a restart.
 *
 * Functions that can fail return `moor_status`. On MOOR_ERROR, an error is pending on the call:
 * returning MOOR_ERROR from the verb raises it, and `clear_error` drops it. On MOOR_CONFLICT the
 * transaction conflicted: the verb must return MOOR_CONFLICT, and the task is retried from its
 * start. Every function that takes a call is valid only on the thread of that call, during it.
 */

#ifndef MOOR_NATIVE_H
#define MOOR_NATIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The interface version. The daemon refuses a library built for another. */
#define MOOR_NATIVE_ABI 1

typedef int32_t moor_status;
#define MOOR_OK 0
#define MOOR_ERROR 1
#define MOOR_CONFLICT 2

/* Value types, as MOO's typeof() numbers them. MOOR_TYPE_NONE is no value at all, as in a
 * `state` or `result` there is none of, or a map lookup that found nothing. */
#define MOOR_TYPE_INT 0
#define MOOR_TYPE_OBJ 1
#define MOOR_TYPE_STR 2
#define MOOR_TYPE_ERR 3
#define MOOR_TYPE_LIST 4
#define MOOR_TYPE_NONE 6
#define MOOR_TYPE_FLOAT 9
#define MOOR_TYPE_MAP 10
#define MOOR_TYPE_BOOL 14
#define MOOR_TYPE_FLYWEIGHT 15
#define MOOR_TYPE_SYMBOL 16
#define MOOR_TYPE_BINARY 17
#define MOOR_TYPE_LAMBDA 18

/* Object flags, as bits of `flags`. */
#define MOOR_FLAG_USER (1u << 0)
#define MOOR_FLAG_PROGRAMMER (1u << 1)
#define MOOR_FLAG_WIZARD (1u << 2)
#define MOOR_FLAG_READ (1u << 4)
#define MOOR_FLAG_WRITE (1u << 5)
#define MOOR_FLAG_FERTILE (1u << 7)

/* An object reference. Its bits are the daemon's; use obj_from_number and obj_number. */
typedef uint64_t moor_obj;

/* A value the daemon holds: anything but an integer, float, boolean or object. */
typedef struct moor_ref moor_ref;
typedef struct moor_call moor_call;

/* A MOO value. `type` says which member of `as` holds it: `i`, `f`, `b` or `o` for a scalar,
 * `ref` for anything else, and none for MOOR_TYPE_NONE. */
typedef struct moor_value {
    int32_t type;
    union {
        int64_t i;
        double f;
        bool b;
        moor_obj o;
        moor_ref *ref;
    } as;
} moor_value;

static inline moor_value moor_none(void) {
    moor_value v = {MOOR_TYPE_NONE, {0}};
    return v;
}

static inline moor_value moor_int(int64_t i) {
    moor_value v = {MOOR_TYPE_INT, {0}};
    v.as.i = i;
    return v;
}

static inline moor_value moor_float(double f) {
    moor_value v = {MOOR_TYPE_FLOAT, {0}};
    v.as.f = f;
    return v;
}

static inline moor_value moor_bool(bool b) {
    moor_value v = {MOOR_TYPE_BOOL, {0}};
    v.as.b = b;
    return v;
}

static inline moor_value moor_object(moor_obj o) {
    moor_value v = {MOOR_TYPE_OBJ, {0}};
    v.as.o = o;
    return v;
}

typedef struct moor_api {
    uint32_t abi_version;
    /* The size of this table in bytes. */
    uint32_t size;

    /* --- The call ---------------------------------------------------------------------- */
    moor_value (*this_value)(moor_call *call);
    moor_obj (*player)(moor_call *call);
    moor_value (*caller)(moor_call *call);
    /* The verb's name, a symbol. */
    moor_ref *(*verb)(moor_call *call);
    /* The arguments, a list. */
    moor_ref *(*args)(moor_call *call);
    size_t (*arg_count)(moor_call *call);
    /* The argument at `index`, from 0; E_ARGS if there is none. */
    moor_status (*arg)(moor_call *call, size_t index, moor_value *out);
    /* The arguments from `start`, `count` of them; E_ARGS if there are fewer. */
    moor_status (*args_read)(moor_call *call, size_t start, moor_value *out, size_t count);
    /* Whose permissions the verb runs with: its owner. */
    moor_obj (*programmer)(moor_call *call);
    uint32_t (*step)(moor_call *call);
    /* The value carried to this step, or none. */
    moor_value (*state)(moor_call *call);
    /* The callee's result on resuming, or none at step 0. */
    moor_value (*result)(moor_call *call);

    /* --- Ending a step --------------------------------------------------------------------- */
    /* Return `value` from the verb. E_INVARG for no value. */
    moor_status (*ret)(moor_call *call, moor_value value);
    /* Call `verb` (a symbol or string) on `target` with `args` (a list), resuming at `step`,
     * which must not be 0, with `state` (or none). */
    moor_status (*call_verb)(moor_call *call, moor_value target, moor_value verb, moor_value args,
                             uint32_t step, moor_value state);
    /* Call the builtin `name` (a symbol or string), as call_verb. */
    moor_status (*call_builtin)(moor_call *call, moor_value name, moor_value args, uint32_t step,
                                moor_value state);

    /* --- Errors ---------------------------------------------------------------------------- */
    /* Make an error with `code` (such as "E_INVARG", or a custom name) and an optional message,
     * and leave it pending. Returns MOOR_ERROR. */
    moor_status (*raise)(moor_call *call, const char *code, size_t code_len, const char *message,
                         size_t message_len);
    /* Leave the error value `error` pending. Returns MOOR_ERROR, or E_TYPE's if it is not one. */
    moor_status (*raise_value)(moor_call *call, moor_value error);
    /* The pending error, or none. */
    moor_value (*pending_error)(moor_call *call);
    void (*clear_error)(moor_call *call);

    /* --- Refs ------------------------------------------------------------------------------ */
    /* A ref to the same value that stays valid until released, on any later call. */
    moor_ref *(*retain)(moor_call *call, moor_ref *ref);
    void (*release)(moor_ref *ref);
    /* A ref to the same value valid until the call returns, as refs the call makes are: for a
     * retained ref, one that stays valid if it is released during the call. */
    moor_ref *(*local)(moor_call *call, moor_ref *ref);
    /* The type of the value a ref holds. */
    int32_t (*ref_type)(moor_ref *ref);

    /* --- Reading values -------------------------------------------------------------------- */
    /* The UTF-8 bytes of a string or symbol, not NUL-terminated. */
    moor_status (*get_str)(moor_call *call, moor_ref *ref, const char **ptr, size_t *len);
    moor_status (*get_binary)(moor_call *call, moor_ref *ref, const uint8_t **ptr, size_t *len);
    /* As MOO's length(): items of a list, entries of a map, characters of a string, bytes of a
     * binary, contents of a flyweight. */
    moor_status (*length)(moor_call *call, moor_ref *ref, size_t *out);
    /* The item at `index`, from 0. */
    moor_status (*list_get)(moor_call *call, moor_ref *list, size_t index, moor_value *out);
    /* The items from `start`, from 0, `count` of them; E_RANGE if the list is shorter. */
    moor_status (*list_read)(moor_call *call, moor_ref *list, size_t start, moor_value *out,
                             size_t count);
    /* Items that must all be integers, or all numbers read as floats; E_TYPE at the first that
     * is not. */
    moor_status (*list_ints)(moor_call *call, moor_ref *list, size_t start, int64_t *out,
                             size_t count);
    moor_status (*list_floats)(moor_call *call, moor_ref *list, size_t start, double *out,
                               size_t count);
    /* The value at `key`, or none if there is none. */
    moor_status (*map_get)(moor_call *call, moor_ref *map, moor_value key, moor_value *out);
    /* The entry at `index`, from 0, in the map's order. */
    moor_status (*map_entry)(moor_call *call, moor_ref *map, size_t index, moor_value *key,
                             moor_value *value);
    /* The entries from `start`, from 0, `count` of them, in the map's order; E_RANGE if the
     * map has fewer. */
    moor_status (*map_read)(moor_call *call, moor_ref *map, size_t start, moor_value *keys,
                            moor_value *values, size_t count);
    /* An error's code (a symbol), message (a string) and value (or none). */
    moor_status (*error_parts)(moor_call *call, moor_ref *error, moor_value *code,
                               moor_value *message, moor_value *value);
    /* A flyweight's delegate, slots (a map of symbols) and contents (a list). */
    moor_status (*flyweight_parts)(moor_call *call, moor_ref *flyweight, moor_obj *delegate,
                                   moor_value *slots, moor_value *contents);
    /* Whether two values are the very same: equal scalars, or refs to the same storage rather
     * than to equal copies. A property read twice while unchanged gives the same value. */
    bool (*same)(moor_value a, moor_value b);
    /* MOO's ==. */
    bool (*equal)(moor_value a, moor_value b);
    /* MOO's ordering: -1, 0 or 1 in *out; E_TYPE if the values cannot be compared. */
    moor_status (*compare)(moor_call *call, moor_value a, moor_value b, int32_t *out);
    /* MOO's toliteral(), a string. */
    moor_value (*to_literal)(moor_call *call, moor_value value);

    /* --- Making values --------------------------------------------------------------------- */
    /* From UTF-8; E_INVARG if it is not. */
    moor_status (*new_str)(moor_call *call, const char *ptr, size_t len, moor_value *out);
    moor_status (*new_sym)(moor_call *call, const char *ptr, size_t len, moor_value *out);
    moor_value (*new_binary)(moor_call *call, const uint8_t *ptr, size_t len);
    /* E_INVARG for an item with no value, or one whose type does not match what it holds. */
    moor_status (*new_list)(moor_call *call, const moor_value *items, size_t count,
                            moor_value *out);
    moor_value (*new_list_ints)(moor_call *call, const int64_t *items, size_t count);
    moor_value (*new_list_floats)(moor_call *call, const double *items, size_t count);
    /* E_TYPE if a key cannot be a map key. */
    moor_status (*new_map)(moor_call *call, const moor_value *keys, const moor_value *values,
                           size_t count, moor_value *out);
    /* An error value, as `raise` makes, with an optional value (or none). */
    moor_status (*new_error)(moor_call *call, const char *code, size_t code_len,
                             const char *message, size_t message_len, moor_value value,
                             moor_value *out);
    /* A flyweight with `delegate`, `slots` (a map of symbol or string keys, or none) and
     * `contents` (a list, or none). */
    moor_status (*new_flyweight)(moor_call *call, moor_obj delegate, moor_value slots,
                                 moor_value contents, moor_value *out);
    /* Lists and maps never change: these make new ones, sharing what they can. */
    moor_status (*list_append)(moor_call *call, moor_ref *list, moor_value item,
                               moor_value *out);
    moor_status (*list_set)(moor_call *call, moor_ref *list, size_t index, moor_value item,
                            moor_value *out);
    moor_status (*map_set)(moor_call *call, moor_ref *map, moor_value key, moor_value value,
                           moor_value *out);
    moor_status (*map_remove)(moor_call *call, moor_ref *map, moor_value key, moor_value *out);

    /* --- Objects --------------------------------------------------------------------------- */
    moor_obj (*obj_from_number)(int32_t number);
    /* The number of a numbered object, such as 12 for #12; false for any other object. */
    bool (*obj_number)(moor_obj obj, int32_t *out);

    /* --- The world, as the verb's programmer ---------------------------------------------- */
    moor_status (*valid)(moor_call *call, moor_obj obj, bool *out);
    moor_status (*parent)(moor_call *call, moor_obj obj, moor_obj *out);
    moor_status (*children)(moor_call *call, moor_obj obj, moor_value *out);
    moor_status (*ancestors)(moor_call *call, moor_obj obj, moor_value *out);
    moor_status (*isa)(moor_call *call, moor_obj obj, moor_obj ancestor, bool *out);
    moor_status (*location)(moor_call *call, moor_obj obj, moor_obj *out);
    moor_status (*contents)(moor_call *call, moor_obj obj, moor_value *out);
    moor_status (*owner)(moor_call *call, moor_obj obj, moor_obj *out);
    moor_status (*name)(moor_call *call, moor_obj obj, moor_value *out);
    moor_status (*flags)(moor_call *call, moor_obj obj, uint16_t *out);
    /* A property, named by a symbol or string. */
    moor_status (*property)(moor_call *call, moor_obj obj, moor_value name, moor_value *out);
    moor_status (*set_property)(moor_call *call, moor_obj obj, moor_value name,
                                moor_value value);
    /* Object metadata, keyed by a symbol or string; none if there is none. */
    moor_status (*metadata)(moor_call *call, moor_obj obj, moor_value key, moor_value *out);
    moor_status (*set_metadata)(moor_call *call, moor_obj obj, moor_value key,
                                moor_value value);
    /* Whether `verb` (a symbol or string) can be called on `obj`. */
    moor_status (*responds_to)(moor_call *call, moor_obj obj, moor_value verb, bool *out);
} moor_api;

/* A native verb. It returns MOOR_OK after ret, call_verb or call_builtin, MOOR_ERROR to raise
 * the pending error, or MOOR_CONFLICT. */
typedef moor_status (*moor_native_fn)(moor_call *call);

typedef struct moor_function {
    /* The name verbs use for the function, NUL-terminated UTF-8. */
    const char *name;
    moor_native_fn call;
} moor_function;

/* What `moor_native_library` returns. It must stay valid while the library is loaded. */
typedef struct moor_library {
    uint32_t abi_version;
    /* The library's name, NUL-terminated UTF-8, which verbs use to name it. */
    const char *name;
    /* The library's version, NUL-terminated UTF-8, for display only. */
    const char *version;
    const moor_function *functions;
    size_t function_count;
} moor_library;

/* The function every library exports. `api` stays valid for the life of the process. */
const moor_library *moor_native_library(const moor_api *api);

#ifdef __cplusplus
}
#endif

#endif /* MOOR_NATIVE_H */
