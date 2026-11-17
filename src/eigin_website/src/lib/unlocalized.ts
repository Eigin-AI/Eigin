/** Published page sections that support a language-free entry URL. */
export const unlocalizedSections = [
  "news",
  "roadmap",
  "trust",
  "contact",
  "support",
  "privacy",
  "terms",
] as const;

/** Whether a path segment names a localized website section. */
export function isUnlocalizedSection(value: string): value is (typeof unlocalizedSections)[number] {
  return unlocalizedSections.some((section) => section === value);
}
