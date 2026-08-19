FROM rust:1.92-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends musl-tools \
    && rm -rf /var/lib/apt/lists/*
RUN rustup target add x86_64-unknown-linux-musl
WORKDIR /app

COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --target x86_64-unknown-linux-musl && rm -rf src

COPY src ./src
COPY migrations ./migrations
COPY api.yaml ./api.yaml
RUN touch src/main.rs && cargo build --release --target x86_64-unknown-linux-musl

FROM alpine:3.24
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/eigin-relay /usr/local/bin/
# sqlx migrations (run on startup when DATABASE_URL is set)
COPY --from=builder /app/migrations /migrations
# Model catalog and Apple Root CA certificates
# api.yaml is embedded in the binary at compile time — no runtime copy needed
COPY config /config

RUN addgroup -S relay && adduser -S -G relay relay
USER relay

EXPOSE 8080
CMD ["eigin-relay"]
