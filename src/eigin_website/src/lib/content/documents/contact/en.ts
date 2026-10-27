import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Contact",
  description: "How to get in touch with Eigin.",
  introduction: [
    {
      html: `<p>Questions, feedback, press, partnerships, or just curious? Here's how to reach us.</p>`,
    },
    {
      action: {
        label: "Say hello",
        href: "mailto:hello@eigin.ai",
      },
    },
    {
      html: `<p>Or write to us at hello@eigin.ai.</p>`,
    },
  ],
  sections: [
    {
      id: "support",
      title: "Support",
      html: `<p>Having trouble with the app? Go to the <a href="/support/">support page</a>.</p>`,
    },
    {
      id: "community",
      title: "Community",
      html: `<p>Join the conversation in our <a href="https://chat.eigin.ai" target="_blank" rel="noopener">Matrix chat</a>, or follow the code at <a href="https://code.eigin.ai" target="_blank" rel="noopener">code.eigin.ai</a>.</p>`,
    },
    {
      id: "company",
      title: "Company",
      html: `<p><strong>Eigin ApS</strong><br>CVR 46428765<br>Denmark</p>`,
    },
  ],
};

export default content;
