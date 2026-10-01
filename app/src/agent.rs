use std::{net::SocketAddr, sync::Arc};

use axum::{
    Json, Router,
    extract::{Request, State},
    http::{HeaderMap, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
};
use serde_json::Value;
use subtle::ConstantTimeEq;
use tracing::info;

use crate::status::SystemMonitor;

pub async fn run(listen: SocketAddr) -> Result<(), String> {
    let metrics_token = std::env::var("METRICS_TOKEN")
        .ok()
        .filter(|value| !value.is_empty());
    let monitor = Arc::new(SystemMonitor::default());

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/system-stats", get(system_stats))
        .with_state(monitor)
        .layer(middleware::from_fn_with_state(
            metrics_token,
            require_metrics_token,
        ));

    let listener = tokio::net::TcpListener::bind(listen)
        .await
        .map_err(|error| format!("failed to bind agent to {listen}: {error}"))?;
    info!("RootOS metrics agent listening on {listen}");
    axum::serve(listener, app)
        .await
        .map_err(|error| format!("metrics agent failed: {error}"))
}

async fn require_metrics_token(
    State(expected): State<Option<String>>,
    request: Request,
    next: Next,
) -> Response {
    let Some(expected) = expected else {
        return next.run(request).await;
    };
    let provided = bearer_token(request.headers());
    let authorized = provided
        .as_deref()
        .is_some_and(|token| bool::from(token.as_bytes().ct_eq(expected.as_bytes())));
    if authorized {
        next.run(request).await
    } else {
        StatusCode::UNAUTHORIZED.into_response()
    }
}

fn bearer_token(headers: &HeaderMap) -> Option<String> {
    let value = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    value
        .strip_prefix("Bearer ")
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .map(str::to_owned)
}

async fn health() -> &'static str {
    "ok"
}

async fn system_stats(
    axum::extract::State(monitor): axum::extract::State<Arc<SystemMonitor>>,
) -> Json<Value> {
    Json(monitor.stats())
}

pub fn listen_address_from_env() -> Result<SocketAddr, String> {
    let listen = std::env::var("ROOTOS_AGENT_LISTEN").unwrap_or_else(|_| "0.0.0.0:9090".to_owned());
    listen
        .parse()
        .map_err(|error| format!("invalid ROOTOS_AGENT_LISTEN {listen:?}: {error}"))
}
