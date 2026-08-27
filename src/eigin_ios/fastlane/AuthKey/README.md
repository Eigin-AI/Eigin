# App Store Connect API key

Drop your `AuthKey_<KEY_ID>.p8` here (gitignored — never commit it). Get one
from App Store Connect → Users and Access → Integrations → App Store Connect
API → Generate API Key. Apple only lets you download it once, so keep a
personal backup outside the repo too.

Then point `.env` at it:

```
export ASC_KEY_ID=<KEY_ID>
export ASC_ISSUER_ID=<ISSUER_ID>
export ASC_KEY_PATH=fastlane/AuthKey/AuthKey_<KEY_ID>.p8
```
