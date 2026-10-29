// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Native verbs: verbs whose bodies are functions in native libraries the daemon loads at
//! startup. Only libraries an administrator lists are loaded, the set is fixed for the life of
//! the process, and only functions a library declares can be bound to verbs.

use libloading::Library;
use moor_common::{model::TaskPermissions, util::BitEnum};
use moor_native_verb::ffi::{
    ENTRY_SYMBOL, MOOR_CONFLICT, MOOR_ERROR, MOOR_NATIVE_ABI, MOOR_OK, moor_entry_fn, moor_library,
    moor_native_fn,
};
use moor_var::{
    E_INVARG, E_VERBNF, Error, List, NOTHING, Obj, Symbol, Var, program::NativeProgram, v_list,
    v_list_iter, v_obj, v_str,
};
use moor_vm::{ExecState, ExecutionResult, FeaturesConfig, FinallyReason, Frame};
use std::{
    ffi::{CStr, c_char},
    fmt,
    path::{Path, PathBuf},
};

use crate::{
    native_api::{API, NativeCallContext, Outcome, returnable},
    vm::kernel_host::KernelHost,
};

#[derive(Debug, thiserror::Error)]
pub enum NativeVerbsError {
    #[error("Unable to load native verb library {path}: {reason}")]
    Load { path: PathBuf, reason: String },
    #[error(
        "Native verb library {path} was built for interface version {found}; this daemon uses {MOOR_NATIVE_ABI}"
    )]
    Abi { path: PathBuf, found: u32 },
    #[error("Native verb library {path} has a malformed descriptor: {reason}")]
    Descriptor { path: PathBuf, reason: String },
    #[error("Two native verb libraries are named {name}: {first} and {second}")]
    Duplicate {
        name: String,
        first: PathBuf,
        second: PathBuf,
    },
}

struct LoadedLibrary {
    name: Symbol,
    version: String,
    path: PathBuf,
    functions: Vec<(Symbol, moor_native_fn)>,
    // Kept loaded for the life of the process: functions may run at any time.
    _library: Option<Library>,
}

/// The native verb libraries the daemon loaded at startup.
#[derive(Default)]
pub struct NativeVerbs {
    libraries: Vec<LoadedLibrary>,
}

impl fmt::Debug for NativeVerbs {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list()
            .entries(
                self.libraries
                    .iter()
                    .map(|l| (&l.name, &l.version, &l.path)),
            )
            .finish()
    }
}

/// A string from a descriptor, which must be NUL-terminated, non-empty UTF-8.
///
/// # Safety
///
/// `ptr` must be null or point to a NUL-terminated string.
unsafe fn descriptor_str(ptr: *const c_char, what: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{what} is missing"));
    }
    // SAFETY: the caller guarantees a NUL-terminated string.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| format!("{what} is not UTF-8"))?;
    if text.is_empty() {
        return Err(format!("{what} is empty"));
    }
    Ok(text.to_string())
}

impl NativeVerbs {
    /// Load the listed libraries. Any that cannot be loaded, or whose descriptor is malformed or
    /// repeats another's name, stops the load.
    pub fn load(paths: &[PathBuf]) -> Result<Self, NativeVerbsError> {
        let mut native_verbs = Self::default();
        for path in paths {
            // SAFETY: loading runs the library's initializers; the administrator vouches for
            // every library they list.
            let library = unsafe { Library::new(path) }.map_err(|e| NativeVerbsError::Load {
                path: path.clone(),
                reason: e.to_string(),
            })?;
            // SAFETY: the entry function has the documented signature.
            let entry: moor_entry_fn = *unsafe {
                library.get::<moor_entry_fn>(ENTRY_SYMBOL.as_bytes())
            }
            .map_err(|e| NativeVerbsError::Load {
                path: path.clone(),
                reason: format!("it does not export {ENTRY_SYMBOL}: {e}"),
            })?;
            // SAFETY: as above; the descriptor lives as long as the library stays loaded.
            unsafe { native_verbs.add(entry, path, Some(library)) }?;
        }
        Ok(native_verbs)
    }

