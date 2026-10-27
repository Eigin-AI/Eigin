import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Support",
  description: "Brug for hjælp til Eigin? Giv feedback i appen eller skriv til os.",
  introduction: [
    { html: `<p>Er der noget, der ikke virker? Sig til, så hjælper vi dig med at løse det.</p>` },
    {
      html: `<p>Brug <strong>Giv feedback</strong> i <strong>Indstillinger</strong> til at sende os feedback og supporthenvendelser direkte fra appen.</p>`,
    },
    {
      action: {
        label: "Skriv til os",
        href: "mailto:support@eigin.ai?subject=Eigin%20support%20request",
      },
    },
    { html: `<p>Eller skriv til os på support@eigin.ai.</p>` },
  ],
  sections: [
    {
      id: "what-to-include",
      title: "Hvad skal du have med?",
      html: `<p>Hvis du skriver til os på mail, så fortæl os:</p>
<ul>
  <li>Hvad du prøvede at gøre, og hvad der gik galt.</li>
  <li>Din enhed og dit styresystem.</li>
  <li>Din appversion i <strong>Indstillinger → Om</strong>.</li>
  <li>Hvilken model du brugte.</li>
</ul>
<p class="support-privacy-note">Undgå at sende os dine samtaler, hvis du kan.</p>
<p>Hvis logning er slået til, kan du eksportere dine logs fra <strong>Indstillinger → Avanceret → Logning → Eksportér log</strong> og vedhæfte dem til din mail.</p>`,
    },
    {
      id: "other-help",
      title: "Andre måder at få fat i os",
      html: `<p>Vær med i vores <a href="https://chat.eigin.ai" target="_blank" rel="noopener">Matrix-chat</a>, eller <a href="https://code.eigin.ai" target="_blank" rel="noopener">meld en fejl</a>.</p>
<p>Hvis din henvendelse ikke handler om support, så se vores <a href="/contact/">kontaktside</a>.</p>`,
    },
  ],
};

export default content;
