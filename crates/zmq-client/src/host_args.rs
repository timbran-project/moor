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

use moor_runtime_api::{RpcError, client_args::RpcClientConfig};
#[cfg(unix)]
use tracing::{info, warn};

use crate::{ZmqHostServices, rpc_client::RpcConfig};

/// Socket and admission limits for standalone ZeroMQ hosts.
#[derive(Clone, Debug, clap_derive::Args, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct HostRpcArgs {
    /// Native context limit, including RPC and subscription sockets.
    #[arg(long, default_value_t = 4096)]
    pub zmq_max_sockets: i32,
    #[command(flatten)]
    #[serde(flatten)]
    pub pool: RpcConfig,
}

impl Default for HostRpcArgs {
    fn default() -> Self {
        Self {
            zmq_max_sockets: 4096,
            pool: RpcConfig::default(),
        }
    }
}

impl HostRpcArgs {
    pub fn validate(&self) -> Result<(), RpcError> {
        self.pool.validate()?;
        if self.zmq_max_sockets <= 0 || self.pool.max_sockets >= self.zmq_max_sockets as usize {
            return Err(RpcError::Fatal(
                "zmq-max-sockets must exceed rpc-max-sockets to allow subscriptions".into(),
            ));
        }
        Ok(())
    }

    pub async fn host_services(
        &self,
        connection: &RpcClientConfig,
        curve_keys: Option<(String, String, String)>,
    ) -> Result<ZmqHostServices, RpcError> {
        self.validate()?;
        raise_open_file_limit(self.zmq_max_sockets);
        let context = r0z::Context::new();
        context
            .set_max_sockets(self.zmq_max_sockets)
            .map_err(|e| RpcError::Fatal(format!("Cannot set ZeroMQ socket limit: {e}")))?;
        let services = ZmqHostServices::with_rpc_config(
            context,
            connection.rpc_address.clone(),
            connection.events_address.clone(),
            curve_keys,
            self.pool.clone(),
        );
        services.rpc_client().reserve_control_sockets().await?;
        Ok(services)
    }
}

/// Open files a host can need: each ZeroMQ socket holds about three descriptors once connected,
/// and the rest is room for the host's own listeners and client connections.
fn open_files_wanted(zmq_max_sockets: i32) -> u64 {
    u64::try_from(zmq_max_sockets).unwrap_or(0) * 3 + 1024
}

/// The soft limit to ask for, if the current one is too low: as much as wanted, within the hard
/// limit.
fn soft_limit_to_set(soft: u64, hard: u64, wanted: u64) -> Option<u64> {
    (soft < wanted && soft < hard).then(|| wanted.min(hard))
}

/// Raise this process's soft limit on open files to suit the ZeroMQ socket limit. Soft limits are
/// often 1024, which a host would reach long before its socket limit, with far hard limits above.
#[cfg(unix)]
// rlim_t is u64 on the common platforms, but not on all.
#[allow(clippy::useless_conversion, clippy::unnecessary_cast)]
fn raise_open_file_limit(zmq_max_sockets: i32) {
    let wanted = open_files_wanted(zmq_max_sockets);
    let mut limit = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    // SAFETY: getrlimit only writes the limit it is given, which outlives the call.
    if unsafe { libc::getrlimit(libc::RLIMIT_NOFILE, &raw mut limit) } != 0 {
        warn!(
            "Cannot read the open file limit: {}",
            std::io::Error::last_os_error()
        );
        return;
    }
    let (soft, hard) = (u64::from(limit.rlim_cur), u64::from(limit.rlim_max));
    let mut reached = soft;
    if let Some(target) = soft_limit_to_set(soft, hard, wanted) {
        limit.rlim_cur = target as libc::rlim_t;
        // SAFETY: setrlimit only reads the limit it is given, which outlives the call.
        if unsafe { libc::setrlimit(libc::RLIMIT_NOFILE, &raw const limit) } == 0 {
            info!(from = soft, to = target, "Raised the open file limit");
            reached = target;
        } else {
            warn!(
                "Cannot raise the open file limit: {}",
                std::io::Error::last_os_error()
            );
        }
    }
    if reached < wanted {
        warn!(
            limit = reached,
            wanted,
            zmq_max_sockets,
            "The open file limit is too low for the ZeroMQ socket limit, and sessions may fail \
             before reaching it"
        );
    }
}