    /// Add a library linked into this process rather than loaded from a file, under `path` for
    /// messages.
    ///
    /// # Safety
    ///
    /// `entry` must return a valid descriptor that lives for the rest of the process.
    pub unsafe fn add_linked(
        &mut self,
        entry: moor_entry_fn,
        path: &Path,
    ) -> Result<(), NativeVerbsError> {
        // SAFETY: the caller's guarantee.
        unsafe { self.add(entry, path, None) }
    }

    unsafe fn add(
        &mut self,
        entry: moor_entry_fn,
        path: &Path,
        library: Option<Library>,
    ) -> Result<(), NativeVerbsError> {
        let malformed = |reason: String| NativeVerbsError::Descriptor {
            path: path.to_path_buf(),
            reason,
        };
        // SAFETY: the caller guarantees the entry function and its descriptor; the table lives
        // for the life of the process.
        let descriptor: &moor_library = unsafe { entry(&API).as_ref() }.ok_or_else(|| {
            malformed(
                "the entry function returned no descriptor, as it does for a table of another version"
                    .to_string(),
            )
        })?;
        if descriptor.abi_version != MOOR_NATIVE_ABI {
            return Err(NativeVerbsError::Abi {
                path: path.to_path_buf(),
                found: descriptor.abi_version,
            });
        }
        // SAFETY: descriptor strings are NUL-terminated by the library.
        let name =
            unsafe { descriptor_str(descriptor.name, "the library name") }.map_err(malformed)?;
        let version = unsafe { descriptor_str(descriptor.version, "the library version") }
            .map_err(malformed)?;
        let name = Symbol::mk(&name);
        if let Some(first) = self.libraries.iter().find(|l| l.name == name) {
            return Err(NativeVerbsError::Duplicate {
                name: name.to_string(),
                first: first.path.clone(),
                second: path.to_path_buf(),
            });
        }
        let entries = if descriptor.function_count == 0 {
            &[][..]
        } else if descriptor.functions.is_null() {
            return Err(malformed("the function table is missing".to_string()));
        } else {
            // SAFETY: the library declares `function_count` entries at `functions`.
            unsafe { std::slice::from_raw_parts(descriptor.functions, descriptor.function_count) }
        };
        let mut functions: Vec<(Symbol, moor_native_fn)> = Vec::with_capacity(entries.len());
        for entry in entries {
            // SAFETY: as for the library name.
            let function = Symbol::mk(
                &unsafe { descriptor_str(entry.name, "a function name") }.map_err(malformed)?,
            );
            if functions.iter().any(|(existing, _)| *existing == function) {
                return Err(malformed(format!("it declares {function} twice")));
            }
            functions.push((function, entry.call));
        }
        self.libraries.push(LoadedLibrary {
            name,
            version,
            path: path.to_path_buf(),
            functions,
            _library: library,
        });
        Ok(())
    }

    pub fn is_empty(&self) -> bool {
        self.libraries.is_empty()
    }

    /// The function a native verb names, or the reason it cannot run.
    pub fn function(&self, program: &NativeProgram) -> Result<moor_native_fn, Error> {
        let Some(library) = self.libraries.iter().find(|l| l.name == program.library) else {
            return Err(E_VERBNF.msg(format!(
                "Native verb library {} is not loaded",
                program.library
            )));
        };
        library
            .functions
            .iter()
            .find(|(name, _)| *name == program.function)
            .map(|(_, function)| *function)
            .ok_or_else(|| {
                E_VERBNF.msg(format!(
                    "Native verb library {} has no function {}",
                    program.library, program.function
                ))
            })
    }

