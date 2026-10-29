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

/* A native verb library in C: `sum` adds its integer arguments. */

#include "moor_native.h"

static const moor_api *api;

static moor_status sum(moor_call *call) {
    int64_t total = 0;
    size_t count = api->arg_count(call);
    for (size_t i = 0; i < count; i++) {
        moor_value arg;
        moor_status status = api->arg(call, i, &arg);
        if (status != MOOR_OK) return status;
        if (arg.type != MOOR_TYPE_INT) {
            const char code[] = "E_TYPE", message[] = "sum adds integers";
            return api->raise(call, code, sizeof code - 1, message, sizeof message - 1);
        }
        total += arg.as.i;
    }
    return api->ret(call, moor_int(total));
}

static const moor_function functions[] = {{"sum", sum}};

static const moor_library library = {
    MOOR_NATIVE_ABI, "c_example", "1.0", functions, sizeof functions / sizeof functions[0],
};

const moor_library *moor_native_library(const moor_api *given) {
    if (given->abi_version != MOOR_NATIVE_ABI || given->size < sizeof(moor_api)) return 0;
    api = given;
    return &library;
}
