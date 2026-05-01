# Frequently asked questions

**Is Eigin free?** Yes. No tiers, no upgrade prompts, no paid features. Open source.

**Do I need an API key?** Not if you use local models, which run on-device. For cloud providers, some support a one-tap connect flow - press "connect with OpenRouter" and you're done. Others require an API key. Eigin works with AI inference providers to make setup as easy as possible.

**Can I use it offline?** Yes, with local models.

**What happens to my data if I uninstall?** Gone. Everything lives in the app's local storage.

**Isn't this just a wrapper around an AI?** No. Eigin is a local agent: it has identity, memory, and goals that persist across conversations. The intelligence may be remote, but the agent and everything it knows about your life belongs to you.

---

## Eigin vs. the big AI labs

ChatGPT, Claude.ai, and Gemini are platforms. Your conversations live on their servers under terms that can change. These companies are competing for a permanent place in your private life — once they have that, they will monetise it.

Eigin is built in opposition to that. Your data lives on your device. No Eigin account. Your private thoughts don't belong to big tech.

## Eigin vs. OpenClaw

OpenClaw's premise is full autonomy: give an agent control of a machine and let it act. A 2026 audit found 500+ vulnerabilities. Publicly exposed instances are routinely exploited. But even setting security aside, AI models make mistakes: an agent with full access to your email can delete your inbox. Not because it was hacked, just because it got it wrong.

Eigin starts from the opposite premise: least privilege. Read-only by default. Destructive actions require consent. The OS security model as a hard boundary.

The right approach is an agent that earns trust, not one that starts with it. As models improve, you can open up more. For now, the default is caution.

## Eigin vs. NemoClaw

NemoClaw puts OpenClaw in a hardened NVIDIA sandbox. It addresses the security problems, but not the mistake problem: an agent that can organise your email can still delete it, securely. 

NemoClaw's controls are similar to Eigin's, but the starting premise is opposite.

## Eigin vs. OpenCat

OpenCat is a native iOS chat client. Fast, clean, and well-made. It connects directly to AI providers using your own API key, or through an OpenCat Cloud subscription. Chats stay on device.

What it doesn't have: a personal agent. Each conversation starts fresh. OpenCat is a Chinese product with a subscription to sell. Eigin is free, open source, and built in Europe. If provenance matters, that's worth knowing.

## Eigin vs. BYOK chat clients

Open WebUI, AnythingLLM, Chatbox, and similar tools are for power users with their own AI infrastructure. Self-hosted servers, local model rigs, document retrieval pipelines. Most are web interfaces wrapped around a server, not native apps. They don't live on your device or integrate with it.

Different tools for different workflows. They're built for querying data, while Eigin is for personal AI.
