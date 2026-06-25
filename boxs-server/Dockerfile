# ── 构建 ──
FROM docker.m.daocloud.io/rust:latest AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./

RUN mkdir .cargo
COPY .cargo/config.toml .cargo/config.toml

COPY .env .env

RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src
COPY src/ src/
COPY migrations/ migrations/
RUN touch src/main.rs && cargo build --release

EXPOSE 8000
CMD ["/app/target/release/boxs-server"]
