// Sprache: gemerkte Wahl, sonst die Browsersprache (Deutsch fuer de-*, sonst Englisch). Kein Abruf bei Dritten.
(() => {
  const els = [...document.querySelectorAll("[data-en]")];
  els.forEach(e => { e.dataset.de = e.tagName === "TITLE" ? e.textContent : e.innerHTML; });
  const meta = document.querySelector('meta[name="description"]'); if (meta) meta.dataset.de = meta.content;
  let saved = null; try { saved = localStorage.getItem("rv-lang"); } catch (e) {}
  const auto = (navigator.languages || [navigator.language || "de"]).some(l => /^de\b/i.test(l)) ? "de" : "en";
  const set = (lang, keep) => {
    document.documentElement.lang = lang;
    els.forEach(e => { const t = lang === "en" ? e.dataset.en : e.dataset.de; if (e.tagName === "TITLE") e.textContent = t; else e.innerHTML = t; });
    if (meta && meta.dataset.enContent) meta.content = lang === "en" ? meta.dataset.enContent : meta.dataset.de;
    // Blog dm5mn.com in derselben Sprache oeffnen
    document.querySelectorAll('a[href^="https://dm5mn.com"]').forEach(a => { const u = new URL(a.href); u.searchParams.set("lang", lang); a.href = u.toString(); });
    document.querySelectorAll(".lang button").forEach(b => b.classList.toggle("on", b.dataset.lang === lang));
    // Videos mit englischer Fassung: Quelle und Vorschaubild je nach Sprache
    document.querySelectorAll("video[data-src-en]").forEach(v => {
      const s = v.querySelector("source"); if (!s) return;
      if (!v.dataset.srcDe) { v.dataset.srcDe = s.getAttribute("src"); v.dataset.posterDe = v.getAttribute("poster") || ""; }
      const src = lang === "en" ? v.dataset.srcEn : v.dataset.srcDe;
      if (s.getAttribute("src") !== src) { v.pause(); s.setAttribute("src", src); v.setAttribute("poster", lang === "en" ? (v.dataset.posterEn || v.dataset.posterDe) : v.dataset.posterDe); v.load(); }
    });
    if (keep) { try { localStorage.setItem("rv-lang", lang); } catch (e) {} }
  };
  document.querySelectorAll(".lang button").forEach(b => b.onclick = () => set(b.dataset.lang, true));
  set(saved === "de" || saved === "en" ? saved : auto, false);
})();
