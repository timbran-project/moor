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

//! Age encryption/decryption for event log

use age::x25519;
use std::io::Write;

#[cfg(test)]
use std::io::Read;

/// Encrypt data using Age with a public key (X25519)
/// Returns encrypted bytes on success
pub fn encrypt(plaintext: &[u8], pubkey_str: &str) -> Result<Vec<u8>, String> {
    // Parse the public key
    let recipient = pubkey_str
        .parse::<x25519::Recipient>()
        .map_err(|e| format!("Failed to parse public key: {e}"))?;

    let encryptor = age::Encryptor::with_recipients(
        [Box::new(recipient) as Box<dyn age::Recipient>]
            .iter()
            .map(|r| r.as_ref()),
    )
    .expect("Failed to create encryptor");

    let mut encrypted = vec![];
    let mut writer = encryptor
        .wrap_output(&mut encrypted)
        .map_err(|e| format!("Failed to create encryptor: {e}"))?;

    writer
        .write_all(plaintext)
        .map_err(|e| format!("Failed to write plaintext: {e}"))?;
    writer
        .finish()
        .map_err(|e| format!("Failed to finish encryption: {e}"))?;

    Ok(encrypted)
}

/// Decrypt data using Age with a secret key (X25519)
/// Returns decrypted bytes on success
#[cfg(test)]
pub fn decrypt(ciphertext: &[u8], seckey_str: &str) -> Result<Vec<u8>, String> {
    // Parse the secret key
    let identity = seckey_str
        .parse::<x25519::Identity>()
        .map_err(|e| format!("Failed to parse secret key: {e}"))?;

    let decryptor =
        age::Decryptor::new(ciphertext).map_err(|e| format!("Failed to create decryptor: {e}"))?;

    let mut decrypted = vec![];
    let mut reader = decryptor
        .decrypt(vec![&identity as &dyn age::Identity].into_iter())
        .map_err(|e| format!("Failed to decrypt: {e}"))?;

    reader
        .read_to_end(&mut decrypted)
        .map_err(|e| format!("Failed to read decrypted data: {e}"))?;

    Ok(decrypted)
}

#[cfg(test)]
mod tests {
    use super::*;
    use age::secrecy::ExposeSecret;

    #[test]
    fn decrypts_event_log_ciphertext_from_pinned_age() {
        use base64::Engine;

        // Public fixture produced by Age at d1912012424ccb7b63172813ee2776cc570684fa.
        let key = "AGE-SECRET-KEY-1KUF4NDDMYHZAE93E3A3QETYCS5JNJ4VP2AN7F3R4Z0ADKGCKMK4S6FXEHW";
        let ciphertext = base64::engine::general_purpose::STANDARD
            .decode("YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBSNlhoQ1JmV0lKM2wwTjV0RDBGNGVMNERVRTdyMjNxYnFOUVpyMHdFQmxFClZTaDc0c0Z3ZWFVcmcxcmt2K00wRUFiTjdMdDFVSEgxVzQyOGxwdmlla0EKLT4ga1IlLDRzQGEtZ3JlYXNlIH5RaXkKbkhLVlhNRVVTVTBpeEpxaHFoYmhyQQotLS0gYlBicVYvTWZ0ZjJxWTdDYzFZZk9NSW84REpVOVJTN2twU2RSMEVKY3gyOApn4QZS0N94cAGz56ojeGw+L2j9OLRzDVn9wA52/8vhzgHsH40TjVBR/zD9x3cHhav3XdJTpvc6LgCgem9rFGq/")
            .unwrap();
        assert_eq!(
            decrypt(&ciphertext, key).unwrap(),
            b"persisted mooR event log fixture"
        );
    }

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        // Generate a key pair
        let identity = x25519::Identity::generate();
        let pubkey = identity.to_public();

        let plaintext = b"Hello, World!";
        let pubkey_str = pubkey.to_string();
        let seckey_str = identity.to_string().expose_secret().to_string();

        // Encrypt
        let encrypted = encrypt(plaintext, &pubkey_str).expect("Encryption failed");

        // Decrypt
        let decrypted = decrypt(&encrypted, &seckey_str).expect("Decryption failed");

        assert_eq!(plaintext, decrypted.as_slice());
    }

    #[test]
    fn test_encrypt_with_invalid_pubkey() {
        let plaintext = b"Hello, World!";
        let result = encrypt(plaintext, "invalid_key");
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_with_invalid_seckey() {
        // Generate a valid encrypted message first
        let identity = x25519::Identity::generate();
        let pubkey = identity.to_public();
        let plaintext = b"Hello, World!";
        let encrypted = encrypt(plaintext, &pubkey.to_string()).expect("Encryption failed");

        // Try to decrypt with wrong key
        let wrong_identity = x25519::Identity::generate();
        let wrong_seckey = wrong_identity.to_string().expose_secret().to_string();
        let result = decrypt(&encrypted, &wrong_seckey);
        assert!(result.is_err());
    }
}
