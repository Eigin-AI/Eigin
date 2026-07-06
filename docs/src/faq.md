# Frequently asked questions

**Isn't this just a wrapper around an AI API?**

No. The inference call is one part of a larger system. Eigin is a persistent agent with its own identity, knowledge graph, and context management that carry across conversations. The model is a component, not the product.

**How does the local/cloud split work?**

The agent, its data, and its tools run on device. With a cloud provider, the inference call goes off device with your key. With a local model, nothing leaves the device.

**Why native apps rather than cross-platform or web?**

Eigin does heavy lifting at the platform level: on-device ML, hardware acceleration, background execution, deep OS integration. Cross-platform frameworks cost you drift, performance, and UI fidelity this close to the metal. Native fits what we're building.

**Can I self-host the relay?**

Yes. It ships as a Docker image with Terraform to deploy it. Configure it with your own keys.

**How does Eigin's agent model differ from frameworks like OpenClaw or NemoClaw?**

Those are server-side, autonomy-first frameworks built to give an agent broad control over a machine or workflow. Eigin is edge-oriented: the agent runs on the user's device, serves the individual, and operates within a least-privilege permission model. Personal AI, not an autonomous system.

**How do I contribute?**

See [CONTRIBUTING.md](https://code.eigin.ai/dev/eigin/-/blob/main/CONTRIBUTING.md).
