(() => {
  const win = document.getElementById('window');
  const scaleBox = win.parentElement;
  const stage = document.getElementById('stage');
  const switcher = document.getElementById('switcher');
  const cursor = document.getElementById('cursor');
  const typed = document.getElementById('typed');
  const caret = document.getElementById('caret');
  const count = document.getElementById('count');

  const SOURCE =
`# Shipping is a habit

Most writers overthink the first line. **Write the ugly version first**, then cut.

- Say one thing
- Say it plainly
- Stop when it's said

The feed doesn't reward *clever*. It rewards clear.`;

  const COUNTS = { x: ['206 / 25,000', 1], linkedin: ['206 / 3,000', 7], slack: ['206 / 40,000', 1] };
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Keep the 960x600 window crisp at any width.
  const fit = () => { win.style.transform = `scale(${scaleBox.clientWidth / 960})`; };
  new ResizeObserver(fit).observe(scaleBox);
  fit();

  const views = [...stage.querySelectorAll('.view')];
  const buttons = [...switcher.querySelectorAll('button')];
  let current = null;

  function show(name) {
    if (current === name) return;
    current = name;
    views.forEach(v => v.classList.toggle('on', v.dataset.view === name));
    buttons.forEach(b => {
      const on = b.dataset.view === name;
      b.classList.toggle('on', on);
      b.setAttribute('aria-selected', on);
    });
    const c = COUNTS[name];
    count.classList.toggle('on', !!c);
    if (c) { count.textContent = c[0]; count.style.setProperty('--p', c[1] + '%'); }
  }

  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let token = 0;
  const alive = t => t === token;

  function moveCursorTo(el) {
    const r = el.getBoundingClientRect();
    const w = win.getBoundingClientRect();
    const s = w.width / 960;
    const x = (r.left + r.width / 2 - w.left) / s - 2;
    const y = (r.top + r.height / 2 - w.top) / s - 1;
    cursor.style.transform = `translate(${x}px, ${y}px)`;
  }

  function parkCursor() {
    cursor.style.transform = 'translate(560px, 340px)';
  }

  async function clickButton(name, t) {
    const btn = buttons.find(b => b.dataset.view === name);
    moveCursorTo(btn);
    await sleep(850);
    if (!alive(t)) return;
    cursor.classList.add('click');
    btn.classList.add('press');
    await sleep(110);
    cursor.classList.remove('click');
    btn.classList.remove('press');
    show(name);
  }

  async function typeSource(t) {
    typed.textContent = '';
    caret.style.display = '';
    for (let i = 0; i < SOURCE.length; i++) {
      if (!alive(t)) return;
      typed.textContent += SOURCE[i];
      const ch = SOURCE[i];
      await sleep(ch === '\n' ? 140 : ch === ' ' ? 34 : 18 + Math.random() * 22);
    }
  }

  async function play() {
    const t = ++token;
    while (alive(t)) {
      show('plaintext');
      cursor.classList.remove('show');
      parkCursor();
      await typeSource(t); if (!alive(t)) return;
      await sleep(700); if (!alive(t)) return;
      cursor.classList.add('show');
      await sleep(300); if (!alive(t)) return;
      for (const name of ['markdown', 'x', 'linkedin', 'slack']) {
        await clickButton(name, t); if (!alive(t)) return;
        await sleep(name === 'slack' ? 2600 : 2300); if (!alive(t)) return;
      }
      await clickButton('plaintext', t); if (!alive(t)) return;
      await sleep(600);
    }
  }

  // Manual control: clicking the switcher pauses the tour.
  buttons.forEach(b => b.addEventListener('click', () => {
    token++;
    cursor.classList.remove('show');
    typed.textContent = SOURCE;
    show(b.dataset.view);
  }));

  if (reduce) {
    typed.textContent = SOURCE;
    caret.style.display = 'none';
    show('markdown');
  } else {
    // Start when the window scrolls into view.
    const io = new IntersectionObserver(es => {
      if (es.some(e => e.isIntersecting)) { io.disconnect(); play(); }
    }, { threshold: 0.35 });
    io.observe(win);
  }

  // Latest release: version + size under the button, and a fallback if no release exists yet.
  fetch('https://api.github.com/repos/jzone3/new-media-writer/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then(r => r.ok ? r.json() : Promise.reject(r.status))
    .then(rel => {
      const dmg = (rel.assets || []).find(a => a.name === 'New-Media-Writer.dmg')
        || (rel.assets || []).find(a => a.name.endsWith('.dmg'));
      if (!dmg) return;
      document.querySelectorAll('[data-download]').forEach(a => a.href = dmg.browser_download_url);
      const mb = (dmg.size / 1048576).toFixed(1);
      const meta = document.querySelector('[data-release-meta]');
      if (meta) meta.textContent = `${rel.tag_name} · ${mb} MB · macOS 14+ · Signed & notarized`;
    })
    .catch(status => {
      if (status === 404) document.querySelectorAll('[data-download]').forEach(a => a.href = 'https://github.com/jzone3/new-media-writer/releases');
    });
})();
