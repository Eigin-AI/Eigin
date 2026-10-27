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
      "Vores steder til eftertanke plejede at være private. Nu tænker vi højt med AI, og hvert ord ender på en virksomheds server.",
      "Teknologi, der er så personlig, bør tilhøre dem, der bruger den. Derfor bygger vi Eigin.",
    ],
  },
  personal: {
    id: "personal",
    label: "Til dig",
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
        ask: "Hjælp mig med at planlægge dagen",
        tools: ["Tjekker din kalender…"],
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
        ask: "Skal jeg tage det nye job?",
        tools: ["Ser på det, der betyder noget for dig…"],
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
        label: "Find de rette ord til en svær samtale",
        ask: "Hjælp mig med at sige fra",
        tools: ["Tænker det igennem…"],
        reply:
          "Prøv: “Jeg vil gerne gøre det ordentligt, men tre projekter på én gang er for meget. Kan vi beslutte, hvilket der kommer først?”",
        options: [
          {
            label: "Hjælp mig med at øve det",
            description: "Prøv samtalen sammen",
            symbol: "illustration/person-1",
          },
        ],
      },
      {
        label: "Overlad rutinearbejdet",
        ask: "Hvilke mails skal jeg svare på?",
        tools: ["Tjekker din tilsluttede indbakke…"],
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
    body: "Eigin holder dine data hos dig og dens handlinger i dine hænder. Det er open source, så alle kan tjekke det.",
    action: { label: "Sådan virker det", href: "/da/trust/" },
    promises: [
      {
        illustration: "illustration/tree",
        title: "Den bor hos dig",
        body: "Dine data gemmes på din egen enhed. Med en lokal model virker den endda offline.",
      },
      {
        illustration: "illustration/person-1",
        title: "Du har det sidste ord",
        body: "Den har et fast sæt værktøjer og spørger dig, før den sender eller ændrer noget.",
      },
      {
        illustration: "illustration/bird",
        title: "Den følger med dig",
        body: "Brug de nyeste modeller eller én på din telefon. Skift når som helst, din agent er den samme.",
      },
      {
        illustration: "illustration/butterfly",
        title: "Den tjener kun dig",
        body: "Ingen reklamer, ingen sporing. Vores AI-modeller kører i Europa og gemmer intet.",
      },
    ],
  },
  team: {
    id: "teams",
    label: "Til teams",
    status: "Kommer snart",
    title: "Ingen står uden for",
    body: "Eigin gør det sikkert at forbinde jeres private agenter. Del kontekst som team, og find det, du har brug for, uden at spørge rundt.",
    bullets: [
      "Find svar i fælles dokumenter og ressourcer",
      "Gør fælles noter til klare næste skridt",
      "Se sammenhænge og afhængigheder",
      "Fælles værktøjer og guides, sat op én gang",
    ],
    placeholder: "Diagram over teamagenter",
  },
  pricing: {
    title: "Gratis for dig, fair for dit team",
    body: "Vi mener, at alle bør eje deres AI, så Eigin er gratis til personlig brug. Vi lever af privat cloud-AI og erhvervsaftaler, der er værd at betale for.",
    action: "Spørg om priser",
    plans: [
      {
        name: "Personlig",
        price: "Gratis",
        detail: "Hele appen og de vigtigste tjenester, der understøtter den.",
      },
      {
        name: "Cloud-AI",
        price: "Betal pr. brug",
        detail: "Du betaler vores pris plus 10 %. Eller brug din egen gratis.",
      },
      {
        name: "Team",
        price: "50 € pr. måned",
        detail: "Op til 25 personer. Én fast pris, intet bøvl med pris pr. bruger.",
        status: "Kommer snart",
      },
      {
        name: "Organisation",
        price: "Tag en snak",
        detail: "Større teams, self-hosting og kommercielle licenser.",
      },
    ],
  },
  open: {
    title: "Åben teknologi, bygget i Europa",
    body: "Eigin er open source og europæisk ejet. Læs koden, følg vores roadmap, og vær med til at forme det næste.",
    links: [
      {
        label: "Læs koden",
        detail: "Se, hvordan den er bygget.",
        href: "https://code.eigin.ai/dev/eigin",
      },
      {
        label: "Se vores roadmap",
        detail: "Se, hvad der er aktivt, planlagt og lanceret.",
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
        answer: `<p>Appen er gratis. Cloud-AI betaler du for pr. brug, så det afhænger af, hvor meget du bruger den. En typisk Eigin-bruger betaler 10–20 € om måneden, mindre end et ChatGPT Plus-abonnement.</p><p>En lokal model, eller en udbyder du allerede betaler for, koster ikke ekstra.</p>`,
      },
      {
        question: "Hvilken model skal jeg vælge?",
        answer: `<p>Start med vores cloud-AI. Den er hurtig, dygtig og kører i Europa.</p><p>Vælg den lokale model for lokal inferens uden internet. Værktøjer, der kontakter forbundne tjenester, kræver stadig netværk og din tilladelse. Den er langsommere og kræver en iPhone 15 eller nyere. Betaler du allerede for ChatGPT Plus eller en anden udbyder? Så forbind den i stedet.</p>`,
      },
      {
        question: "Bliver alt på min telefon?",
        answer: `<p>Dine samtaler, minder og indstillinger gemmes på din telefon. Cloud-forespørgsler kan indeholde din samtale, relevante minder og tilladte data fra forbundne tjenester. Vores cloud-AI kører i Europa og gemmer intet.</p><p>Med en lokal model bliver inferens på din telefon. Værktøjer med særskilt tilladelse kan stadig kontakte forbundne tjenester. <a href="/da/trust/">Sådan virker det</a></p>`,
      },
      {
        question: "Hvordan virker credits?",
        answer: `<p>Du betaler for vores cloud-AI med credits, som du køber i appen. Credits udløber aldrig. De er knyttet til dit køb, ikke til en konto, så du skal ikke oprette dig.</p><p>På en ny telefon trykker du på <strong>Gendan credits</strong> for at få dem tilbage.</p>`,
      },
      {
        question: "Hvad hvis jeg mister min telefon?",
        answer: `<p>Dine samtaler og minder er med i telefonens almindelige backup, ligesom dine andre apps. Vi ser dem aldrig, så vi kan ikke gendanne dem for dig.</p>`,
      },
      {
        question: "Kan jeg bruge den på Android eller nettet?",
        answer: `<p>Ikke endnu. Eigin findes til iPhone i dag, og flere platforme er på vej. <a href="/da/roadmap/">Se vores roadmap</a></p>`,
      },
      {
        question: "Hvornår kommer Eigin til teams?",
        answer: `<p>Vi bygger det nu og leder efter teams, der vil prøve det tidligt. <a href="mailto:hello@eigin.ai?subject=Eigin%20til%20teams%20early%20access">Prøv det tidligt</a></p>`,
      },
    ],
    more: "Brug for hjælp med appen?",
    support: { label: "Gå til support", href: "/da/support/" },
  },
  get: {
    motion: { pause: "Sæt illustration på pause", play: "Afspil illustration" },
    title: "Gør AI til din egen.\nFra i dag.",
    visual: "Eigin på en iPhone, der tilbyder at udfylde en blanket til en skoletur.",
    // The badge artwork is English, so its description is too.
    badge: "Download on the App Store",
    more: "Snart på flere platforme.",
    roadmap: { label: "Se vores roadmap", href: "/da/roadmap/" },
  },
};

export default content;
