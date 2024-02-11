# Deploy a Web server to AWS

The goal of this repository is to implement a trivial web server, deploy it on AWS and describe the process along the way.

## Service description

This is a simple webserver exposing one healthcheck route `GET /health`. The associated handler will check the health of a connected `postgres` database and answer a status `200` response with a JSON body `{ ok: true, services: { database: true } }`.

## Steps

Here is the list of steps that have been taken when developing and deploying the services.

### 1. First iteration of the service

The web server is developed with basic capabilities:
- `GET /health` route which answers a status `200` and JSON data `{ ok: true }`,
- global timeout controlled by env var `GLOBAL_TIMEOUT`,
- server listening on port controlled by env var `PORT`,
- graceful shutdown.

## Development

This repository uses the [rust language](https://www.rust-lang.org/), make sure to have it installed before going further. Installation instructions can be found [here](https://www.rust-lang.org/tools/install).

In order to install dependencies and verify that everything is fine, start by building the project
```console
cargo build
```

Start the server
```console
cargo run
```
