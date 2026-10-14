// Runs in a loaded article page, after Readability.js (see ArticleReader.swift). Returns the article twice over, so
// Swift can choose: the text the page's own metadata gives (JSON-LD articleBody), and Readability's main text as
// paragraphs. Both are plain rules over the page, so the same page always gives the same text.

function cincoBlocks(root) {
  // The innermost text blocks, in order: a <p> inside a <blockquote> counts once.
  const sel = "p, h2, h3, h4, li, blockquote, pre";
  const out = [];
  root.querySelectorAll(sel).forEach((el) => {
    if (el.querySelector(sel)) return;
    const text = el.textContent.replace(/\s+/g, " ").trim();
    if (text) out.push(text);
  });
  return out;
}

function cincoMetadata() {
  for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
    let data;
    try { data = JSON.parse(s.textContent); } catch (e) { continue; }
    const stack = [data];
    while (stack.length) {
      const d = stack.pop();
      if (!d || typeof d !== "object") continue;
      if (typeof d.articleBody === "string" && d.articleBody.trim()) {
        let body = d.articleBody;
        // Some sites put HTML or entities in it: read it as a page, keeping its paragraphs.
        if (/[<&]/.test(body)) {
          const doc = new DOMParser().parseFromString(body, "text/html");
          const blocks = cincoBlocks(doc.body);
          body = blocks.length > 1 ? blocks.join("\n") : doc.body.textContent;
        }
        return { body: body, title: typeof d.headline === "string" ? d.headline : "" };
      }
      for (const v of Object.values(d)) if (v && typeof v === "object") stack.push(v);
    }
  }
  return { body: "", title: "" };
}

// Photos and their credits, boxes beside the story, and text only screen readers get ("Fuente de la imagen,",
// "Saltar Más leídas") aren't the article.
const clutter = 'figure, figcaption, aside, nav, [hidden], [aria-hidden="true"], [class*="visually-hidden"], [class*="sr-only"], [class*="screen-reader"]';

const meta = cincoMetadata();
let parsed = null;
try {
  const copy = document.cloneNode(true);
  copy.querySelectorAll(clutter).forEach((el) => el.remove());
  parsed = new Readability(copy).parse();
} catch (e) { parsed = null; }
let paragraphs = [];
if (parsed && parsed.content) {
  const doc = new DOMParser().parseFromString(parsed.content, "text/html");
  paragraphs = cincoBlocks(doc.body);
}
const og = document.querySelector('meta[property="og:title"]');
return {
  title: (parsed && parsed.title) || meta.title || (og && og.content) || document.title || "",
  site: (parsed && parsed.siteName) || location.hostname,
  paragraphs: paragraphs,
  metadata: meta.body,
  lang: document.documentElement.lang || "",
};
