# Apple Root CA Certificates

Place Apple Root CA `.cer` files (DER-encoded) here.

Download from Apple:
- https://www.apple.com/certificateauthority/

Required file for App Store Server API / StoreKit 2 JWS verification:
- `AppleRootCA-G3.cer` — Apple Root CA - G3

The relay loads all `.cer` files from this directory at startup. These are public certificates and are safe to commit to the repository.
