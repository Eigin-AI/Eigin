# Local pool recovery checks

Requires Docker and Cargo. Use disposable local PostgreSQL only.
The tests use `POOL_TEST_DATABASE_URL`, never the relay's `DATABASE_URL`,
and do not migrate or modify existing tables (one test creates a temp table).

From the repository root:

```sh
docker run -d --rm --name eigin-pool-test \
  -e POSTGRES_PASSWORD=pool-test -p 127.0.0.1::5432 postgres:17-alpine
until docker exec eigin-pool-test pg_isready -U postgres; do sleep 1; done
port=$(docker port eigin-pool-test 5432/tcp | cut -d: -f2)
POOL_TEST_DATABASE_URL="postgres://postgres:pool-test@127.0.0.1:$port/postgres?sslmode=disable" \
  cargo test --locked --manifest-path src/eigin_relay/Cargo.toml \
  --test pool_recovery -- --ignored --nocapture
docker stop eigin-pool-test
```

All four checks should pass in approximately five seconds after compilation.
The silent-socket check embeds a TCP proxy: after a successful query it stops
forwarding on the first socket without closing it. New sockets still work.
The original pool must recover, and a fresh direct connection through the
same endpoint proves that the database remains reachable.
Every check and pool shutdown has a deadline. Test teardown aborts the proxy
and closes its sockets, including on assertion failure.

## TLS variant

Before stopping the container above, generate a local CA and server certificate
with OpenSSL. Temporary private keys are test-only; never commit them.

```sh
tls=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout "$tls/ca.key" -out "$tls/ca.crt" -subj '/CN=Pool Test CA' \
  -addext 'basicConstraints=critical,CA:TRUE'
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$tls/server.key" -out "$tls/server.csr" -subj '/CN=localhost'
printf '%s\n' 'basicConstraints=critical,CA:FALSE' \
  'subjectAltName=IP:127.0.0.1,DNS:localhost' 'extendedKeyUsage=serverAuth' \
  'keyUsage=digitalSignature,keyEncipherment' > "$tls/server.ext"
openssl x509 -req -days 2 -in "$tls/server.csr" \
  -CA "$tls/ca.crt" -CAkey "$tls/ca.key" -CAcreateserial \
  -out "$tls/server.crt" -extfile "$tls/server.ext"
docker cp "$tls/server.key" eigin-pool-test:/var/lib/postgresql/data/server.key
docker cp "$tls/server.crt" eigin-pool-test:/var/lib/postgresql/data/server.crt
docker exec -u root eigin-pool-test sh -c \
  'chown postgres:postgres /var/lib/postgresql/data/server.* && chmod 600 /var/lib/postgresql/data/server.key'
docker exec -u postgres eigin-pool-test psql -c 'ALTER SYSTEM SET ssl = on'
docker exec -u postgres eigin-pool-test psql -c 'SELECT pg_reload_conf()'
sleep 1
POOL_TEST_DATABASE_URL="postgres://postgres:pool-test@127.0.0.1:$port/postgres?sslmode=verify-full&sslrootcert=$tls/ca.crt" \
  cargo test --locked --manifest-path src/eigin_relay/Cargo.toml \
  --test pool_recovery -- --ignored --nocapture
rm -rf "$tls"
```

## Before/after comparison

Temporarily replace only `vendor/sqlx-core/src/pool/connection.rs` with the
published 0.8.6 source and rerun the checks. Restore the patched file afterward.
Healthy reuse/rollback should pass in both cases. Without the patch, the other
three checks fail their recovery deadlines. With the patch they recover after
roughly five seconds.

This establishes a matching dependency failure. It does not establish the
production incident's trigger or prove all possible TLS close faults recover.

## Local verification for #348

- Published 0.8.6 return implementation: healthy reuse/rollback passed;
  silent socket, stalled callback, and cancelled-query recovery failed.
- Patched implementation: all four checks passed over plain TCP and
  certificate-verified rustls TLS, recovering in approximately five seconds.
- Full relay suite including database tests: 195 passed, zero failed over TLS.
- Production-platform Docker build (`linux/amd64`, musl release): passed.
- Existing compiler warnings remain, including three lifetime-syntax warnings
  exposed by building the vendored dependency as a path dependency.
