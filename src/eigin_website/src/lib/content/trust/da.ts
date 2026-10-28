import type { TrustContent } from "./types";
import daniel from "../../assets/team/daniel-rothmann.jpg";
import therkel from "../../assets/team/therkel-sand-therkelsen.jpg";

const docs = "https://code.eigin.ai/dev/eigin/-/blob/main/docs/src";

const content: TrustContent = {
  title: "Tillid — Eigin",
  description:
    "Sådan er Eigin bygget til at beskytte dit privatliv og give dig kontrol over dine data og din AI.",
  heading: "Hvorfor stole på Eigin?",
  introduction:
    "Se, hvordan Eigin er bygget med privatliv og sikkerhed i centrum, så du trygt kan bruge personlig AI.",
  more: "Sådan virker det",
  claims: [
    {
      id: "data",
      diagram: "device",
      title: "Dine data",
      summary: "Dine samtaler og din agents data gemmes på din enhed, ikke vores.",
      details: [
        "Dine data gemmes på din enhed. Cloud-AI kan modtage minder og data fra tilsluttede tjenester.",
        "Din stemme behandles på din enhed og forlader den ikke.",
        "Tilsluttede konti tilgås fra din enhed, ikke gennem os.",
      ],
    },
    {
      id: "models",
      diagram: "models",
      title: "AI-modeller",
      summary: "Dine beskeder går kun til den AI-model, du vælger, og kun når du har sagt ja.",
      details: [
        "Eigin spørger, før noget sendes til en cloud-model første gang.",
        "Vores cloud-AI gemmer ikke dine chats og kræver ingen konto.",
        "Lokale modeller kører på din enhed. Værktøjer med særskilt tilladelse kan stadig kontakte tilsluttede tjenester.",
      ],
    },
    {
      id: "actions",
      diagram: "actions",
      title: "Hvad den kan",
      summary:
        "Den kan kun bruge de værktøjer, du giver den, og spørger, før den ændrer eller sender noget.",
      details: [
        "Den har ingen “virtuel computer”, så den kan ikke skrive eller køre sin egen kode.",
        "Hvert værktøj har tilladelser, som du styrer.",
        "Som standard spørger Eigin før handlinger med konsekvenser.",
      ],
    },
    {
      id: "sync",
      diagram: "sync",
      title: "Synkronisering",
      status: "Kommer snart",
      summary: "Når Eigin synkroniserer, kan kun du og dem, du deler med, læse dataene.",
      details: [
        "Synkronisering mellem dine enheder og dit team er end-to-end-krypteret.",
        "Kun du og de personer, du deler med, har nøglerne.",
        "Eigin Relay kan sende dine data videre, men kan ikke læse dem.",
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
        "Vi sælger valgfrie tjenester og erhvervsaftaler, ikke data.",
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
        "Eigin fungerer uafhængigt af vores firma. Du kan bruge en lokal model eller tilslutte din egen udbyder.",
        "Vil du have fuld kontrol, kan du selv hoste vores cloud-tjenester.",
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
        "Din agent kører på din enhed. Den kan bruge en lokal model på enheden eller Eigin Relay eller din egen udbyder i skyen. Intet sendes ud, før du siger ja.",
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
      relayNote: "Kan ikke åbne den.",
    },
    money: {
      description:
        "Eigin finansieres af dem, der bruger vores cloud-AI efter forbrug, og af teams til én fast pris. Intet går til annoncører, trackere eller datamæglere.",
      cloud: "cloud-AI",
      cloudNote: "Betal pr. brug.",
      team: "teamplaner",
      teamNote: "Én fast pris.",
      refused: ["Annoncører", "Trackere", "Datamæglere"],
    },
    open: {
      description:
        "En lukket app er en sort boks. Eigin er open source under AGPL: Alle kan læse, hvordan den gemmer, synkroniserer og deler dine data.",
      others: "andre apps",
      trustUs: "“Stol på os.”",
      eigin: "Eigin, open source",
      items: [
        "Hvordan den gemmer data",
        "Hvordan den synkroniserer",
        "Hvad den må gøre",
        "Hvor den sender data hen",
        "Alt det andet",
      ],
    },
  },
  limits: {
    title: "Begrænsninger",
    introduction: "Intet system beskytter mod alt. Her kan du se, hvor grænserne går.",
    items: [
      {
        title: "Cloud-modeller kan læse din aktuelle samtale",
        body: "For at svare dig skal en cloud-model læse det, du sender. Vores cloud-AI-modeller gemmer ikke dine samtaler, men hos din egen udbyder gælder dens vilkår.",
      },
      {
        title: "Din enhed er pengeskabet",
        body: "Dine data er lige så sikre som din enhed. Hvis nogen kan åbne din enhed, kan de læse dine chats.",
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
        body: "Enhver AI-model kan tage fejl og lyde sikker. Tjek svaret, før du stoler på det.",
      },
    ],
  },
  responsible: {
    title: "Menneskerne",
    body: "Eigin er lavet af Eigin ApS, et dansk team med base i København og Aarhus. Du ved, hvem vi er, og du kan altid få fat i os.",
    people: [
      { name: "Daniel Rothmann", role: "Medstifter og CTO", photo: daniel },
      { name: "Therkel Sand Therkelsen", role: "Medstifter og CEO", photo: therkel },
    ],
  },
  transparency: {
    title: "Gennemsigtighed",
    groups: [
      {
        title: "Kode",
        links: [
          { label: "Kildekode", href: "https://code.eigin.ai/dev/eigin" },
          { label: "Teknisk dokumentation", href: `${docs}/privacy.md` },
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