#[cfg(not(unix))]
fn raise_open_file_limit(_zmq_max_sockets: i32) {}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn open_file_limit_rises_only_as_far_as_needed_and_allowed() {
        assert_eq!(open_files_wanted(4096), 13312);
        assert_eq!(soft_limit_to_set(1024, 524288, 13312), Some(13312));
        assert_eq!(soft_limit_to_set(1024, 4096, 13312), Some(4096));
        assert_eq!(soft_limit_to_set(4096, 4096, 13312), None);
        assert_eq!(soft_limit_to_set(20000, 524288, 13312), None);
    }

    #[derive(clap_derive::Parser, serde::Serialize, serde::Deserialize)]
    struct Args {
        #[command(flatten)]
        rpc: HostRpcArgs,
    }

    #[cfg(unix)]
    #[test]
    fn raising_the_open_file_limit_reaches_what_the_hard_limit_allows() {
        raise_open_file_limit(4096);
        let mut limit = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        // SAFETY: getrlimit only writes the limit it is given, which outlives the call.
        assert_eq!(
            unsafe { libc::getrlimit(libc::RLIMIT_NOFILE, &raw mut limit) },
            0
        );
        #[allow(clippy::useless_conversion)]
        let (soft, hard) = (u64::from(limit.rlim_cur), u64::from(limit.rlim_max));
        assert!(soft >= open_files_wanted(4096).min(hard));
    }

    #[test]
    fn cli_and_serde_defaults_agree() {
        let args = Args::try_parse_from(["host"]).unwrap().rpc;
        let deserialized: HostRpcArgs = serde_json::from_str("{}").unwrap();
        assert_eq!(
            serde_json::to_value(args).unwrap(),
            serde_json::to_value(deserialized).unwrap()
        );
    }

    #[test]
    fn limits_are_configurable_and_validated() {
        let args = Args::try_parse_from([
            "host",
            "--rpc-max-sockets",
            "256",
            "--rpc-control-sockets",
            "8",
            "--rpc-host-sockets",
            "2",
            "--rpc-control-acquire-timeout-ms",
            "9000",
            "--rpc-max-waiters",
            "512",
            "--rpc-control-max-waiters",
            "300",
            "--rpc-acquire-timeout-ms",
            "2000",
            "--zmq-max-sockets",
            "8192",
            "--rpc-send-timeout-ms",
            "-1",
            "--rpc-receive-timeout-ms",
            "-1",
        ])
        .unwrap()
        .rpc;
        args.validate().unwrap();
        assert_eq!(args.pool.max_sockets, 256);
        assert_eq!(args.pool.control_reserved_sockets, 8);
        assert_eq!(args.pool.host_reserved_sockets, 2);
        assert_eq!(args.pool.control_acquire_timeout_ms, 9000);
        assert_eq!(args.pool.max_waiters, 512);
        assert_eq!(args.pool.control_max_waiters, 300);
        assert_eq!(args.pool.acquire_timeout_ms, 2000);
        assert_eq!(args.zmq_max_sockets, 8192);
        assert_eq!(args.pool.send_timeout_ms, -1);
        assert_eq!(args.pool.receive_timeout_ms, -1);
        let mut invalid = args;
        invalid.pool.control_reserved_sockets = invalid.pool.max_sockets;
        assert!(invalid.validate().is_err());
        invalid.pool.control_reserved_sockets = 0;
        assert!(invalid.validate().is_err());
        invalid.pool.control_reserved_sockets = 4;
        invalid.pool.host_reserved_sockets = 0;
        assert!(invalid.validate().is_err());
        invalid.pool.host_reserved_sockets = 4;
        invalid.zmq_max_sockets = invalid.pool.max_sockets as i32;
        assert!(invalid.validate().is_err());
    }

    #[test]
    fn yaml_overrides_nested_rpc_limits_and_preserves_defaults() {
        let path =
            std::env::temp_dir().join(format!("moor-rpc-config-{}.yaml", uuid::Uuid::new_v4()));
        std::fs::write(
            &path,
            "rpc:\n  max_sockets: 256\n  control_reserved_sockets: 8\n  zmq_max_sockets: 8192\n",
        )
        .unwrap();
        let result =
            moor_common::config::apply_yaml_config_file(Args::parse_from(["host"]), Some(&path));
        std::fs::remove_file(path).unwrap();
        let args = result.unwrap().rpc;
        args.validate().unwrap();
        assert_eq!(args.pool.max_sockets, 256);
        assert_eq!(args.pool.control_reserved_sockets, 8);
        assert_eq!(args.pool.control_max_waiters, 2048);
        assert_eq!(args.pool.acquire_timeout_ms, 5000);
        assert_eq!(args.zmq_max_sockets, 8192);
    }
}
