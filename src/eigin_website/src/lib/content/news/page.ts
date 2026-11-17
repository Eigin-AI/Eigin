import { error } from "@sveltejs/kit";
import { isLocale } from "#lib/locales.ts";
import { site } from "#lib/content/site/index.ts";
import { listPosts, findPost, loadPostComponent } from "./index";
import { newsCopy } from "./copy";

/** Resolve a news index or permanent article page for static rendering. */
export async function loadNews(lang: string, slug?: string) {
  if (!isLocale(lang)) error(404, "Page not found");
  const posts = listPosts(lang);
  const post = slug ? findPost(lang, slug) : posts[0];
  if (slug && !post) error(404, "Article not found");
  return {
    locale: lang,
    site: site[lang],
    copy: newsCopy[lang],
    posts,
    post,
    Article: post ? await loadPostComponent(lang, post.slug) : null,
    path: slug ? `news/${slug}/` : "news/",
    isArticle: Boolean(slug),
  };
}
