import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Support",
  description: "Need help with Eigin? Send feedback in the app or email us.",
  introduction: [
    { html: `<p>Something not working? Let us know and we'll help you fix it.</p>` },
    {
      html: `<p>Use <strong>Send Feedback</strong> in <strong>Settings</strong> to send us feedback and support requests directly from the app.</p>`,
    },
    {
      action: {
        label: "Reach out",
        href: "mailto:support@eigin.ai?subject=Eigin%20support%20request",
      },
    },
    { html: `<p>Or email us at support@eigin.ai.</p>` },
  ],
  sections: [
    {
      id: "what-to-include",
      title: "What to include",
      html: `<p>If you email us, please include:</p>
<ul>
  <li>What you were trying to do and what went wrong.</li>
  <li>Your device and operating system.</li>
  <li>Your app version, in <strong>Settings → About</strong>.</li>
  <li>The model you were using.</li>
</ul>
<p class="support-privacy-note">Avoid sending us your conversations if you can.</p>
<p>If logging is enabled, export your logs from <strong>Settings → Advanced → Logging → Export Log</strong> and attach them to your email.</p>`,
    },
    {
      id: "other-help",
      title: "Other ways to reach us",
      html: `<p>Join our <a href="https://chat.eigin.ai" target="_blank" rel="noopener">Matrix chat</a>, or <a href="https://code.eigin.ai" target="_blank" rel="noopener">report a bug</a>.</p>
<p>For anything that isn't a support request, see our <a href="/contact/">contact page</a>.</p>`,
    },
  ],
};

export default content;
