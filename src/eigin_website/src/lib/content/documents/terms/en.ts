import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Terms of Service",
  description: "The terms that apply when you use Eigin.",
  updated: "Last updated: 21 October 2026",
  introduction: [
    {
      html: `<p>These terms cover the Eigin app, the Eigin Relay, and related services, provided by <strong>Eigin ApS</strong>, CVR 46428765, Denmark.</p>`,
    },
    {
      html: `<ul>
        <li>By using Eigin you accept these terms.</li>
        <li>You must be 18 or older.</li>
        <li>Our <a href="/privacy/">privacy policy</a> explains how we handle your data.</li>
      </ul>`,
    },
  ],
  sections: [
    {
      id: "your-device-your-data",
      title: "1. Your device, your data",
      html: `<ul>
        <li>Your data is stored on your device. You are responsible for your device, its security, and your backups.</li>
        <li>We have no access to your local data and cannot recover it.</li>
      </ul>`,
    },
    {
      id: "ai-output-and-actions",
      title: "2. AI output and actions",
      html: `<ul>
        <li>AI output can be inaccurate or inappropriate. It is not professional advice of any kind.</li>
        <li>You are responsible for checking it before relying on it.</li>
        <li>The AI can act on your behalf, such as sending an email or adding a calendar event, when you approve the action. You are responsible for the actions you approve.</li>
        <li>Local models are downloaded through the app and may carry their own licences.</li>
      </ul>`,
    },
    {
      id: "credits",
      title: "3. Credits",
      html: `<ul>
        <li>Hosted AI through the Eigin Relay is paid with credits, bought through your app store.</li>
        <li>Refunds are handled by your app store under its policies.</li>
        <li>Credits do not expire, have no monetary value, and cannot be transferred or resold.</li>
        <li>Credits are tied to your purchase, not to you. We cannot restore a lost wallet.</li>
        <li>Rate limits apply.</li>
      </ul>`,
    },
    {
      id: "acceptable-use",
      title: "4. Acceptable use",
      html: `<p>Do not use Eigin to:</p>
<ul>
        <li>Break the law or infringe the rights of others.</li>
        <li>Attack, overload, or gain unauthorised access to any system.</li>
        <li>Resell or share access to the Relay.</li>
      </ul>
<p>The acceptable-use rules of our AI providers also apply. We may suspend access on breach.</p>`,
    },
    {
      id: "ownership",
      title: "5. Ownership",
      html: `<ul>
        <li>Eigin ApS owns the Eigin name, logo, and software.</li>
        <li>Open-source components are governed by their own licences.</li>
        <li>You own everything you create with Eigin.</li>
      </ul>`,
    },
    {
      id: "third-parties",
      title: "6. Third parties",
      html: `<ul>
        <li>The Relay relies on Corti (Denmark), TensorX (Ireland, Finland), Mistral (France), Staan (France), and Scaleway (EU).</li>
        <li>Purchases are handled by your app store.</li>
        <li>AI providers, accounts, or tools you connect yourself are your relationship with them, under their terms.</li>
        <li>We are not responsible for third-party services.</li>
      </ul>`,
    },
    {
      id: "no-warranty",
      title: "7. No warranty",
      html: `<ul>
        <li>To the extent the law allows, Eigin is provided <strong>as is</strong> and <strong>as available</strong>, without warranties of any kind.</li>
        <li>We do not promise it will be uninterrupted, error-free, or secure. Features may change, and the Relay may be interrupted or discontinued.</li>
        <li>Your mandatory consumer rights are unaffected.</li>
      </ul>`,
    },
    {
      id: "liability",
      title: "8. Liability",
      html: `<ul>
        <li>To the extent the law allows, we are not liable for indirect or consequential damages, or for loss of data or profits.</li>
        <li>Our total liability is capped at the greater of what you paid us in the past twelve months or DKK 500.</li>
        <li>Liability that cannot be excluded by law, such as for gross negligence, is not excluded.</li>
      </ul>`,
    },
    {
      id: "changes",
      title: "9. Changes",
      html: `<p>We may update these terms. The date at the top tells you the current version. Continued use after a change means you accept it.</p>`,
    },
    {
      id: "governing-law",
      title: "10. Governing law",
      html: `<p>Danish law governs these terms, and disputes go before the Danish courts. Mandatory consumer-protection rules in your country of residence are unaffected.</p>`,
    },
    {
      id: "contact",
      title: "11. Contact",
      html: `<p><a href="mailto:hello@eigin.ai">hello@eigin.ai</a></p>`,
    },
  ],
};

export default content;
