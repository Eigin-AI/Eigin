# Frequently asked questions

## Compared to others

**How is it different from OpenClaw or Hermes?**

They're powerful tools for people who like to tinker: you set up a server, give the agent broad access and see what it can do. Eigin is a native app you just download. It runs on the user's device, serves one person, and works within a least-privilege permission model, so it's safe to use by default.

**How is it different from Muse or Spark?**

They're just as easy to pick up, but they run on their company's servers, under their terms. Eigin is local-first: the agent and everything it knows stay on the user's device, it works with any model, and it keeps the user in the loop.

## How it works

**How does the local/cloud split work?**

Everything lives and runs on the device. Data only leaves for something the user chose: their cloud model, a service they connected, or a relay feature like web search. See [System context](./system-context.md).

**Why native apps rather than cross-platform?**

Eigin does heavy lifting at the platform level: on-device ML, hardware acceleration, background execution and deep OS integration. Cross-platform frameworks would cost performance and quality this close to the metal. Native fits what we're building.

**Can I trust it?**

Eigin runs in a strict agent runtime with a fixed set of declared tools and no shell. By default, it asks before changing the user's data or acting on their behalf. We trade some capability for safety. See [Permissions](./tools/permissions.md) and [Privacy and security](./privacy.md).

## Business and licence

**How do you make money?**

The app is free, and users pay AI providers directly for what they use. We take a margin on inference through [Eigin Relay](./relay.md), which is optional. Most of our revenue comes from adapting Eigin for organisations and institutions.

**Can I self-host?**

The app already runs on the user's device, and anyone can fork it. The relay ships as a Docker image with Terraform, so you can run your own. See [Eigin Relay](./relay.md#self-hosting).

**What if you change the deal?**

There's no lock-in. The user's data stays their own, the code is AGPL, and everything we've shipped under those terms stays that way.

**How do I contribute?**

See [Contributing](./contributing/README.md).