    /// Run the next step of the native verb at the top of the stack, and carry out how it ended:
    /// return, raise, or call a verb or builtin to resume from.
    pub(crate) fn run_frame(
        &self,
        exec: &mut ExecState,
        config: &FeaturesConfig,
    ) -> ExecutionResult {
        let activation = exec.top_mut();
        let (this, player, verb, permissions) = (
            activation.this.clone(),
            activation.player(),
            activation.verb_name,
            activation.authority(),
        );
        let Frame::Native(frame) = &mut activation.frame else {
            panic!("Expected a native verb frame at the top of the stack");
        };
        let program = frame.program.clone();
        let mut context = NativeCallContext::new(
            this,
            player,
            frame.caller.clone(),
            verb,
            frame.args.clone(),
            permissions,
            frame.step,
            frame.state.take(),
            frame.return_value.take(),
        );
        let function = match self.function(&program) {
            Ok(function) => function,
            Err(error) => return exec.throw_error(error),
        };
        // SAFETY: `function` comes from a loaded library, and the context outlives the call.
        let status = unsafe { function(context.as_call()) };
        exec.tick_count += context.requests;

        let named = |message: &str| {
            E_INVARG.msg(format!(
                "Native verb {}:{} {message}",
                program.library, program.function
            ))
        };
        if context.conflict || status == MOOR_CONFLICT {
            return ExecutionResult::TaskRollbackRestart;
        }
        if status == MOOR_ERROR {
            let error = context
                .pending_error
                .take()
                .unwrap_or_else(|| named("failed without an error"));
            return exec.throw_error(error);
        }
        if status != MOOR_OK {
            return exec.throw_error(named(&format!("returned unknown status {status}")));
        }
        match context.outcome.take() {
            None => exec.throw_error(named("ended without returning")),
            Some(Outcome::Return(value)) if !returnable(&value) => {
                exec.throw_error(named("returned the clear value"))
            }
            Some(Outcome::Return(value)) => exec.unwind_stack(FinallyReason::Return(value)),
            Some(Outcome::CallVerb {
                target,
                verb,
                args,
                step,
                state,
            }) => {
                resume_at(exec, step, state);
                match exec.verb_dispatch(&mut KernelHost, config.type_dispatch, target, verb, args)
                {
                    Ok(result) => result,
                    Err(error) => exec.push_error(error),
                }
            }
            Some(Outcome::CallBuiltin {
                builtin,
                args,
                step,
                state,
            }) => {
                resume_at(exec, step, state);
                ExecutionResult::DispatchBuiltin {
                    builtin,
                    arguments: args,
                }
            }
        }
    }

    /// Run a library's function as a task's first step would, outside any task: for testing a
    /// library, and for tools that use one without a daemon. It runs through the same function
    /// table as a verb does, with `this` and `player` as given and the caller `#-1`. A function
    /// that asks for the world, or to call a verb or builtin, gets an error, as there is no task
    /// to give them.
    pub fn call(
        &self,
        library: &str,
        function: &str,
        this: Var,
        player: Obj,
        args: List,
    ) -> Result<Var, Error> {
        let program = NativeProgram {
            library: Symbol::mk(library),
            function: Symbol::mk(function),
        };
        let native = self.function(&program)?;
        let mut context = NativeCallContext::new(
            this,
            player,
            v_obj(NOTHING),
            program.function,
            args,
            TaskPermissions::new(player, BitEnum::new()),
            0,
            None,
            None,
        );
        // SAFETY: `native` comes from a loaded library, and the context outlives the call.
        let status = unsafe { native(context.as_call()) };
        let named =
            |message: &str| E_INVARG.msg(format!("Native verb {library}:{function} {message}"));
        match status {
            MOOR_OK => match context.outcome.take() {
                Some(Outcome::Return(value)) if returnable(&value) => Ok(value),
                Some(Outcome::Return(_)) => Err(named("returned the clear value")),
                Some(Outcome::CallVerb { .. } | Outcome::CallBuiltin { .. }) => {
                    Err(named("called out, which needs a task"))
                }
                None => Err(named("ended without returning")),
            },
            MOOR_ERROR => Err(context
                .pending_error
                .take()
                .unwrap_or_else(|| named("failed without an error"))),
            MOOR_CONFLICT => Err(named("reported a conflict outside a transaction")),
            other => Err(named(&format!("returned unknown status {other}"))),
        }
    }

