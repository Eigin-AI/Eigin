import type { Component } from "svelte";
import type { Locale } from "#lib/locales.ts";
import { publishedPosts as posts } from "./published";

const components = import.meta.glob<{ default: Component }>("./posts/*/*.svx");

/** List published articles for one language, newest first. */
export function listPosts(locale: Locale) {
  return posts.filter((post) => post.locale === locale);
}

/** Find a published article by its permanent slug. */
export function findPost(locale: Locale, slug: string) {
  return posts.find((post) => post.locale === locale && post.slug === slug);
}

/** Load only the selected article’s compiled Markdown component. */
export async function loadPostComponent(locale: Locale, slug: string) {
  const path = Object.keys(components).find((path) => path.endsWith(`/${slug}/${locale}.svx`));
  if (!path) throw new Error(`Unknown news article: ${locale}/${slug}`);
  return (await components[path]()).default;
}
