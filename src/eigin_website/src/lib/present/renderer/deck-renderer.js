/** Installs deck composition in the isolated iframe after the Reveal bundles load. */
(function () {
  const globals = /** @type {import("./deck-types").DeckGlobals} */ (
    /** @type {unknown} */ (window)
  );
  const { Reveal, RevealMarkdown, RevealHighlight, RevealZoom } = globals;
  let initialized = false;

  /** @param {string} name */
  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  /** Resolve deck media references before Markdown parsing.
   * @param {string} md
   * @param {import("./deck-types").DeckOptions["resolve"]} [resolve]
   */
  function rewriteMedia(md, resolve) {
    if (!resolve) return md;
    md = md.replace(/(!\[[^\]]*\]\()([^)\s]+)(\s*(?:"[^"]*")?\))/g, function (m, pre, src, post) {
      const r = resolve(src);
      return r ? pre + r + post : m;
    });
    md = md.replace(
      /(<img\b[^>]*?\s(?:data-)?src=["'])([^"']+)(["'])/gi,
      function (m, pre, src, post) {
        const r = resolve(src);
        return r ? pre + r + post : m;
      },
    );
    md = md.replace(/(data-background-image=["'])([^"']+)(["'])/gi, function (m, pre, src, post) {
      const r = resolve(src);
      return r ? pre + r + post : m;
    });
    return md;
  }

  /** @param {string} md */
  function buildSection(md) {
    const slides = document.querySelector(".reveal .slides");
    if (!slides) throw new Error("Slide container is missing.");
    slides.innerHTML = "";
    const section = document.createElement("section");
    section.setAttribute("data-markdown", "");
    section.setAttribute("data-separator", "^\\r?\\n---\\r?\\n");
    section.setAttribute("data-separator-vertical", "^\\r?\\n----\\r?\\n");
    section.setAttribute("data-separator-notes", "^Note:");
    const ta = document.createElement("textarea");
    ta.setAttribute("data-template", "");
    // The markdown plugin reads textContent (not .value), so set that.
    ta.textContent = md;
    section.appendChild(ta);
    slides.appendChild(section);
  }

  /** @param {Element} section */
  function wrapFrame(section) {
    if (section.querySelector(":scope > .slide-frame")) return;
    const frame = document.createElement("div");
    frame.className = "slide-frame";
    while (section.firstChild) frame.appendChild(section.firstChild);
    section.appendChild(frame);
  }

  function buildFrames() {
    document.querySelectorAll(".reveal .slides > section").forEach(function (sec) {
      const vertical = sec.querySelectorAll(":scope > section");
      if (vertical.length) vertical.forEach(wrapFrame);
      else wrapFrame(sec);
    });
    composeCovers();
    markWordStats();
  }

  const COVER_PANEL_SEL = "h1, h2, .subhead, .lede, .bleed";

  function composeCovers() {
    document.querySelectorAll(".reveal section.layout-cover").forEach(function (sec) {
      const frame = sec.querySelector(":scope > .slide-frame");
      if (!frame || frame.querySelector(":scope > .cover-panel")) return;

      const panel = document.createElement("div");
      panel.className = "cover-panel";
      const meta = document.createElement("div");
      meta.className = "cover-meta";

      const art = sec.getAttribute("data-art");
      if (art) {
        const bleed = document.createElement("div");
        bleed.className = "bleed ink";
        bleed.setAttribute(
          "style",
          "--size:85%; left:-17%; top:55%; margin-top:calc(var(--size) / -2); " +
            "--shape:url(" +
            (globals.EiginArtwork[art] || "") +
            ")",
        );
        panel.appendChild(bleed);
      }

      while (frame.firstChild) {
        const node = frame.firstChild;
        const toPanel = node instanceof Element && node.matches(COVER_PANEL_SEL);
        (toPanel ? panel : meta).appendChild(node);
      }

      frame.appendChild(panel);
      frame.appendChild(meta);
    });
  }

  function markWordStats() {
    /** @param {Element} el */
    const isWord = function (el) {
      const t = (el.textContent || "").trim();
      return t.length > 5 || /\s/.test(t);
    };
    document.querySelectorAll(".reveal .stat-row").forEach(function (row) {
      const nums = row.querySelectorAll(".stat-number");
      if (!Array.from(nums).some(isWord)) return;
      nums.forEach(function (el) {
        el.classList.add("is-word");
      });
    });
    // A stat standing on its own, outside a row, decides for itself.
    document.querySelectorAll(".reveal .stat-number").forEach(function (el) {
      if (!el.closest(".stat-row") && isWord(el)) el.classList.add("is-word");
    });
  }

  function applyThemeBackgrounds() {
    const dark = cssVar("--eigin-dark-bg");
    const light = cssVar("--eigin-light-bg");
    Reveal.getSlides().forEach(function (section) {
      const bg = section.slideBackgroundElement;
      if (!bg) return;
      if (
        section.getAttribute("data-background-color") ||
        section.getAttribute("data-background-image") ||
        section.getAttribute("data-background-gradient")
      )
        return;
      bg.style.backgroundColor = section.classList.contains("theme-light") ? light : dark;
    });
  }

  /** @param {Record<string, unknown>} [overrides] */
  function revealConfig(overrides) {
    return Object.assign(
      {
        hash: false,
        controls: true,
        progress: true,
        center: false,
        transition: "none",
        backgroundTransition: "none",
        width: 1280,
        height: 720,
        margin: 0,
        pdfPageHeightOffset: 0,
        slideNumber: false,
        plugins: [
          RevealMarkdown,
          RevealHighlight,
          RevealZoom,
          { id: "eigin-frames", init: buildFrames },
        ],
      },
      overrides || {},
    );
  }

  /** Initialize Reveal with the deck and Eigin slide layouts.
   * @param {string} md
   * @param {import("./deck-types").DeckOptions} [opts]
   */
  function render(md, opts) {
    opts = opts || {};
    md = rewriteMedia(md, opts.resolve);
    buildSection(md);
    return Reveal.initialize(revealConfig(opts.reveal)).then(function () {
      initialized = true;
      buildFrames();
      applyThemeBackgrounds();
      if (opts.onReady) opts.onReady();
    });
  }

  /** Replace deck content while retaining the current slide position.
   * @param {string} md
   * @param {import("./deck-types").DeckOptions} [opts]
   */
  function reload(md, opts) {
    opts = opts || {};
    if (!initialized) return render(md, opts);
    md = rewriteMedia(md, opts.resolve);
    const idx = Reveal.getIndices();
    buildSection(md);
    return Reveal.getPlugin("markdown")
      .init(Reveal)
      .then(function () {
        const hl = Reveal.getPlugin("highlight");
        if (hl && hl.init) hl.init(Reveal);
        buildFrames();
        Reveal.sync();
        applyThemeBackgrounds();
        Reveal.slide(idx.h || 0, idx.v || 0);
      });
  }

  globals.EiginPresent = {
    render: render,
    reload: reload,
    rewriteMedia: rewriteMedia,
    applyThemeBackgrounds: applyThemeBackgrounds,
  };
})();
