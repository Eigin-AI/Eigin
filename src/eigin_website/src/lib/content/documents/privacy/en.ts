import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Privacy Policy",
  description: "How Eigin handles your data. Which is, as little as possible.",
  updated: "Last updated: 21 October 2026",
  introduction: [
    {
      html: `<p>Eigin keeps your data on your device. We aim to know as little about you as possible.</p>`,
    },
  ],
  sections: [
    {
      id: "who-we-are",
      title: "1. Who we are",
      html: `<p><strong>Eigin ApS</strong>, CVR 46428765, Denmark. Contact: <a href="mailto:hello@eigin.ai">hello@eigin.ai</a>.</p>`,
    },
    {
      id: "your-data-stays-on-your-device",
      title: "2. Your data stays on your device",
      html: `<ul>
        <li>Your chats, the AI's memory, and your settings are stored on your device.</li>
        <li>There are no accounts and no login.</li>
        <li>Your connected data, such as calendar, reminders, location, and email, is read on your device. It leaves only as described in section 3, when the AI needs it to answer you.</li>
        <li>You grant access through your device's permissions. You can revoke access at any time.</li>
        <li>Credentials for connected accounts are stored securely on your device. Disconnecting deletes them.</li>
        <li>Your data is not used for tracking, advertising, or training.</li>
      </ul>`,
    },
    {
      id: "ai-models",
      title: "3. AI models",
      html: `<p>When you send a message, it goes to the AI provider you chose. You pick one during onboarding and can change it in Settings at any time.</p>
<p>Before anything goes to a cloud AI provider, the app asks for your permission. It states what is shared and who receives it, and nothing is sent until you allow it.</p>
<ul>
        <li><strong>Local model.</strong> Runs on your device. No data is shared.</li>
        <li><strong>Your own AI provider.</strong> Goes straight to that provider, using your credentials, under their privacy policy.</li>
        <li><strong>Eigin Relay.</strong> Our service, described below. It passes your message to a hosted AI provider, which is a third party.</li>
      </ul>
<p>What is sent with each message:</p>
<ul>
        <li><strong>The conversation.</strong> Your messages and attachments in it.</li>
        <li><strong>Memories.</strong> Things the AI saved from earlier chats, when they are relevant.</li>
        <li><strong>Connected data.</strong> Data from your calendar, reminders, email, or other connections, only if you explicitly allow the AI to use it, and only when it needs it to answer.</li>
      </ul>`,
    },
    {
      id: "the-eigin-relay",
      title: "4. The Eigin Relay",
      html: `<p>The Relay gives you hosted AI, web search, and inference credits.</p>
<ul>
        <li><strong>Prompts</strong> are passed unread to Corti (Denmark), TensorX (Ireland, Finland) or Mistral (France), depending on the model, with zero data retention.</li>
        <li><strong>Search queries</strong> are passed to Staan (France).</li>
        <li><strong>Credits</strong> are tied to your purchase, not to you. We don't store your name, email, or device ID.</li>
        <li><strong>Your IP address</strong> is used to prevent abuse. It is stored temporarily and may appear in our hosting provider's logs.</li>
      </ul>
<p>The Relay runs on Scaleway cloud in the EU. Third-party AI providers are bound by contract to protect your data as strictly as we do.</p>
<p><strong>Our legal basis:</strong></p>
<ul>
        <li>To provide the service you use.</li>
        <li>To keep it secure.</li>
        <li>To keep the purchase records the law requires.</li>
      </ul>`,
    },
    {
      id: "google-user-data",
      title: "5. Google user data",
      html: `<p>Connecting Gmail is optional. If you don't connect it, skip this section.</p>
<ul>
        <li><strong>What we access.</strong> Reading your email (gmail.readonly) and sending email for you (gmail.send).</li>
        <li><strong>Where it goes.</strong> Your device fetches it straight from Google. It is not stored on our servers.</li>
        <li><strong>How we use it.</strong> Only for what you ask: reading email to answer you, and drafting messages you approve before sending.</li>
        <li><strong>What we don't do.</strong> Use it for advertising, train AI on it, sell it, or let a person at Eigin read it.</li>
        <li><strong>When it is shared.</strong> Only when you ask the AI about your email. The email then goes to the AI model you chose in section 3.</li>
        <li><strong>How it is protected.</strong> Connections are encrypted. Your Google credentials stay on your device. You can disconnect Gmail in the app at any time, or revoke Eigin in your <a href="https://myaccount.google.com/permissions">Google account settings</a>.</li>
      </ul>
<p>Eigin's use and transfer of information received from Google APIs will adhere to the <a href="https://developers.google.com/terms/api-services-user-data-policy#additional_requirements_for_specific_api_scopes">Google API Services User Data Policy</a>, including the Limited Use requirements.</p>`,
    },
    {
      id: "purchases",
      title: "6. Purchases",
      html: `<ul>
        <li>Credits are bought through your app store, under its privacy policy.</li>
        <li>We receive a signed receipt and any refund notice.</li>
        <li>Credits do not expire.</li>
      </ul>`,
    },
    {
      id: "no-tracking",
      title: "7. No tracking",
      html: `<ul>
        <li>Eigin includes no analytics, crash reporting, or telemetry SDKs.</li>
        <li>eigin.ai sets no cookies.</li>
      </ul>`,
    },
    {
      id: "how-long-we-keep-data",
      title: "8. How long we keep data",
      html: `<ul>
        <li><strong>Conversations and searches.</strong> Not stored.</li>
        <li><strong>IP addresses and logs.</strong> Our hosting provider's standard log period, then deleted.</li>
        <li><strong>Credits.</strong> As long as you hold them. Purchase records as long as Danish law requires.</li>
        <li><strong>Data on your device.</strong> Delete the app and your chats, memory, and settings are permanently removed.</li>
      </ul>
<p>To delete your credits, email <a href="mailto:hello@eigin.ai">hello@eigin.ai</a> with your purchase details. Deleting forfeits any remaining credits.</p>`,
    },
    {
      id: "your-rights",
      title: "9. Your rights",
      html: `<ul>
        <li><strong>See, fix, or delete your data.</strong> Email us if you need help. Under the GDPR you can also restrict, move, or object to processing.</li>
        <li><strong>Stop sharing with an AI provider.</strong> Switch to another provider or the local model, or remove the provider, in Settings → Connections.</li>
        <li><strong>Take back a permission.</strong> Use your device's settings, or disconnect the account in the app.</li>
        <li><strong>Complain.</strong> Datatilsynet, <a href="https://www.datatilsynet.dk">datatilsynet.dk</a>.</li>
      </ul>`,
    },
    {
      id: "age",
      title: "10. Age",
      html: `<p>You must be 18 or older to use Eigin.</p>`,
    },
    {
      id: "changes",
      title: "11. Changes",
      html: `<p>We may update this policy. The date at the top tells you the current version.</p>`,
    },
  ],
};

export default content;
