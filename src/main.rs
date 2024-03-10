use axum::{extract::State, http::StatusCode, response::IntoResponse, routing::get, Json, Router};
use serde::Serialize;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};
use std::{process, time::Duration};
use tokio::{self, signal};
use tower_http::timeout::TimeoutLayer;

#[tokio::main]
async fn main() {
    let config = Config::build().unwrap_or_else(|err| {
        println!("Error while building the configuration: {err}");
        process::exit(1);
    });

    let ssl_addendum = if config.ssl_required {
        "?sslmode=require"
    } else {
        ""
    };
    let db = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .connect(format!("{}{}", config.database_url, ssl_addendum).as_str())
        .await
        .unwrap_or_else(|err| {
            println!("Error while connecting to the database: {err}");
            process::exit(1);
        });

    println!("Successfully connected to database");

    let app = Router::new()
        .route("/health", get(healthcheck))
        .fallback(not_found_handler)
        .layer(TimeoutLayer::new(Duration::from_secs(
            config.global_timeout.into(),
        )))
        .with_state(db);

    let addr = format!("0.0.0.0:{port}", port = config.port);
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .unwrap_or_else(|err| {
            println!("Error while binding the TCP listener to address {addr}: {err}");
            process::exit(1);
        });

    println!("Successfully bind the TCP listener to address {addr}");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap_or_else(|err| {
            println!("Error while serving the routes: {err}");
            process::exit(1);
        });

    println!("App has been gracefully shutdown");
}

async fn healthcheck(State(db): State<Pool<Postgres>>) -> (StatusCode, Json<HealthcheckResponse>) {
    println!("Healthcheck has been called");
    let db_healthy = sqlx::query("SELECT 1").fetch_one(&db).await.is_ok();
    (
        StatusCode::OK,
        Json(HealthcheckResponse {
            ok: true,
            db_ok: db_healthy,
        }),
    )
}

#[derive(Serialize)]
struct HealthcheckResponse {
    db_ok: bool,
    ok: bool,
}

struct Config {
    port: u16,
    global_timeout: u8,
    database_url: String,
    ssl_required: bool,
}

impl Config {
    fn build() -> Result<Self, Box<dyn std::error::Error>> {
        let port = std::env::var("PORT")
            .unwrap_or_else(|_| "3000".to_string())
            .parse::<u16>()?;

        let global_timeout = std::env::var("GLOBAL_TIMEOUT")
            .unwrap_or_else(|_| "10".to_string())
            .parse::<u8>()?;

        let database_url = std::env::var("DATABASE_URL")?;

        let ssl_required = std::env::var("SSL_REQUIRED")
            .unwrap_or_else(|_| "false".to_string())
            .parse::<bool>()?;

        Ok(Self {
            port,
            global_timeout,
            database_url,
            ssl_required,
        })
    }
}

async fn not_found_handler() -> impl IntoResponse {
    (StatusCode::NOT_FOUND, "Page not found")
}

// Taken from https://github.com/tokio-rs/axum/blob/main/examples/graceful-shutdown/src/main.rs
async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install CTRL+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install the terminate signal")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            println!("CTRL+C signal received, app enters graceful shutdown");
        },
        _ = terminate => {
            println!("Termination signal received, app enters graceful shutdown")
        }
    }
}
