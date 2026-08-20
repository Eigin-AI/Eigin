# Token key rotation

The relay encrypts credit tokens at rest with `TOKEN_ENCRYPTION_KEY_PRIMARY`. This
rotates that key with no downtime and no lost credits.

Balances aren't tied to the key — only *restore* is (handing a token back to someone who
reinstalled). During a rotation the relay runs the new key as primary and the old key as
a decrypt fallback, while a sweep re-encrypts every wallet onto the new key. The old key
is dropped only once every wallet is on the new one.

The `just infra token-key-*` commands resolve keys and the database URL themselves and
call the `rotate-key` tool for you — you never set environment variables or run the
binary directly. Each step guards the one before it.

Rehearse on staging first, and take a database snapshot before step 4. Set the target:

```sh
export ENV=staging   # or production
```

## 1. Deploy this feature

```sh
just infra deploy $ENV
```

Ships the two-key support and the new Terraform outputs the rest of this relies on. Skip
if it's already deployed.

## 2. Check the starting state

```sh
just infra token-key-status $ENV
```

Fails if an earlier rotation left wallets on an old key. Resolve that before continuing.

## 3. Deploy the new key

```sh
just infra token-key-replace $ENV
```

It prints the current key and the exact `.env` line to add as the secondary, then stops.
Add that line, re-run, and it regenerates the primary — leaving the relay on new primary
+ old secondary, every wallet still readable.

## 4. Re-encrypt every wallet

```sh
just infra token-key-sweep $ENV
```

Shows a dry-run count, asks for confirmation, re-encrypts every wallet onto the new key,
then verifies the drain. Safe to re-run — it resumes where it stopped.

**Undecryptable wallets.** If the sweep reports wallets it couldn't decrypt, they were
encrypted under a key you didn't supply — usually an older key from before rotation was in
place. Their credits still work, but the stored token can't be restored until it's
re-encrypted with the key it was minted under. They aren't under the key you're retiring,
so the rest of the rotation is safe to finish; track down the original key and re-run the
sweep with it, or handle those wallets manually. `token-key-status` will keep listing them
until they're resolved.

## 5. Drop the old key

```sh
just infra token-key-retire $ENV
```

It stops until you remove the secondary line from `.env`, then redeploys. The old key is
now gone. Rotation complete.
