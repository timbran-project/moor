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

use super::{
    OAuth2Config, OAuth2Manager, OAuth2ProviderConfig, OAuthHttpClient, http_client_builder,
};
use axum::{
    Json, Router,
    http::HeaderMap,
    response::Redirect,
    routing::{get, post},
};
use oauth2::AsyncHttpClient;
use std::{collections::HashMap, sync::Arc, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};
use tokio_rustls::{
    TlsAcceptor,
    rustls::{
        ServerConfig,
        pki_types::{CertificateDer, PrivateKeyDer, pem::PemObject},
    },
};

#[tokio::test]
async fn exchanges_tokens_fetches_user_info_and_rejects_redirects() {
    let app = Router::new()
        .route(
            "/token",
            post(|headers: HeaderMap, body: String| async move {
                assert_eq!(
                    headers["authorization"],
                    "Basic dGVzdC1jbGllbnQ6dGVzdC1zZWNyZXQ="
                );
                assert_eq!(headers["content-type"], "application/x-www-form-urlencoded");
                let fields =
                    url::form_urlencoded::parse(body.as_bytes()).collect::<HashMap<_, _>>();
                assert_eq!(fields.get("code").unwrap(), "test-code");
                assert_eq!(fields.get("grant_type").unwrap(), "authorization_code");
                Json(serde_json::json!({"access_token": "test-token", "token_type": "bearer"}))
            }),
        )
        .route(
            "/userinfo",
            get(|headers: HeaderMap| async move {
                assert_eq!(headers["authorization"], "Bearer test-token");
                Json(serde_json::json!({"id": 42, "login": "fixture-user"}))
            }),
        )
        .route(
            "/redirect",
            post(|| async { Redirect::temporary("/token") }),
        );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let config = OAuth2Config {
        enabled: true,
        base_url: base.clone(),
        providers: HashMap::from([(
            "github".into(),
            OAuth2ProviderConfig {
                client_id: "test-client".into(),
                client_secret: "test-secret".into(),
                auth_url: format!("{base}/authorize"),
                token_url: format!("{base}/token"),
                user_info_url: format!("{base}/userinfo"),
                scopes: vec![],
            },
        )]),
        ..Default::default()
    };
    tokio::time::timeout(Duration::from_secs(5), async {
        let manager = OAuth2Manager::new(config.clone()).unwrap();
        let user = manager
            .complete_oauth2_flow("github", "test-code".into())
            .await
            .unwrap();
        assert_eq!(user.external_id, "42");
        assert_eq!(user.username.as_deref(), Some("fixture-user"));

        let mut redirected = config;
        redirected.providers.get_mut("github").unwrap().token_url = format!("{base}/redirect");
        let manager = OAuth2Manager::new(redirected).unwrap();
        assert!(
            manager
                .exchange_code("github", "test-code".into())
                .await
                .is_err()
        );
    })
    .await
    .expect("OAuth exchange timed out");
    server.abort();
}

#[tokio::test]
async fn https_requires_a_trusted_certificate() {
    const CA: &[u8] = include_bytes!("../../../../telnet-host/tests/fixtures/tls/ca.pem");
    const CHAIN: &[u8] = include_bytes!("../../../../telnet-host/tests/fixtures/tls/ec-chain.pem");
    const KEY: &[u8] = include_bytes!("../../../../telnet-host/tests/fixtures/tls/ec-pkcs8.pem");
    let certs = CertificateDer::pem_slice_iter(CHAIN)
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    let key = PrivateKeyDer::from_pem_slice(KEY).unwrap();
    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .unwrap();
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!(
        "https://localhost:{}",
        listener.local_addr().unwrap().port()
    );
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        assert!(acceptor.accept(socket).await.is_err());
        let (socket, _) = listener.accept().await.unwrap();
        let mut tls = acceptor.accept(socket).await.unwrap();
        let mut request = Vec::new();
        while !request.ends_with(b"\r\n\r\n") {
            request.push(tls.read_u8().await.unwrap());
            assert!(request.len() < 8192);
        }
        assert!(request.starts_with(b"GET / HTTP/1.1\r\n"));
        tls.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
            .await
            .unwrap();
        tls.shutdown().await.unwrap();
    });
    tokio::time::timeout(Duration::from_secs(5), async {
        let untrusted = http_client_builder().no_proxy().build().unwrap();
        assert!(untrusted.get(&url).send().await.is_err());
        let trusted = reqwest::Client::builder()
            .no_proxy()
            .tls_certs_only([reqwest::Certificate::from_pem(CA).unwrap()])
            .build()
            .unwrap();
        assert_eq!(
            trusted
                .get(&url)
                .send()
                .await
                .unwrap()
                .text()
                .await
                .unwrap(),
            "ok"
        );
        server.await.unwrap();
    })
    .await
    .expect("HTTPS exchange timed out");
}

#[tokio::test]
async fn oauth_adapter_preserves_http_data_and_transport_errors() {
    use axum::http::{Response, StatusCode, Version};

    let app = Router::new()
        .route(
            "/echo",
            post(|headers: HeaderMap, body: String| async move {
                assert_eq!(headers["x-request-marker"], "request-value");
                assert_eq!(body, "raw request body");
                Response::builder()
                    .status(StatusCode::CREATED)
                    .header("x-response-marker", "first")
                    .header("x-response-marker", "second")
                    .body(axum::body::Body::from("raw response body"))
                    .unwrap()
            }),
        )
        .route(
            "/denied",
            post(|| async {
                (
                    StatusCode::UNAUTHORIZED,
                    Json(serde_json::json!({"error": "invalid_grant"})),
                )
            }),
        )
        .route(
            "/slow",
            post(|| async {
                tokio::time::sleep(Duration::from_secs(1)).await;
                "too late"
            }),
        );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let manager = OAuth2Manager::new(OAuth2Config::default()).unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        let request = oauth2::http::Request::builder()
            .method("POST")
            .uri(format!("{base}/echo"))
            .header("x-request-marker", "request-value")
            .body(b"raw request body".to_vec())
            .unwrap();
        let response = OAuthHttpClient(&manager.http_client)
            .call(request)
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CREATED);
        assert_eq!(response.version(), Version::HTTP_11);
        assert_eq!(
            response
                .headers()
                .get_all("x-response-marker")
                .iter()
                .map(|v| v.to_str().unwrap())
                .collect::<Vec<_>>(),
            ["first", "second"]
        );
        assert_eq!(response.body(), b"raw response body");

        let request = oauth2::http::Request::builder()
            .method("POST")
            .uri(format!("{base}/denied"))
            .body(Vec::new())
            .unwrap();
        let response = OAuthHttpClient(&manager.http_client)
            .call(request)
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(response.body()).unwrap()["error"],
            "invalid_grant"
        );

        let mut short_timeout = manager;
        short_timeout.http_client = http_client_builder()
            .timeout(Duration::from_millis(25))
            .build()
            .unwrap();
        let request = oauth2::http::Request::builder()
            .method("POST")
            .uri(format!("{base}/slow"))
            .body(Vec::new())
            .unwrap();
        let error = OAuthHttpClient(&short_timeout.http_client)
            .call(request)
            .await
            .unwrap_err();
        assert!(matches!(error, oauth2::HttpClientError::Reqwest(e) if e.is_timeout()));
    })
    .await
    .expect("OAuth adapter tests timed out");
    server.abort();
}
