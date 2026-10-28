import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Kontakt",
  description: "Sådan kommer du i kontakt med Eigin.",
  introduction: [
    {
      html: `<p>Spørgsmål, feedback, presse eller samarbejde? Måske bare nysgerrig? Sådan får du fat i os.</p>`,
    },
    { action: { label: "Sig hej", href: "mailto:hello@eigin.ai" } },
    { html: `<p>Eller skriv til os på hello@eigin.ai.</p>` },
  ],
  sections: [
    {
      id: "support",
      title: "Support",
      html: `<p>Har du problemer med appen? Besøg <a href="/support/">supportsiden</a>.</p>`,
    },
    {
      id: "community",
      title: "Fællesskab",
      html: `<p>Deltag i vores <a href="https://chat.eigin.ai" target="_blank" rel="noopener">Matrix-chat</a>, eller følg udviklingen på <a href="https://code.eigin.ai" target="_blank" rel="noopener">code.eigin.ai</a>.</p>`,
    },
    {
      id: "company",
      title: "Virksomhed",
      html: `<p><strong>Eigin ApS</strong><br>CVR 46428765<br>Danmark</p>`,
    },
  ],
};

export default content;
