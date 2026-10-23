// Runs in an article's own page, in a script world of its own (see PageReader.swift). A tap on a word, or a phrase
// selected the usual way, goes to Swift; Swift decides what's marked and sends it back to be painted as CSS
// highlights, so the page's own elements are never changed.
//
// The page is read as blocks: the text between block elements (a paragraph, a heading, a list item), its spaces
// evened out the way a reading's lines are. Places in a block are counted in UTF-16 units, as NSRange counts them.
(() => {
  const post = (m) => window.webkit.messageHandlers.cinco.postMessage(m);
  const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "svg", "IFRAME", "TEXTAREA", "INPUT", "SELECT", "BUTTON"]);
  // Taps on these do what the page says.
  const controls = "button, input, select, textarea, label, summary, [role=button], [contenteditable]";

  // {el, text, parts: the text nodes (and <br>s) it's made of, at/off: each character's part and offset in it}
  let blocks = [];
  let byText = new Map();
  let where = new WeakMap(); // text node → {b, p}

  function index() {
    const info = new Map();
    // The block an element's text belongs to, and whether it's hidden.
    function of(el) {
      let r = info.get(el);
      if (r) return r;
      const up = el === document.body || !el.parentElement ? { block: el, hidden: false } : of(el.parentElement);
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") r = { block: up.block, hidden: true };
      else if (!style.display.startsWith("inline") && style.display !== "contents") r = { block: el, hidden: up.hidden };
      else r = up;
      info.set(el, r);
      return r;
    }

    const raw = new Map();
    let last = null;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.nodeType === 1 && skipped.has(n.tagName) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (n.nodeType === 1 && n.tagName !== "BR") continue;
      const i = of(n.parentElement);
      if (i.hidden) continue;
      let parts = raw.get(i.block);
      if (!parts) raw.set(i.block, (parts = []));
      // Text on both sides of a block inside this one is two words, not one.
      else if (last !== i.block) parts.push(null);
      parts.push(n);
      last = i.block;
    }

    blocks = [];
    byText = new Map();
    where = new WeakMap();
    for (const [el, parts] of raw) {
      let text = "", gap = false, prev = null;
      const at = [], off = [];
      parts.forEach((node, p) => {
        if (!node || node.nodeType !== 3) { gap = true; return; }
        const s = node.data;
        for (let k = 0; k < s.length; k++) {
          if (/\s/.test(s[k])) { gap = true; continue; }
          // A space stands where the character before it is, so every place is a real one, in order.
          if (gap && prev) {
            text += " ";
            at.push(prev[0]);
            off.push(prev[1]);
          }
          gap = false;
          text += s[k];
          at.push(p);
          off.push(k);
          prev = [p, k];
        }
      });
      if (!/\p{L}/u.test(text)) continue;
      const b = { el, text, parts, at, off };
      blocks.push(b);
      if (!byText.has(text)) byText.set(text, []);
      byText.get(text).push(b);
      parts.forEach((node, p) => { if (node && node.nodeType === 3) where.set(node, { b, p }); });
    }
  }

  // The first character of a block at or after offset k of part p.
  function place(b, p, k) {
    let lo = 0, hi = b.at.length;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (b.at[m] < p || (b.at[m] === p && b.off[m] < k)) lo = m + 1;
      else hi = m;
    }
    return lo;
  }

  // The first character of a block for which `test` holds, when it holds for every character after it too.
  function first(b, test) {
    let lo = 0, hi = b.at.length;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (test(m)) hi = m;
      else lo = m + 1;
    }
    return lo;
  }

  function range(b, s, e) {
    if (s < 0 || e > b.text.length || s >= e) return null;
    const r = document.createRange();
    r.setStart(b.parts[b.at[s]], b.off[s]);
    r.setEnd(b.parts[b.at[e - 1]], b.off[e - 1] + 1);
    return r;
  }

  // The block character under a point, when the point is on one (not between lines or words).
  function charAt(x, y) {
    const caret = document.caretRangeFromPoint(x, y);
    const node = caret && caret.startContainer;
    const w = node && node.nodeType === 3 && where.get(node);
    if (!w) return null;
    for (const k of [caret.startOffset, caret.startOffset - 1]) {
      if (k < 0 || k >= node.data.length || /\s/.test(node.data[k])) continue;
      const r = document.createRange();
      r.setStart(node, k);
      r.setEnd(node, k + 1);
      for (const q of r.getClientRects()) {
        if (x >= q.left - 3 && x <= q.right + 3 && y >= q.top - 3 && y <= q.bottom + 3) return { b: w.b, i: place(w.b, w.p, k) };
      }
    }
    return null;
  }

  // Painting

  const style = document.createElement("style");
  style.textContent = `
    ::highlight(cinco-mark) { background-color: #FFE08A; color: #2B2622; }
    ::highlight(cinco-known) { text-decoration: underline dotted #2A9D99 2px; text-underline-offset: 3px; }
  `;
  (document.head || document.documentElement).appendChild(style);
  const marked = new Highlight(), known = new Highlight();
  CSS.highlights.set("cinco-mark", marked);
  CSS.highlights.set("cinco-known", known);
  // From Swift: [text, marked stretches, known words], each stretch [start, end].
  let painted = [];

  function apply() {
    marked.clear();
    known.clear();
    for (const [text, m, k] of painted) {
      for (const b of byText.get(text) || []) {
        for (const [s, e] of m) { const r = range(b, s, e); if (r) marked.add(r); }
        for (const [s, e] of k) { const r = range(b, s, e); if (r) known.add(r); }
      }
    }
  }

  let sent = null;
  function refresh() {
    index();
    apply();
    const texts = [...byText.keys()];
    const key = texts.join("\n");
    if (key !== sent) {
      sent = key;
      post({ type: "blocks", texts });
    }
  }

  // Pages keep changing after they load (more text, ads): read again once they've been still a moment.
  let timer = null, since = 0;
  new MutationObserver(() => {
    const now = Date.now();
    if (!timer) since = now;
    clearTimeout(timer);
    timer = setTimeout(() => { timer = null; refresh(); }, now - since > 3000 ? 0 : 600);
  }).observe(document.body, { childList: true, subtree: true, characterData: true });

  // Taps

  let touch = null, scrolled = 0;
  addEventListener("scroll", () => { scrolled = Date.now(); }, { passive: true, capture: true });
  addEventListener("touchstart", (e) => {
    const t = e.touches[0];
    // A tap that stops a scroll, or clears a selection, isn't a tap on a word.
    touch = e.touches.length === 1 && Date.now() - scrolled > 150 && getSelection().isCollapsed
      ? { x: t.clientX, y: t.clientY, at: Date.now() } : null;
  }, { passive: true, capture: true });
  addEventListener("touchmove", (e) => {
    const t = e.touches[0];
    if (touch && Math.hypot(t.clientX - touch.x, t.clientY - touch.y) > 10) touch = null;
  }, { passive: true, capture: true });
  addEventListener("touchend", (e) => {
    const t = touch;
    touch = null;
    if (!t || Date.now() - t.at > 350 || (e.target.closest && e.target.closest(controls))) return;
    const hit = charAt(t.x, t.y);
    if (!hit) return;
    // A word in a link is a word to look up: the link isn't followed.
    e.preventDefault();
    e.stopPropagation();
    post({ type: "tap", text: hit.b.text, at: hit.i });
  }, { passive: false, capture: true });

  // A selection inside one block is a phrase to mark.
  let selTimer = null;
  document.addEventListener("selectionchange", () => {
    clearTimeout(selTimer);
    selTimer = setTimeout(selected, 250);
  });

  function selected() {
    const sel = getSelection();
    if (!sel.rangeCount || sel.isCollapsed) return post({ type: "select" });
    const r = sel.getRangeAt(0);
    const node = (b, m) => b.parts[b.at[m]];
    const hits = [];
    for (const b of blocks) {
      if (!r.intersectsNode(b.el)) continue;
      const s = first(b, (m) => r.comparePoint(node(b, m), b.off[m]) >= 0);
      const e = first(b, (m) => r.comparePoint(node(b, m), b.off[m] + 1) === 1);
      if (e > s && /\S/.test(b.text.slice(s, e))) hits.push({ b, s, e });
    }
    if (hits.length !== 1) return post({ type: "select" });
    const h = hits[0];
    post({ type: "select", text: h.b.text, start: h.s, end: h.e });
  }

  window.cinco = {
    paint(list) { painted = list; apply(); },
    clearSelection() { getSelection().removeAllRanges(); },
  };

  refresh();
  addEventListener("load", refresh);
})();
