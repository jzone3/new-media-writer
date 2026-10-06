// Time-driven walkthrough (same schedule as the launch video): the Declaration is typed into Plaintext and the
// cursor switches view at fixed points in the text; typing resumes in the rendered view. render(t) is pure.
(() => {
  const win = document.getElementById('window');
  const scaleBox = win.parentElement;
  const stage = document.getElementById('stage');
  const switcher = document.getElementById('switcher');
  const cursor = document.getElementById('cursor');
  const count = document.getElementById('count');

  const SOURCE =
`# The Declaration of Independence

When in the Course of human events, it becomes necessary for one people to dissolve the political bands which have connected them with another…

We hold these truths to be self-evident, that **all men are created equal**, that they are endowed by their Creator with certain unalienable Rights, that among these are:

- Life
- Liberty
- the pursuit of Happiness

That to secure these rights, Governments are instituted among Men, deriving their just powers from the *consent of the governed*.`;

  // Where the mouse switches view while the text is still being typed (char index into SOURCE).
  const BREAKS = [
    { at: SOURCE.indexOf('When in'),        view: 'x' },
    { at: SOURCE.indexOf('We hold'),        view: 'linkedin' },
    { at: SOURCE.indexOf('That to secure'), view: 'slack' },
  ];
  const LIMITS = { x: 25000, linkedin: 3000, slack: 40000 };
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- schedule (deterministic) ----------
  let seed = 7;
  const MOVE = 380, DWELL = 1000;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  const charAt = [];            // time each char appears
  const clicks = [];            // {view, moveStart, clickAt}
  let t = 600, bi = 0;
  for (let i = 0; i < SOURCE.length; i++) {
    if (bi < BREAKS.length && BREAKS[bi].at === i) {
      t += 250;
      clicks.push({ view: BREAKS[bi].view, moveStart: t, clickAt: t + MOVE + 90 });
      t += MOVE + 90 + DWELL;
      bi++;
    }
    const ch = SOURCE[i];
    charAt.push(t);
    t += ch === '\n' ? 70 : ch === ' ' ? 16 : 9 + rnd() * 11;
    if (ch === '.' || ch === ',' || ch === ':' || ch === '…') t += 40;
  }
  // typing ends in Slack; hold on the finished message, then back to Plaintext for the loop
  t += 2800;
  clicks.push({ view: 'plaintext', moveStart: t, clickAt: t + MOVE + 90 });
  const END = t + MOVE + 90 + 900;

  // Phones: the demo section leads the page (moved in the DOM so reading order matches), with the script
  // title under the window; it fades in once the page has settled. Desktop keeps the title in the hero.
  const mobile = matchMedia('(max-width: 768px)');
  const hero = document.querySelector('.hero');
  const demo = scaleBox.parentElement;
  const title = document.querySelector('h1.script');
  let titleTimer = 0;
  const placeTitle = () => {
    clearTimeout(titleTimer);
    if (!title) return;
    if (mobile.matches) {
      if (demo.nextElementSibling !== hero) hero.parentElement.insertBefore(demo, hero);
      if (title.parentElement !== demo) { title.classList.remove('in'); demo.appendChild(title); }
      titleTimer = setTimeout(() => title.classList.add('in'), reduce ? 0 : 700);
    } else {
      if (hero.nextElementSibling !== demo) hero.parentElement.insertBefore(demo, hero.nextElementSibling);
      if (title.parentElement !== hero) { title.classList.remove('in'); hero.prepend(title); }
    }
  };
  placeTitle();
  mobile.addEventListener('change', placeTitle);

  // Keep the window crisp at any width: scale the --win-w x --win-h window to the box. On phones the box
  // is also capped by height so window + title fit the first screen.
  const fit = () => {
    const cs = getComputedStyle(scaleBox);
    const W = parseFloat(cs.getPropertyValue('--win-w')) || 960;
    const H = parseFloat(cs.getPropertyValue('--win-h')) || 600;
    let s = demo.clientWidth / W;
    if (mobile.matches) {
      const byWidth = (demo.clientWidth - 32) / W;
      const byHeight = Math.max(300, innerHeight - 72 - 190) / H;
      s = Math.max(Math.min(byWidth, byHeight), byWidth * 0.85);
      scaleBox.style.width = `${W * s}px`;
      scaleBox.style.height = `${H * s}px`;
    } else {
      scaleBox.style.width = scaleBox.style.height = '';
      s = scaleBox.clientWidth / W;
    }
    win.style.transform = `scale(${s})`;
  };
  new ResizeObserver(fit).observe(demo);
  addEventListener('resize', fit);
  fit();

  const views = [...stage.querySelectorAll('.view')];
  const buttons = [...switcher.querySelectorAll('button')];
  const live = {
    raw: [...stage.querySelectorAll('[data-live="raw"]')],
    doc: [...stage.querySelectorAll('[data-live="doc"]')],
    post: [...stage.querySelectorAll('[data-live="post"]')],
  };
  const btnCenter = name => {
    const b = buttons.find(b => b.dataset.view === name);
    return { x: b.offsetLeft + b.offsetParent.offsetLeft + b.offsetWidth / 2 - 2, y: b.offsetTop + b.offsetParent.offsetTop + b.offsetHeight / 2 - 1 };
  };
  const PARK = { get x() { return win.offsetWidth * 0.62; }, get y() { return win.offsetHeight * 0.6; } };
  const ease = p => 1 - Math.pow(1 - p, 3);
  const clamp = v => Math.max(0, Math.min(1, v));
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

  // ---------- markdown → html ----------
  function inline(s) {
    s = esc(s);
    s = s.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
    s = s.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<i>$2</i>');
    return s;
  }
  function blocks(src) {
    const out = []; let para = [], list = null;
    const flush = () => {
      if (para.length) { out.push({ type: 'p', text: para.join('\n') }); para = []; }
      if (list) { out.push({ type: 'ul', items: list }); list = null; }
    };
    for (const line of src.split('\n')) {
      if (line.startsWith('# ')) { flush(); out.push({ type: 'h', text: line.slice(2) }); }
      else if (line.startsWith('- ')) { if (para.length) flush(); (list ??= []).push(line.slice(2)); }
      else if (line.trim() === '') flush();
      else { if (list) flush(); para.push(line); }
    }
    flush();
    return out;
  }
  const CARET = '<span class="caret"></span>';
  function renderDoc(src, caret) {
    const b = blocks(src);
    let html = b.map((blk, i) => {
      const c = i === b.length - 1 && caret ? CARET : '';
      if (blk.type === 'h') return `<h2>${inline(blk.text)}${c}</h2>`;
      if (blk.type === 'ul') return `<ul>${blk.items.map((it, j) => `<li>${inline(it)}${j === blk.items.length - 1 ? c : ''}</li>`).join('')}</ul>`;
      return `<p>${inline(blk.text).replace(/\n/g, '<br>')}${c}</p>`;
    }).join('');
    if (!b.length && caret) html = `<p>${CARET}</p>`;
    return html;
  }
  function renderPost(src, caret) {
    const b = blocks(src);
    let html = b.map((blk, i) => {
      const c = i === b.length - 1 && caret ? CARET : '';
      if (blk.type === 'h') return `<p><b>${inline(blk.text)}</b>${c}</p>`;
      if (blk.type === 'ul') return `<p>${blk.items.map(it => '• ' + inline(it)).join('<br>')}${c}</p>`;
      return `<p>${inline(blk.text).replace(/\n/g, '<br>')}${c}</p>`;
    }).join('');
    if (!b.length && caret) html = `<p>${CARET}</p>`;
    return html;
  }
  const plainCount = src => src.replace(/^# /gm, '').replace(/^- /gm, '• ').replace(/\*\*([^*]+)\*\*/g, '$1').replace(/\*([^*\n]+)\*/g, '$1').length;

  function setView(cur, prev, p) {
    views.forEach(v => {
      const name = v.dataset.view;
      let o = 0, y = 6;
      if (name === cur) { o = ease(p); y = 6 * (1 - ease(p)); }
      else if (name === prev && p < 1) { o = 1 - ease(p); y = 0; }
      v.style.opacity = o; v.style.visibility = o > 0 ? 'visible' : 'hidden';
      v.style.transform = `translateY(${y}px)`;
      v.style.zIndex = name === cur ? 2 : 1;
    });
    buttons.forEach(b => {
      const on = b.dataset.view === cur;
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', on);
    });
  }
  function setCount(cur, src) {
    const lim = LIMITS[cur];
    count.classList.toggle('on', !!lim);
    if (!lim) return;
    const used = plainCount(src);
    count.textContent = `${used.toLocaleString('en-US')} / ${lim.toLocaleString('en-US')}`;
    count.style.setProperty('--p', Math.max(1, Math.min(100, used / lim * 100 * (cur === 'linkedin' ? 1 : 6))).toFixed(1) + '%');
  }

  function render(t) {
    let n = 0; while (n < charAt.length && charAt[n] <= t) n++;
    const src = SOURCE.slice(0, n);
    const typingDone = n >= SOURCE.length;
    const caretOn = !typingDone || Math.floor(t / 530) % 2 === 0;
    live.raw.forEach(el => el.innerHTML = esc(src) + (caretOn ? CARET : ''));
    live.doc.forEach(el => el.innerHTML = renderDoc(src, caretOn));
    live.post.forEach(el => el.innerHTML = renderPost(src, caretOn));

    let cur = 'plaintext', prev = null, p = 1;
    for (const c of clicks) if (c.clickAt <= t) { prev = cur; cur = c.view; p = clamp((t - c.clickAt) / 220); }
    setView(cur, prev, p);
    buttons.forEach(b => b.classList.toggle('press', clicks.some(c => t >= c.clickAt - 110 && t < c.clickAt + 40 && c.view === b.dataset.view)));
    setCount(cur, src);

    // mouse: parked off to the side, glides to each button with a slight arc
    const firstMove = clicks[0].moveStart, lastClick = clicks[clicks.length - 1].clickAt;
    let cx = PARK.x, cy = PARK.y, from = PARK;
    for (const c of clicks) {
      const to = btnCenter(c.view);
      if (t >= c.moveStart) {
        const q = ease(clamp((t - c.moveStart) / MOVE));
        cx = from.x + (to.x - from.x) * q; cy = from.y + (to.y - from.y) * q - Math.sin(q * Math.PI) * 18;
        from = to;
      }
    }
    const show = t >= firstMove - 200 && t < lastClick + 500;
    cursor.style.opacity = show ? clamp((t - (firstMove - 200)) / 200) * (1 - clamp((t - lastClick - 300) / 200)) : 0;
    cursor.style.transform = `translate(${cx}px, ${cy}px)`;
    cursor.classList.toggle('click', clicks.some(c => t >= c.clickAt - 110 && t < c.clickAt + 40));
  }
  // Final state: full text, chosen view, no cursor.
  function renderStatic(view) {
    live.raw.forEach(el => el.innerHTML = esc(SOURCE));
    live.doc.forEach(el => el.innerHTML = renderDoc(SOURCE, false));
    live.post.forEach(el => el.innerHTML = renderPost(SOURCE, false));
    setView(view, null, 1);
    setCount(view, SOURCE);
    cursor.style.opacity = 0;
  }
  window.__walkthrough = { render, duration: END };

  let playing = false, raf = 0;
  function play() {
    playing = true;
    const t0 = performance.now();
    const loop = () => {
      if (!playing) return;
      render((performance.now() - t0) % (END + 600));
      raf = requestAnimationFrame(loop);
    };
    loop();
  }

  // Manual control: clicking the switcher stops the tour and shows the finished post in that view.
  buttons.forEach(b => b.addEventListener('click', () => {
    playing = false; cancelAnimationFrame(raf);
    renderStatic(b.dataset.view);
  }));

  if (reduce || navigator.webdriver && !location.hash.includes('play')) {
    renderStatic('x');
  } else {
    render(0);
    // Start as soon as any part of the window is on screen.
    const io = new IntersectionObserver(es => {
      if (es.some(e => e.isIntersecting)) { io.disconnect(); play(); }
    }, { threshold: 0 });
    io.observe(win);
  }

  // Links start at the releases page (always valid); upgrade to the direct DMG once the latest release is known.
  fetch('https://api.github.com/repos/jzone3/new-media-writer/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then(r => r.ok ? r.json() : Promise.reject(r.status))
    .then(rel => {
      const dmg = (rel.assets || []).find(a => a.name === 'New-Media-Writer.dmg')
        || (rel.assets || []).find(a => a.name.endsWith('.dmg'));
      if (!dmg) return;
      document.querySelectorAll('[data-download]').forEach(a => a.href = dmg.browser_download_url);
      const mb = (dmg.size / 1048576).toFixed(1);
      const meta = document.querySelector('[data-release-meta]');
      if (meta) meta.textContent = `${rel.tag_name} · ${mb} MB · macOS 14+ · Signed & notarized · Free`;
    })
    .catch(() => {});
})();
