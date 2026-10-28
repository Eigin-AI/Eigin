import type { SiteContent } from "./types";

const content: SiteContent = {
  skip: "Skip to content",
  homeLabel: "Eigin home",
  mainNavigation: "Main navigation",
  languageNavigation: "Language",
  menu: "Menu",
  action: "Get Eigin",
  navigation: [
    {
      label: "For you",
      href: "#personal",
    },
    {
      label: "For teams",
      href: "#teams",
    },
    {
      label: "Pricing",
      href: "#pricing",
    },
    {
      label: "Trust",
      href: "/en/trust/",
    },
    {
      label: "Roadmap",
      href: "/en/roadmap/",
    },
  ],
  footer: {
    tagline: "AI so personal, it has to be yours.",
    comingSoon: "Coming soon",
    copyright: "© Eigin ApS 2026",
    socialNavigation: "Social links",
    groups: [
      {
        title: "Eigin",
        links: [
          { label: "Get Eigin", href: "#get" },
          { label: "For you", href: "#personal" },
          { label: "For teams", href: "#teams" },
          { label: "Pricing", href: "#pricing" },
        ],
      },
      {
        title: "Learn",
        links: [
          {
            label: "Trust",
            href: "/en/trust/",
          },
          {
            label: "Roadmap",
            href: "/en/roadmap/",
          },
          {
            label: "Questions",
            href: "#faq",
          },
          {
            label: "Source code",
            href: "https://code.eigin.ai/dev/eigin",
          },
        ],
      },
      {
        title: "Company",
        links: [
          {
            label: "Contact",
            href: "/en/contact/",
          },
          {
            label: "Support",
            href: "/en/support/",
          },
          {
            label: "Privacy",
            href: "/en/privacy/",
          },
          {
            label: "Terms",
            href: "/en/terms/",
          },
        ],
      },
    ],
  },
};

export default content;
