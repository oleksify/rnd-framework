// rnd-framework docs — client-side renderer.
// Fetch the section list, render each Markdown file with `marked`, assemble one
// long page, then build a table of contents from the headings. No build step.

const MANIFEST = "docs/manifest.json";

const slugify = (s) =>
  s.toLowerCase().trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-");

async function fetchText(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  return res.text();
}

async function render() {
  const content = document.getElementById("content");
  const tocList = document.getElementById("toc-list");

  let manifest;
  try {
    manifest = JSON.parse(await fetchText(MANIFEST));
  } catch (e) {
    content.innerHTML = `<p class="error">Could not load docs manifest (${e.message}).</p>`;
    return;
  }

  let sources;
  try {
    sources = await Promise.all(
      manifest.map((entry) => fetchText("docs/" + entry.file))
    );
  } catch (e) {
    content.innerHTML = `<p class="error">Could not load a docs section (${e.message}).</p>`;
    return;
  }

  const html = sources
    .map((md) => `<section>${marked.parse(md)}</section>`)
    .join("\n");

  content.innerHTML = html;

  // Assign ids to section headings and build the table of contents.
  const used = new Set();
  const headings = content.querySelectorAll("h2, h3");
  const tocLinks = {};
  const orderedIds = [];

  headings.forEach((h) => {
    const text = h.textContent;
    let id = slugify(text);
    let n = 1;
    while (used.has(id)) id = `${slugify(text)}-${++n}`;
    used.add(id);
    h.id = id;
    orderedIds.push(id);

    const anchor = document.createElement("a");
    anchor.href = "#" + id;
    anchor.className = "anchor";
    anchor.textContent = "#";
    anchor.setAttribute("aria-hidden", "true");
    h.appendChild(anchor);

    const li = document.createElement("li");
    li.className = h.tagName === "H3" ? "lvl-3" : "lvl-2";
    const link = document.createElement("a");
    link.href = "#" + id;
    link.textContent = text;
    li.appendChild(link);
    tocList.appendChild(li);
    tocLinks[id] = link;
  });

  setupScrollSpy(headings, orderedIds, tocLinks);

  // Honour a deep link that arrived before content existed.
  if (location.hash) {
    const target = document.getElementById(location.hash.slice(1));
    if (target) target.scrollIntoView();
  }
}

// Highlight the table-of-contents entry for the section currently in view.
function setupScrollSpy(headings, orderedIds, tocLinks) {
  const nav = document.getElementById("toc");
  let activeId = null;

  // Keep the active entry visible inside the (scrollable) sidebar, without
  // ever scrolling the page itself.
  const keepInView = (el) => {
    const e = el.getBoundingClientRect();
    const n = nav.getBoundingClientRect();
    if (e.top < n.top) nav.scrollTop -= n.top - e.top + 8;
    else if (e.bottom > n.bottom) nav.scrollTop += e.bottom - n.bottom + 8;
  };

  const setActive = (id) => {
    if (id === activeId || !tocLinks[id]) return;
    if (activeId && tocLinks[activeId]) tocLinks[activeId].classList.remove("active");
    activeId = id;
    tocLinks[id].classList.add("active");
    keepInView(tocLinks[id]);
  };

  const visible = new Set();
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) visible.add(entry.target.id);
        else visible.delete(entry.target.id);
      }
      const current = orderedIds.find((id) => visible.has(id));
      if (current) setActive(current);
    },
    { rootMargin: "-12% 0px -80% 0px", threshold: 0 }
  );

  headings.forEach((h) => observer.observe(h));
  if (orderedIds.length) setActive(orderedIds[0]);
}

render();
