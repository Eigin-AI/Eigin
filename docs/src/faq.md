# Frequently asked questions

**Isn't this just a wrapper around an AI API?**

No. The inference call is one part of a larger system. Eigin is a persistent agent with its own identity, knowledge graph, and context management that carries across every conversation. The model is a component — it's not the product.

**How does the local/cloud split work?**

The agent, its data, and its tools all run on device. If you're using a cloud provider, the inference call goes off device to that provider with your key. If you're using a local model, nothing leaves the device at all.

**Why native apps rather than cross-platform or web?**

Eigin does a lot of heavy lifting at the platform level - on-device machine learning, hardware-accelerated processing, background execution, deep OS integrations. Cross-platform frameworks have improved a lot, but there's a real cost in drift, performance overhead, and UI fidelity when you're working this close to the metal. Native is the best fit for what we're building.

**Can I self-host the relay?**

Yes. The relay ships as a Docker image and the repository includes Terraform code to deploy it. You can configure it yourself with your own API keys.

**How does Eigin's agent model differ from frameworks like OpenClaw or NemoClaw?**

Those are server-side, autonomy-first frameworks, designed to give an agent broad control over a machine or workflow. Eigin is edge-oriented: the agent runs on the user's device, serves the individual, and operates within a permission model that defaults to least privilege. It's personal AI, not an autonomous system.

**How do I contribute?**

See [CONTRIBUTING.md](https://code.eigin.ai/dev/eigin/-/blob/main/CONTRIBUTING.md).
