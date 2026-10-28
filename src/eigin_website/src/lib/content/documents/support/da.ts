import type { DocumentContent } from "../types";

const content: DocumentContent = {
  title: "Support",
  description: "Brug for hjælp til Eigin? Send feedback i appen eller skriv til os.",
  introduction: [
    { html: `<p>Virker noget ikke? Sig til, så hjælper vi dig med at løse det.</p>` },
    {
      html: `<p>Brug <strong>Giv feedback</strong> under <strong>Indstillinger</strong> til at sende feedback og bede om hjælp direkte fra appen.</p>`,
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
      title: "Hvad skal med?",
      html: `<p>Skriver du en mail, så tag dette med:</p>
<ul>
  <li>Hvad du prøvede at gøre, og hvad der gik galt.</li>
  <li>Din enhed og dit styresystem.</li>
  <li>Appens version i <strong>Indstillinger → Om</strong>.</li>
  <li>Hvilken model du brugte.</li>
</ul>
<p class="support-privacy-note">Undlad så vidt muligt at sende dine samtaler.</p>
<p>Hvis logning er slået til, kan du eksportere dine logs fra <strong>Indstillinger → Avanceret → Logning → Eksportér log</strong> og vedhæfte dem til din mail.</p>`,
    },
    {
      id: "other-help",
      title: "Andre måder at kontakte os på",
      html: `<p>Vær med i vores <a href="https://chat.eigin.ai" target="_blank" rel="noopener">Matrix-chat</a>, eller <a href="https://code.eigin.ai" target="_blank" rel="noopener">indberet en fejl</a>.</p>
<p>Handler det ikke om support, så se vores <a href="/contact/">kontaktside</a>.</p>`,
    },
  ],
};

export default content;
