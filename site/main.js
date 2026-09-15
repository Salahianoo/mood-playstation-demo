// Portfolio links. The LinkedIn button stays hidden until a URL is set.
const PROFILE = {
  name: 'Salah',
  github: 'https://github.com/Salahianoo',
  linkedin: '',
};

document.documentElement.classList.remove('no-js');

for (const el of document.querySelectorAll('[data-profile]')) {
  const value = PROFILE[el.dataset.profile];
  if (!value) continue;
  if (el.tagName === 'A') {
    el.href = value;
    el.hidden = false;
  } else {
    el.textContent = value;
  }
}
for (const el of document.querySelectorAll('[data-year]')) {
  el.textContent = new Date().getFullYear();
}

// localStorage can be missing or throw (private windows, blocked storage).
const store = {
  get(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw == null ? fallback : JSON.parse(raw);
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {}
  },
};

// ── Simulator ────────────────────────────────────────────────────────
// Each device is the app's real logical viewport — the same two design
// baselines the Flutter app switches between (see lib/app.dart).
const DEVICES = {
  tablet: { w: 1280, h: 800, bezel: 22, radius: 34 },
  phone: { w: 390, h: 844, bezel: 12, radius: 56 },
};

const stage = document.querySelector('[data-stage]');
const deviceFrame = stage.querySelector('[data-device-frame]');
const screen = stage.querySelector('[data-screen]');
const narrow = matchMedia('(max-width: 760px)').matches;
let device = store.get('mood-device', narrow ? 'phone' : 'tablet');
if (!DEVICES[device]) device = 'tablet';
let iframe = null;
let readyPoll = 0;

function fit() {
  const d = DEVICES[device];
  const maxW = stage.clientWidth - d.bezel * 2;
  const maxH = Math.min(window.innerHeight - 120, device === 'phone' ? 880 : 920) - d.bezel * 2;
  const s = Math.max(0.2, Math.min(1, maxW / d.w, maxH / d.h));
  deviceFrame.style.setProperty('--s', s.toFixed(4));
  deviceFrame.style.setProperty('--w', `${d.w}px`);
  deviceFrame.style.setProperty('--h', `${d.h}px`);
  deviceFrame.style.setProperty('--bezel', `${d.bezel}px`);
  deviceFrame.style.setProperty('--radius', `${d.radius}px`);
  deviceFrame.classList.toggle('is-phone', device === 'phone');
}

// Switching devices resizes the live iframe in place — the app re-lays
// itself out between its tablet and phone layouts without reloading.
function setDevice(next) {
  device = next;
  store.set('mood-device', next);
  for (const btn of document.querySelectorAll('[data-device]')) {
    const on = btn.dataset.device === next;
    btn.setAttribute('aria-checked', String(on));
    btn.tabIndex = on ? 0 : -1;
  }
  fit();
}

function launch({ reset = false } = {}) {
  if (!iframe) {
    iframe = document.createElement('iframe');
    iframe.title = 'Mood PlayStation — live app';
    iframe.allow = 'autoplay; fullscreen; vibrate';
    screen.append(iframe);
  }
  stage.classList.add('is-live', 'is-loading');
  iframe.src = reset ? `app/?reset=${Date.now()}` : 'app/';

  // The app removes its own splash on Flutter's first frame; until then
  // keep the branded loader over the (initially blank) iframe.
  clearInterval(readyPoll);
  const startedAt = performance.now();
  readyPoll = setInterval(() => {
    let ready;
    try {
      const doc = iframe.contentDocument;
      ready = doc?.readyState === 'complete' && !doc.getElementById('splash');
    } catch {
      ready = true;
    }
    if (ready || performance.now() - startedAt > 30000) {
      clearInterval(readyPoll);
      stage.classList.remove('is-loading');
      iframe.focus();
    }
  }, 200);
}

for (const el of document.querySelectorAll('[data-launch]')) {
  el.addEventListener('click', () => {
    if (!iframe) launch();
  });
}
document.querySelector('[data-reset]').addEventListener('click', () => launch({ reset: true }));

const deviceButtons = [...document.querySelectorAll('[data-device]')];
for (const btn of deviceButtons) {
  btn.addEventListener('click', () => setDevice(btn.dataset.device));
  btn.addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const next = deviceButtons[(deviceButtons.indexOf(btn) + 1) % deviceButtons.length];
    setDevice(next.dataset.device);
    next.focus();
  });
}

new ResizeObserver(fit).observe(stage);
window.addEventListener('resize', fit);
setDevice(device);

// ── Missions ─────────────────────────────────────────────────────────
const doneMissions = new Set(store.get('mood-missions', []));
for (const mission of document.querySelectorAll('[data-mission]')) {
  const id = mission.dataset.mission;
  const check = mission.querySelector('.mission__check');
  const sync = () => {
    const done = doneMissions.has(id);
    mission.classList.toggle('is-done', done);
    check.setAttribute('aria-pressed', String(done));
  };
  check.addEventListener('click', () => {
    if (doneMissions.has(id)) doneMissions.delete(id);
    else doneMissions.add(id);
    store.set('mood-missions', [...doneMissions]);
    sync();
  });
  sync();
}

// ── Arabic cheat-sheet ───────────────────────────────────────────────
const glossary = document.querySelector('[data-glossary]');
document.querySelector('[data-glossary-open]').addEventListener('click', () => glossary.showModal());
glossary.addEventListener('click', (event) => {
  if (event.target === glossary) glossary.close();
});

// ── Room replicas ────────────────────────────────────────────────────
// Same rule as the app: elapsed = now − start, never a stored counter.
const pageOpenedAt = Date.now();
const two = (n) => String(Math.floor(n)).padStart(2, '0');
const hms = (sec) => `${two(sec / 3600)}:${two((sec % 3600) / 60)}:${two(sec % 60)}`;
const clock12 = (d) => `${d.getHours() % 12 || 12}:${String(d.getMinutes()).padStart(2, '0')} ${d.getHours() < 12 ? 'ص' : 'م'}`;

const booking = document.querySelector('[data-booking]');
if (booking) {
  const from = new Date();
  from.setMinutes(0, 0, 0);
  from.setHours(from.getHours() + 2);
  const to = new Date(from.getTime() + 2 * 3600e3);
  booking.textContent = `محجوزة ${clock12(from)} ← ${clock12(to)}`;
}

function tickRooms() {
  const since = (Date.now() - pageOpenedAt) / 1000;
  for (const clock of document.querySelectorAll('[data-rooms] [data-clock]')) {
    const seconds = -Number(clock.dataset.start) + since;
    clock.textContent = hms(seconds);
    const total = clock.closest('.room').querySelector('[data-total][data-rate]');
    if (total) {
      const amount = Number(total.dataset.items) + (seconds / 3600) * Number(total.dataset.rate);
      total.textContent = `${amount.toFixed(3)} د.أ`;
    }
  }
}
tickRooms();
setInterval(tickRooms, 1000);

// ── Reveal on scroll ─────────────────────────────────────────────────
const revealer = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    entry.target.classList.add('is-in');
    revealer.unobserve(entry.target);
  }
}, { rootMargin: '0px 0px -8% 0px' });

for (const el of document.querySelectorAll('.reveal')) {
  const siblings = [...el.parentElement.children].filter((c) => c.classList.contains('reveal'));
  el.style.transitionDelay = `${Math.min(siblings.indexOf(el), 5) * 70}ms`;
  revealer.observe(el);
}
