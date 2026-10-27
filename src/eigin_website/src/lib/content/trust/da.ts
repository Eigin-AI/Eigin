import type { TrustContent } from "./types";
import daniel from "../../assets/team/daniel-rothmann.jpg";
import therkel from "../../assets/team/therkel-sand-therkelsen.jpg";

const docs = "https://code.eigin.ai/dev/eigin/-/blob/main/docs/src";

const content: TrustContent = {
  title: "Tillid — Eigin",
  description:
    "Sådan holder Eigin personlig AI privat og sikker, i et klart sprog og med beviser, du kan tjekke.",
  heading: "Hvorfor stole på Eigin?",
  introduction:
    "Her kan du se, hvordan Eigin håndterer dine data, hvad den kan, og hvor du selv kan tjekke det.",
  more: "Sådan virker det",
  claims: [
    {
      id: "data",
      diagram: "device",
      title: "Dine data",
      summary: "Dine samtaler og din agents hukommelse gemmes på din enhed, ikke hos os.",
      details: [
        "Chats, hukommelse, mål og indstillinger gemmes på din enhed. Cloud-forespørgsler kan indeholde relevante minder og data fra forbundne tjenester.",
        "Din stemme behandles på din enhed og forlader den aldrig.",
        "Forbundne konti tilgås direkte fra din enhed, ikke gennem os.",
      ],
    },
    {
      id: "models",
      diagram: "models",
      title: "AI-modeller",
      summary: "Dine beskeder går kun til den AI-model, du vælger, og kun når du har sagt ja.",
      details: [
        "Eigin spørger, før noget sendes til en cloud-model første gang.",
        "Vores cloud-AI gemmer intet og kræver ingen konto.",
        "Lokal inferens kører på din enhed. Værktøjer med særskilt tilladelse kan stadig kontakte forbundne tjenester.",
      ],
    },
    {
      id: "actions",
      diagram: "actions",
      title: "Hvad den kan",
      summary:
        "Den kan kun bruge de værktøjer, du giver den, og spørger, før den ændrer eller sender noget.",
      details: [
        "Den har ingen computer selv og kan ikke skrive eller køre sin egen kode.",
        "Hvert værktøj har tilladelser, som du styrer.",
        "Alt risikabelt spørger dig først, som standard.",
      ],
    },
    {
      id: "sync",
      diagram: "sync",
      title: "Sync",
      status: "Kommer snart",
      summary: "Når Eigin synkroniserer, kan kun du og dem, du deler med, læse det.",
      details: [
        "Sync mellem dine enheder og dit team er end-to-end-krypteret.",
        "Kun du og de personer, du deler med, har nøglerne.",
        "Vi sender dine data videre, men vi kan ikke læse dem.",
      ],
    },
    {
      id: "money",
      diagram: "money",
      title: "Sådan tjener vi penge",
      summary: "Vi lever af privat cloud-AI og erhvervsaftaler, ikke af dine data.",
      details: [
        "Der er ingen reklamer eller sporing i appen.",
        "Vores cloud-tjeneste behøver ikke vide, hvem du er.",
        "Vi sælger valgfrie tjenester og erhvervsabonnementer, ikke data.",
      ],
    },
    {
      id: "open",
      diagram: "open",
      title: "Open source",
      summary:
        "Eigin er open source, så du kan se, hvordan den håndterer dine data, og hvad den må.",
      details: [
        "Koden er offentlig under AGPL-licensen.",
        "Uden os virker den stadig med en lokal model eller din egen nøgle.",
        "Du kan også selv hoste vores cloud-tjenester.",
      ],
    },
  ],
  diagrams: {
    motion: { pause: "Sæt illustration på pause", play: "Afspil illustration" },
    device: {
      description:
        "Din agent gemmer chats, hukommelse, mål og noter på din enhed. Cloud-forespørgsler kan indeholde din samtale, relevante minder og tilladte data fra forbundne tjenester. Lokal inferens bliver på enheden; netværksværktøjer med særskilt tilladelse kan stadig kontakte forbundne tjenester.",
      device: "din enhed",
      memory: "Minder",
      goals: "Mål",
      voice: "Stemme",
      notes: "Noter",
      conversation: "Kontekst",
      local: "lokal model",
      cloud: "cloud-model",
    },
    models: {
      description:
        "Din agent kører på din enhed. Den kan bruge en lokal model på enheden, eller uden for den Eigin Relay eller din egen udbyder. Intet sendes ud, før du siger ja.",
      device: "din enhed",
      local: "lokal model",
      relay: "eigin relay",
      own: "egen udbyder",
      ask: "spørg",
    },
    actions: {
      description:
        "Billedet skifter mellem to scener. Først en anden agent, vist som en cirkel i en sandkasse: dens muligheder vokser i en låst maskine, indtil én finder det eneste hul og slipper ud. Så din Eigin-agent, uden kasse og med faste handlinger: den kan tjekke din kalender og læse en note, en e-mail kræver dit ja, og kode kan den ikke køre.",
      others: "andre agenter",
      calendar: "Tjek din kalender",
      note: "Læs en note",
      email: "Send en e-mail",
      code: "Kør kode",
      agent: "din agent",
      ask: "spørg",
    },
    sync: {
      description:
        "En note på din enhed sendes låst gennem Eigin Relay til dit team. Kun din enhed og dit team har nøgler; Eigin Relay kan ikke åbne den.",
      device: "din enhed",
      team: "dit team",
      message: ["Planer for", "fredag?"],
      relay: "Eigin Relay",
      relayNote: "Kan ikke se den.",
    },
    money: {
      description:
        "Eigin betales af folk, der vælger vores cloud-AI efter forbrug, og af teams til én fast pris. Intet går til annoncører, trackere eller datamæglere.",
      cloud: "cloud-ai",
      cloudNote: "Betal pr. brug.",
      team: "teamplaner",
      teamNote: "Én fast pris.",
      refused: ["Annoncører", "Trackere", "Datamæglere"],
    },
    open: {
      description:
        "En lukket app er en sort boks. Eigin er open source under AGPL: hvordan den gemmer, synkroniserer og deler dine data, kan alle læse.",
      others: "andre apps",
      trustUs: "“Stol på os.”",
      eigin: "Eigin, open source",
      items: [
        "Hvor den gemmer dine data",
        "Hvordan sync virker",
        "Hvad den må gøre",
        "Hvor den sender data hen",
        "Alt det andet",
      ],
    },
  },
  limits: {
    // A no-break space keeps "ikke kan" together when the title wraps.
    title: "Hvad Eigin ikke\u00a0kan",
    introduction: "Intet system beskytter mod alt. Her kan du se, hvor grænserne går.",
    items: [
      {
        title: "Cloud-modeller læser din aktuelle samtale",
        body: "For at svare dig skal en cloud-model læse det, du sender. Vores cloud-AI-modeller gemmer aldrig dine samtaler, men hos din egen udbyder gælder dens vilkår.",
      },
      {
        title: "Din enhed er pengeskabet",
        body: "Dine data er lige så sikre som din enhed. Alle, der kan åbne din enhed, kan læse dine chats.",
      },
      {
        title: "Indhold kan prøve at narre agenten",
        body: "Websider og værktøjer kan gemme instruktioner til agenten. Som standard spørger Eigin dig, før den læser eksterne kilder, og før enhver handling med konsekvenser.",
      },
      {
        title: "Vi ser noget trafik",
        body: "Vores cloud-tjenester ser kortvarigt din IP-adresse for at stoppe misbrug. De behøver ikke dit navn, din e-mail eller et bruger-ID.",
      },
      {
        title: "AI kan tage fejl",
        body: "Enhver model kan tage fejl og lyde sikker. Tjek svaret, før du stoler på det.",
      },
    ],
  },
  responsible: {
    title: "Hvem har ansvaret",
    body: "Eigin er lavet af Eigin ApS, et lille dansk team i København og Aarhus. Du ved, hvem vi er, og du kan altid få fat i os.",
    people: [
      { name: "Daniel Rothmann", role: "Medstifter og CTO", photo: daniel },
      { name: "Therkel Sand Therkelsen", role: "Medstifter og CEO", photo: therkel },
    ],
  },
  transparency: {
    title: "Kortene på bordet",
    groups: [
      {
        title: "Kode",
        links: [
          { label: "Kildekode", href: "https://code.eigin.ai/dev/eigin" },
          { label: "Dokumentation", href: `${docs}/privacy.md` },
          {
            label: "Sikkerhedspolitik",
            href: "https://code.eigin.ai/dev/eigin/-/blob/main/SECURITY.md",
          },
        ],
      },
      {
        title: "Compliance",
        links: [
          { label: "CASA", href: "https://docs.eigin.ai/compliance/casa.html" },
          { label: "GDPR", href: "https://docs.eigin.ai/compliance/gdpr.html" },
          { label: "AI Act", href: "https://docs.eigin.ai/compliance/ai-act.html" },
        ],
      },
      {
        title: "Politikker",
        links: [
          { label: "Privatlivspolitik", href: "/da/privacy/" },
          { label: "Servicevilkår", href: "/da/terms/" },
        ],
      },
      {
        title: "Tal med os",
        links: [
          { label: "Mail os", href: "mailto:hello@eigin.ai" },
          { label: "Chat med os", href: "https://chat.eigin.ai" },
        ],
      },
    ],
  },
};

export default content;
