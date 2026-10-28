import type { SiteContent } from "./types";

const content: SiteContent = {
  skip: "Gå til indhold",
  homeLabel: "Eigin forside",
  mainNavigation: "Hovednavigation",
  languageNavigation: "Sprog",
  menu: "Menu",
  action: "Hent Eigin",
  navigation: [
    {
      label: "Til dig",
      href: "#personal",
    },
    {
      label: "Til teams",
      href: "#teams",
    },
    {
      label: "Priser",
      href: "#pricing",
    },
    {
      label: "Tillid",
      href: "/da/trust/",
    },
    {
      label: "Roadmap",
      href: "/da/roadmap/",
    },
  ],
  footer: {
    tagline: "AI så personlig, at den skal være din.",
    comingSoon: "Kommer snart",
    copyright: "© Eigin ApS 2026",
    socialNavigation: "Sociale links",
    groups: [
      {
        title: "Eigin",
        links: [
          { label: "Hent Eigin", href: "#get" },
          { label: "Til dig", href: "#personal" },
          { label: "Til teams", href: "#teams" },
          { label: "Priser", href: "#pricing" },
        ],
      },
      {
        title: "Læs mere",
        links: [
          {
            label: "Tillid",
            href: "/da/trust/",
          },
          {
            label: "Roadmap",
            href: "/da/roadmap/",
          },
          {
            label: "Spørgsmål",
            href: "#faq",
          },
          {
            label: "Kildekode",
            href: "https://code.eigin.ai/dev/eigin",
          },
        ],
      },
      {
        title: "Virksomhed",
        links: [
          {
            label: "Kontakt",
            href: "/da/contact/",
          },
          {
            label: "Support",
            href: "/da/support/",
          },
          {
            label: "Privatliv",
            href: "/da/privacy/",
          },
          {
            label: "Vilkår",
            href: "/da/terms/",
          },
        ],
      },
    ],
  },
};

export default content;
