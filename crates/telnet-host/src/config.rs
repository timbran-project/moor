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

//! Telnet protocol configuration: which out-of-band protocols the host implements.
//!
//! Every protocol is off by default; with the defaults the host is passive and the bytes on the
//! wire are what they were before the protocol layer existed. See
//! `doc/telnet-oob-protocols.md`, section "Configuration".

use std::collections::BTreeMap;

use clap_derive::Args;
use serde::{Deserialize, Serialize};

use crate::session::telnet::{ProtocolPolicy, negotiator::DEFAULT_MAX_SUBNEG};

/// Default inbound `ClientData` rate per connection, in messages per second.
pub const DEFAULT_CLIENT_DATA_RATE: u32 = 50;

/// The `protocols` section of the telnet host configuration.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Args)]
#[serde(default, deny_unknown_fields)]
pub struct TelnetProtocolConfig {
    /// Send WILL/DO offers for the enabled protocols when a connection opens
    #[arg(long = "telnet-protocols-offer-on-connect")]
    pub offer_on_connect: bool,
    /// Implement GMCP (option 201)
    #[arg(long = "telnet-protocols-gmcp")]
    pub gmcp: bool,
    /// Implement MSDP (option 69)
    #[arg(long = "telnet-protocols-msdp")]
    pub msdp: bool,
    /// Answer MSSP (option 70) from `mssp_values`
    #[arg(long = "telnet-protocols-mssp")]
    pub mssp: bool,
    /// Implement MXP (option 91) and render rich output with MXP links
    #[arg(long = "telnet-protocols-mxp")]
    pub mxp: bool,
    /// Accept NAWS (option 31) window sizes
    #[arg(long = "telnet-protocols-naws")]
    pub naws: bool,
    /// Accept TTYPE (option 24) and MTTS
    #[arg(long = "telnet-protocols-ttype")]
    pub ttype: bool,
    /// Mark prompts with EOR (option 25)
    #[arg(long = "telnet-protocols-eor")]
    pub eor: bool,
    /// Negotiate CHARSET (option 42)
    #[arg(long = "telnet-protocols-charset")]
    pub charset: bool,
    /// Compress output with MCCP2 (option 86)
    #[arg(long = "telnet-protocols-mccp2")]
    pub mccp2: bool,
    /// Largest subnegotiation accepted, in bytes; larger ones are discarded
    #[arg(long = "telnet-protocols-max-subneg", default_value_t = DEFAULT_MAX_SUBNEG)]
    pub max_subneg: usize,
    /// Inbound ClientData messages per second per connection (burst is twice this); 0 is unlimited
    #[arg(long = "telnet-protocols-client-data-rate", default_value_t = DEFAULT_CLIENT_DATA_RATE)]
    pub client_data_rate: u32,
    /// Static MSSP variables (config file only). PLAYERS and UPTIME are computed by the host.
    #[arg(skip)]
    pub mssp_values: BTreeMap<String, String>,
}

impl Default for TelnetProtocolConfig {
    fn default() -> Self {
        Self {
            offer_on_connect: false,
            gmcp: false,
            msdp: false,
            mssp: false,
            mxp: false,
            naws: false,
            ttype: false,
            eor: false,
            charset: false,
            mccp2: false,
            max_subneg: DEFAULT_MAX_SUBNEG,
            client_data_rate: DEFAULT_CLIENT_DATA_RATE,
            mssp_values: BTreeMap::new(),
        }
    }
}

impl From<&TelnetProtocolConfig> for ProtocolPolicy {
    fn from(c: &TelnetProtocolConfig) -> Self {
        ProtocolPolicy {
            offer_on_connect: c.offer_on_connect,
            gmcp: c.gmcp,
            msdp: c.msdp,
            mssp: c.mssp,
            mxp: c.mxp,
            naws: c.naws,
            ttype: c.ttype,
            eor: c.eor,
            charset: c.charset,
            mccp2: c.mccp2,
            max_subneg: c.max_subneg,
            mssp_values: c
                .mssp_values
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;
    use clap_derive::Parser;
    use std::io::Write;

    #[derive(Parser, Debug)]
    struct Cli {
        #[command(flatten)]
        protocols: TelnetProtocolConfig,
    }

    #[test]
    fn defaults_are_all_off_and_passive() {
        let c = TelnetProtocolConfig::default();
        assert!(!c.offer_on_connect);
        assert_eq!(c.max_subneg, 65536);
        assert_eq!(c.client_data_rate, 50);
        let policy = ProtocolPolicy::from(&c);
        assert!(!policy.any_enabled());
        assert_eq!(policy, ProtocolPolicy::default());
    }

    #[test]
    fn cli_defaults_match_serde_defaults() {
        let cli = Cli::parse_from(["test"]);
        assert_eq!(cli.protocols, TelnetProtocolConfig::default());
        let cli = Cli::parse_from([
            "test",
            "--telnet-protocols-gmcp",
            "--telnet-protocols-max-subneg",
            "1024",
        ]);
        assert!(cli.protocols.gmcp);
        assert!(!cli.protocols.msdp);
        assert_eq!(cli.protocols.max_subneg, 1024);
    }

    #[derive(Serialize, Deserialize, Default)]
    #[serde(default, deny_unknown_fields)]
    struct Wrapper {
        protocols: TelnetProtocolConfig,
    }

    fn load(yaml: &str) -> Result<Wrapper, eyre::Report> {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(yaml.as_bytes()).unwrap();
        moor_common::config::apply_yaml_config_file(Wrapper::default(), Some(file.path()))
    }

    #[test]
    fn yaml_round_trip() {
        let w = load(
            "protocols:\n  gmcp: true\n  mssp: true\n  max_subneg: 4096\n  mssp_values:\n    NAME: Test\n    CODEBASE: mooR\n",
        )
        .unwrap();
        let c = &w.protocols;
        assert!(c.gmcp && c.mssp && !c.msdp);
        assert_eq!(c.max_subneg, 4096);
        assert_eq!(c.client_data_rate, 50);
        let policy = ProtocolPolicy::from(c);
        assert_eq!(
            policy.mssp_values,
            vec![
                ("CODEBASE".to_string(), "mooR".to_string()),
                ("NAME".to_string(), "Test".to_string()),
            ]
        );
        let json = serde_json::to_string(c).unwrap();
        let back: TelnetProtocolConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(&back, c);
    }

    #[test]
    fn unknown_field_is_rejected() {
        assert!(load("protocols:\n  gmpc: true\n").is_err());
        assert!(serde_json::from_str::<TelnetProtocolConfig>(r#"{"gmpc": true}"#).is_err());
    }
}
