import type { HomeContent } from "./types";

const content: HomeContent = {
  title: "Eigin — AI så personlig, at den skal være din.",
  description: "Personlig AI, der tilhører dig. Åben teknologi, bygget i Europa.",
  hero: {
    headline: "AI så personlig,\nat den skal være din",
    body: "Eigin er en personlig AI-agent, der er privat, sikker og under din kontrol.",
    placeholder: "Brandillustration",
  },
  mission: {
    title: "Hvad ville du sige til en AI, hvis den var helt din egen?",
    paragraphs: [
      "Før havde vi private rum til eftertanke. Nu tænker vi højt med AI, og hvert ord ender på en virksomheds server.",
      "Teknologi, der er så personlig, bør tilhøre dem, der bruger den. Derfor bygger vi Eigin.",
    ],
  },
  personal: {
    id: "personal",
    label: "Til mennesker",
    title: "Agenten, der kender dig bedst",
    body: "Bare tal med den. Den lærer, hvad du går op i, og hjælper med stort og småt på dine vilkår.",
    placeholder: "Chatvisning",
    chat: {
      agent: "Eigin",
      placeholder: "Skriv til Eigin",
      allow: "Tillad",
      examples: "Eksempler på samtaler",
      play: "Afspil demo",
      pause: "Sæt demo på pause",
    },
    examples: [
      {
        label: "Planlæg din dag efter det vigtige",
        ask: "Find tid til min præsentation i dag",
        tools: ["Tjekker din kalender"],
        reply:
          "Dit første møde er kl. 10. Brug kl. 8–9 på præsentationen, før dagen bliver travl. Skal jeg sætte det i din kalender?",
        permission: {
          headline: "Føj til kalender",
          symbol: "functional/timer",
          value: "Fordybelse · kl. 8–9",
        },
      },
      {
        label: "Tænk en svær beslutning igennem",
        ask: "Hvilket job passer til mine prioriteter?",
        tools: ["Tjekker dine prioriteter"],
        reply:
          "Du ville gerne lede et team. Du ville også have mere tid med din søster. Hvilket tilbud giver plads til begge dele?",
        options: [
          {
            label: "Sammenlign tilbuddene",
            description: "Dine prioriteter, side om side",
            symbol: "illustration/tree",
          },
        ],
      },
      {
        label: "Få styr på familielivet",
        ask: "Noget til børnehaven i dag?",
        tools: ["Tjekker Aula"],
        reply:
          "Der er udedag i børnehaven. Pak varmt tøj og vandtætte støvler. Vil du have en påmindelse, før I går?",
        options: [
          {
            label: "Sæt en påmindelse",
            description: "Pak tøj til udedagen",
            symbol: "functional/timer",
          },
        ],
      },
      {
        label: "Overlad rutinearbejdet",
        ask: "Hvilke mails skal jeg svare på i dag?",
        tools: ["Tjekker din indbakke"],
        reply:
          "VVS’eren mangler et tidspunkt. Du er ledig tirsdag kl. 8. Jeg har skrevet et svar — du bestemmer, om det skal sendes.",
        permission: {
          headline: "Send et svar",
          symbol: "functional/mail",
          value: "“Tirsdag kl. 8 passer mig.”",
        },
      },
    ],
  },
  privacy: {
    title: "Privat fra start",
    body: "Eigin er bygget til at holde dine data hos dig og give dig styringen. Vi udvikler åbent, så andre kan se, hvordan teknologien virker, stille spørgsmål og gøre den bedre.",
    action: { label: "Læs mere", href: "/da/trust/" },
    promises: [
      {
        illustration: "illustration/tree",
        title: "Den bor hos dig",
        body: "Dine personlige data gemmes på din egen enhed. Med en lokal model virker den endda offline.",
      },
      {
        illustration: "illustration/person-1",
        title: "Du har det sidste ord",
        body: "Den har et fast sæt værktøjer og spørger dig, før den sender eller ændrer noget.",
      },
      {
        illustration: "illustration/bird",
        title: "Den følger med dig",
        body: "Brug de nyeste modeller eller én på din telefon. Skift når som helst. Din agent er den samme.",
      },
      {
        illustration: "illustration/butterfly",
        title: "Den tjener kun dig",
        body: "Ingen reklamer eller sporing. Vores AI-modeller kører i Europa uden at gemme dine data.",
      },
    ],
  },
  team: {
    id: "teams",
    label: "Til teams",
    status: "Kommer snart",
    title: "Alle er med",
    body: "Eigin gør det sikkert at forbinde jeres agenter. Del kontekst i teamet, og find det, du skal bruge, uden at spørge rundt.",
    bullets: [
      "Find svar i fælles dokumenter og ressourcer",
      "Gør fælles noter til klare næste skridt",
      "Se beslægtede opgaver og afhængigheder",
      "Fælles værktøjer og guides, sat op én gang",
    ],
    placeholder: "Diagram over teamagenter",
    diagram: {
      context: ["Fælles", "kontekst"],
      description: "Fem individuelle agenter bidrager til og bruger teamets fælles viden.",
      pause: "Sæt diagram på pause",
      play: "Afspil diagram",
    },
  },
  pricing: {
    title: "Din AI. På dine vilkår.",
    body: "Alle bør eje deres AI. Eigin er gratis til personlig brug, finansieret af valgfri cloud-AI og erhvervsaftaler.",
    action: "Læs mere",
    actionHref: "#faq",
    plans: [
      {
        name: "Personlig",
        href: "#get",
        price: "Gratis",
        detail: "Hele appen og de nødvendige tjenester, der understøtter den.",
      },
      {
        name: "Cloud-AI",
        href: "#faq",
        price: "Betal pr. brug",
        detail: "Vores indkøbspris + 10 %. Eller brug din egen gratis.",
      },
      {
        name: "Team",
        href: "mailto:hello@eigin.ai?subject=Eigin%20til%20teams%20early%20access",
        price: "75 € pr. måned",
        detail: "Op til 25 personer. Én fast pris, intet bøvl med pris pr. bruger.",
        status: "Kommer snart",
      },
      {
        name: "Organisation",
        href: "mailto:hello@eigin.ai?subject=Eigin%20til%20organisationer",
        price: "Tag en snak",
        detail: "Større teams, self-hosting og kommercielle licenser.",
      },
    ],
  },
  open: {
    title: "Åben teknologi fra Danmark",
    body: "Eigin er open source og europæisk ejet. Læs koden, følg vores roadmap, og vær med til at forme det næste.",
    links: [
      {
        label: "Læs koden",
        detail: "Se, hvordan Eigin er bygget.",
        href: "https://code.eigin.ai/dev/eigin",
      },
      {
        label: "Se vores roadmap",
        detail: "Se, hvad vi arbejder på.",
        href: "/da/roadmap/",
      },
      {
        label: "Vær med i samtalen",
        detail: "Tal med os og andre på Matrix.",
        href: "https://chat.eigin.ai",
      },
    ],
  },
  faq: {
    title: "Spørgsmål",
    items: [
      {
        question: "Hvad koster det?",
        answer: `<p>Appen er gratis. Vores cloud-AI betales efter forbrug. Ud fra vores eget forbrug koster en typisk måned 10–20 €, alt efter hvor meget du bruger den.</p><p>En lokal model eller en udbyder, du allerede betaler for, koster ikke ekstra.</p>`,
      },
      {
        question: "Hvordan vælger jeg en AI-model?",
        answer: `<p>Det behøver du ikke. Eigin vælger automatisk en egnet model hos din udbyder, så du ikke behøver vide, hvilken du skal vælge.</p><p>Start med vores cloud-AI. Den er hurtig, dygtig og europæisk. Betaler du allerede for ChatGPT Plus eller en anden udbyder, kan du også tilslutte den.</p><p>Du kan også hente en lokal model i appen og chatte offline.</p>`,
      },
      {
        question: "Bliver alt på min enhed?",
        answer: `<p>Dine chats, minder og indstillinger gemmes på din enhed. Cloud-AI kan modtage din samtale, relevante minder og tilladte data fra tilsluttede tjenester.</p><p>Vores cloud-AI kører i Europa og gemmer ikke dine prompts eller svar.</p><p>Med en lokal model bliver samtalen på din enhed. Værktøjer med særskilt tilladelse kan stadig kontakte tilsluttede tjenester. <a href="/da/trust/">Sådan virker det</a></p>`,
      },
      {
        question: "Hvordan virker credits?",
        answer: `<p>Du betaler for vores cloud-AI med credits købt i appen.</p><p>Én credit dækker cirka én eurocent i AI-forbrug hos vores europæiske AI-udbydere. Når du køber credits, er App Store-gebyret og vores tillæg på 10 % til driften med i prisen.</p><p>Credits udløber ikke. De er knyttet direkte til dit køb, så du ikke behøver oprette en Eigin-konto.</p>`,
      },
      {
        question: "Hvad hvis jeg mister min enhed?",
        answer: `<p>Dine chats og minder kan gendannes fra din enheds backup ligesom andre appdata. Vi har ingen kopi, så vi kan ikke gendanne dem for dig.</p><p>Du kan gendanne credits fra købssiden i appen. Brug den samme Apple-konto, som du købte dem med.</p>`,
      },
      {
        question: "Kan jeg bruge den på Android eller nettet?",
        answer: `<p>Ikke endnu. Eigin findes til iOS i dag, og flere platforme er på vej.</p><p><a href="/da/roadmap/">Se vores roadmap</a>.</p>`,
      },
      {
        question: "Hvornår kommer Eigin til teams?",
        answer: `<p>Vi bygger det nu og leder efter teams, der vil prøve det tidligt.</p><p><a href="mailto:hello@eigin.ai?subject=Eigin%20til%20teams%20early%20access">Få tidlig adgang</a>.</p>`,
      },
    ],
    more: "Brug for hjælp med appen?",
    support: { label: "Gå til support", href: "/da/support/" },
  },
  get: {
    motion: { pause: "Sæt illustration på pause", play: "Afspil illustration" },
    title: "Ej din AI.\nFra nu af.",
    visual: "Eigin på en iPhone, der tilbyder at udfylde en blanket til en skoletur.",
    // The badge artwork is English, so its description is too.
    badge: "Download on the App Store",
    more: "Snart på flere platforme.",
    roadmap: { label: "Se vores roadmap", href: "/da/roadmap/" },
  },
};

export default content;
