FROM docker.m.daocloud.io/rust:latest AS builder
WORKDIR /app
COPY boxs-server/Cargo.toml boxs-server/Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src
COPY boxs-server/src/ src/
COPY boxs-server/migrations/ migrations/
RUN touch src/main.rs && cargo build --release

EXPOSE 8000
CMD ["/app/target/release/boxs-server"]
