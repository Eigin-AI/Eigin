export type SiteLink = { label: string; href?: string };

export type SiteContent = {
  skip: string;
  homeLabel: string;
  mainNavigation: string;
  languageNavigation: string;
  menu: string;
  action: string;
  navigation: (SiteLink & { href: string })[];
  footer: {
    tagline: string;
    groups: { title: string; links: SiteLink[] }[];
    comingSoon: string;
    copyright: string;
    socialNavigation: string;
  };
};
