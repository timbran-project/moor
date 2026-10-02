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

use std::{path::PathBuf, sync::Arc, time::Duration};

use moor_telnet_host::load_tls_config;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_rustls::{
    TlsAcceptor, TlsConnector,
    rustls::{
        ClientConfig, RootCertStore,
        pki_types::{CertificateDer, pem::PemObject},
    },
};

const CA: &[u8] = include_bytes!("fixtures/tls/ca.pem");
const EC_CHAIN: &[u8] = include_bytes!("fixtures/tls/ec-chain.pem");
const RSA_CHAIN: &[u8] = include_bytes!("fixtures/tls/rsa-chain.pem");
const EC_PKCS8: &[u8] = include_bytes!("fixtures/tls/ec-pkcs8.pem");
const EC_SEC1: &[u8] = include_bytes!("fixtures/tls/ec-sec1.pem");
const RSA_PKCS8: &[u8] = include_bytes!("fixtures/tls/rsa-pkcs8.pem");
const RSA_PKCS1: &[u8] = include_bytes!("fixtures/tls/rsa-pkcs1.pem");

fn pem_files(cert: &[u8], key: &[u8]) -> (tempfile::TempDir, PathBuf, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let cert_path = dir.path().join("chain.pem");
    let key_path = dir.path().join("key.pem");
    std::fs::write(&cert_path, cert).unwrap();
    std::fs::write(&key_path, key).unwrap();
    (dir, cert_path, key_path)
}

// This suite also runs from moor-server to exercise its unified dependency features.
#[tokio::test]
async fn tls_handshake_with_certificate_chain_and_supported_key_formats() {
    for (cert, key) in [
        (EC_CHAIN, EC_PKCS8),
        (EC_CHAIN, EC_SEC1),
        (RSA_CHAIN, RSA_PKCS8),
        (RSA_CHAIN, RSA_PKCS1),
    ] {
        let (_dir, cert_path, key_path) = pem_files(cert, key);
        let server = load_tls_config(&cert_path, &key_path).unwrap();
        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from_pem_slice(CA).unwrap())
            .unwrap();
        let client = ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth();
        let acceptor = TlsAcceptor::from(server);
        let connector = TlsConnector::from(Arc::new(client));
        let (client_io, server_io) = tokio::io::duplex(4096);
        let server_task = async {
            let mut tls = acceptor.accept(server_io).await.unwrap();
            let mut input = [0; 4];
            tls.read_exact(&mut input).await.unwrap();
            assert_eq!(&input, b"ping");
            tls.write_all(b"pong").await.unwrap();
            tls.flush().await.unwrap();
        };
        let client_task = async {
            let mut tls = connector
                .connect("localhost".try_into().unwrap(), client_io)
                .await
                .unwrap();
            assert_eq!(tls.get_ref().1.peer_certificates().unwrap().len(), 2);
            tls.write_all(b"ping").await.unwrap();
            tls.flush().await.unwrap();
            let mut reply = [0; 4];
            tls.read_exact(&mut reply).await.unwrap();
            assert_eq!(&reply, b"pong");
        };
        tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(server_task, client_task);
        })
        .await
        .expect("TLS handshake and application exchange timed out");
    }
}

#[test]
fn tls_rejects_empty_malformed_and_mismatched_pem() {
    for (cert, key, message) in [
        (&b""[..], EC_PKCS8, "No certificates found"),
        (EC_CHAIN, &b""[..], "No private key found"),
        (
            &b"-----BEGIN CERTIFICATE-----\n!\n-----END CERTIFICATE-----\n"[..],
            EC_PKCS8,
            "Failed to parse certificate",
        ),
        (
            EC_CHAIN,
            &b"-----BEGIN PRIVATE KEY-----\n!\n-----END PRIVATE KEY-----\n"[..],
            "Failed to parse private key",
        ),
        (EC_CHAIN, RSA_PKCS8, "Failed to build TLS config"),
    ] {
        let (_dir, cert_path, key_path) = pem_files(cert, key);
        let error = load_tls_config(&cert_path, &key_path).unwrap_err();
        assert!(error.to_string().contains(message), "{error:?}");
    }
}