    /// The loaded libraries, as `{name, version, {function, ...}}` each.
    pub fn describe(&self) -> Var {
        v_list_iter(self.libraries.iter().map(|library| {
            v_list(&[
                v_str(&library.name.as_arc_str()),
                v_str(&library.version),
                v_list_iter(
                    library
                        .functions
                        .iter()
                        .map(|(name, _)| v_str(&name.as_arc_str())),
                ),
            ])
        }))
    }
}

/// Record where the native verb at the top of the stack resumes after its call.
fn resume_at(exec: &mut ExecState, step: u32, state: Option<Var>) {
    if let Frame::Native(frame) = &mut exec.top_mut().frame {
        frame.step = step;
        frame.state = state;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_native_verb::ffi::{moor_api, moor_call, moor_function, moor_status};

    unsafe extern "C" fn nothing(_call: *mut moor_call) -> moor_status {
        MOOR_OK
    }

    macro_rules! descriptor {
        ($entry:ident, $abi:expr, $name:literal, [$($function:literal),*]) => {
            unsafe extern "C" fn $entry(_api: *const moor_api) -> *const moor_library {
                static FUNCTIONS: &[moor_function] = &[
                    $(moor_function {
                        name: concat!($function, "\0").as_ptr() as *const c_char,
                        call: nothing,
                    }),*
                ];
                static LIBRARY: moor_library = moor_library {
                    abi_version: $abi,
                    name: concat!($name, "\0").as_ptr() as *const c_char,
                    version: "1\0".as_ptr() as *const c_char,
                    functions: FUNCTIONS.as_ptr(),
                    function_count: FUNCTIONS.len(),
                };
                &LIBRARY
            }
        };
    }

    descriptor!(terrain, MOOR_NATIVE_ABI, "terrain", ["column"]);
    descriptor!(terrain_again, MOOR_NATIVE_ABI, "Terrain", ["fill"]);
    descriptor!(future, MOOR_NATIVE_ABI + 1, "future", ["column"]);
    descriptor!(repeated, MOOR_NATIVE_ABI, "repeated", ["column", "column"]);

    unsafe extern "C" fn refuses(_api: *const moor_api) -> *const moor_library {
        std::ptr::null()
    }

    fn add(native_verbs: &mut NativeVerbs, entry: moor_entry_fn) -> Result<(), NativeVerbsError> {
        // SAFETY: every descriptor above is static.
        unsafe { native_verbs.add_linked(entry, Path::new("linked")) }
    }

    #[test]
    fn libraries_are_checked_when_loaded() {
        let mut native_verbs = NativeVerbs::default();
        add(&mut native_verbs, terrain).unwrap();
        assert!(matches!(
            add(&mut native_verbs, terrain_again),
            Err(NativeVerbsError::Duplicate { .. })
        ));
        assert!(matches!(
            add(&mut native_verbs, future),
            Err(NativeVerbsError::Abi { .. })
        ));
        assert!(matches!(
            add(&mut native_verbs, repeated),
            Err(NativeVerbsError::Descriptor { .. })
        ));
        assert!(matches!(
            add(&mut native_verbs, refuses),
            Err(NativeVerbsError::Descriptor { .. })
        ));
        let column = NativeProgram {
            library: Symbol::mk("TERRAIN"),
            function: Symbol::mk("Column"),
        };
        assert!(
            native_verbs.function(&column).is_ok(),
            "names match without case"
        );
    }

    #[test]
    fn missing_files_stop_the_load() {
        let missing = PathBuf::from("/nonexistent/libnothing.so");
        assert!(matches!(
            NativeVerbs::load(&[missing]),
            Err(NativeVerbsError::Load { .. })
        ));
        assert!(NativeVerbs::load(&[]).unwrap().is_empty());
    }
}
