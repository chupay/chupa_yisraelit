// Homepage behaviour (index.html)

document.getElementById('year').textContent = new Date().getFullYear();

function applyScrollMargins() {
  const nav = document.querySelector('header.nav');
  const offset = (nav?.offsetHeight || 100) + 10;
  document.querySelectorAll('section').forEach(sec => {
    sec.style.scrollMarginTop = offset + 'px';
  });
}
window.addEventListener('load', applyScrollMargins);
window.addEventListener('resize', applyScrollMargins);

const sections = Array.from(document.querySelectorAll('main section')).map(s => ({id: s.id, el: s}));
const menuLinks = Array.from(document.querySelectorAll('.menu a'));
const io = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if(entry.isIntersecting){
      const id = entry.target.id;
      menuLinks.forEach(a => a.classList.toggle('active', a.getAttribute('href') === `#${id}`));
    }
  });
}, {rootMargin: '-50% 0px -50% 0px', threshold: 0});
sections.forEach(s => io.observe(s.el));

document.querySelectorAll('[data-toggle]').forEach(btn => {
  const sel = btn.getAttribute('data-toggle');
  const panel = document.querySelector(sel);
  btn.addEventListener('click', () => {
    const isOpen = !panel.hasAttribute('hidden');
    if(isOpen){
      panel.setAttribute('hidden','');
      btn.setAttribute('aria-expanded','false');
    } else {
      panel.removeAttribute('hidden');
      btn.setAttribute('aria-expanded','true');
    }
  });
});

const photoPool = [
  {src:'assets/img/gallery/standing-chuppah-balcony-sea-view.webp', alt:'חופה עומדת במרפסת עם נוף לים, מקושטת בפרחים'},
  {src:'assets/img/gallery/standing-chuppah-personalized-canopy.webp', alt:'חופה עומדת עם בד מותאם אישית, ליד חומת אבן'},
  {src:'assets/img/gallery/standing-chuppah-garden-flowers-1.webp', alt:'חופה עומדת בגינה, מקושטת בפרחים'},
  {src:'assets/img/gallery/standing-chuppah-garden-flowers-2.webp', alt:'חופה עומדת בגינה, מקושטת בפרחים – מבט נוסף'},
  {src:'assets/img/gallery/standing-chuppah-garden-sunset.webp', alt:'חופה עומדת בגינה בשעת שקיעה'},
  {src:'assets/img/gallery/standing-chuppah-indoor-hall.webp', alt:'חופה עומדת באולם, מקושטת בפרחים לבנים'},
  {src:'assets/img/gallery/held-chuppah-ceremony-1.webp', alt:'טקס חתונה תחת חופה נישאת – 1'},
  {src:'assets/img/gallery/held-chuppah-ceremony-2.webp', alt:'טקס חתונה תחת חופה נישאת – 2'},
  {src:'assets/img/gallery/held-chuppah-ceremony-3.webp', alt:'טקס חתונה תחת חופה נישאת – 3'},
  {src:'assets/img/gallery/held-chuppah-outdoor-ceremony-1.webp', alt:'טקס חתונה בחוץ תחת חופה נישאת – 1'},
  {src:'assets/img/gallery/held-chuppah-outdoor-ceremony-2.webp', alt:'טקס חתונה בחוץ תחת חופה נישאת – 2'}
];
const strip = document.getElementById('photo-strip');
const stripImgs = Array.from(strip.querySelectorAll('img'));

// Shuffle once, then walk the list 3 at a time (wrapping around).
// Every photo gets exactly the same screen time, in a random order per visit.
const order = photoPool.slice();
for(let i = order.length - 1; i > 0; i--){
  const j = Math.floor(Math.random() * (i + 1));
  [order[i], order[j]] = [order[j], order[i]];
}
let stripPos = 0;

function renderStrip(){
  const set = stripImgs.map((_, i) => order[(stripPos + i) % order.length]);
  stripPos = (stripPos + stripImgs.length) % order.length;
  stripImgs.forEach((img, i) => {
    const it = set[i];
    if(!it) return;
    img.style.opacity = '0';
    setTimeout(() => {
      img.src = it.src;
      img.alt = it.alt;
      img.loading = "lazy";
      img.decoding = "async";
      img.style.opacity = '1';
    }, 100);
  });
}

renderStrip();

// Rotate only while the strip is on screen, the tab is visible, and the visitor
// isn't hovering it or viewing a photo in the lightbox. A paused tick is skipped,
// so every photo still gets equal screen time. (With reduced motion the CSS
// drops the fade, but photos still change.)
let stripOnScreen = false;
let stripHovered = false;
new IntersectionObserver(entries => {
  stripOnScreen = entries[0].isIntersecting;
}).observe(strip);
strip.addEventListener('mouseenter', () => { stripHovered = true; });
strip.addEventListener('mouseleave', () => { stripHovered = false; });

setInterval(() => {
  const lightboxOpen = document.getElementById('lightbox').classList.contains('active');
  if(!stripOnScreen || stripHovered || lightboxOpen || document.hidden) return;
  renderStrip();
}, 4500);

(function(){
  const lb = document.getElementById('lightbox');
  const lbImg = lb.querySelector('img');
  const btnClose = lb.querySelector('.close');
  const btnPrev = lb.querySelector('.prev');
  const btnNext = lb.querySelector('.next');
  let currentList = [];
  let index = 0;

  const update = () => {
    const img = currentList[index];
    if(!img){ return; }
    lbImg.src = img.src;
    lbImg.alt = img.alt || 'תמונה מוגדלת';
  };
  const open = (list, i=0) => {
    if(!list || !list.length) return;
    currentList = list;
    index = Math.max(0, i);
    update();
    lb.classList.add('active');
    lb.setAttribute('aria-hidden','false');
  };
  const close = () => {
    lb.classList.remove('active');
    lb.setAttribute('aria-hidden','true');
    lbImg.removeAttribute('src');
  };
  const prev  = () => { if(!currentList.length) return; index = (index - 1 + currentList.length) % currentList.length; update(); };
  const next  = () => { if(!currentList.length) return; index = (index + 1) % currentList.length; update(); };

  document.addEventListener('click', (e) => {
    const targetImg = e.target.closest('.gallery img');
    if(!targetImg) return;
    const gal = targetImg.closest('.gallery');
    const imgs = Array.from(gal.querySelectorAll('img')).filter(im => im.src);
    const i = imgs.indexOf(targetImg);
    open(imgs, i);
  });

  btnClose.addEventListener('click', close);
  btnPrev.addEventListener('click', prev);
  btnNext.addEventListener('click', next);
  lb.addEventListener('click', (e) => { if(e.target === lb) close(); });
  document.addEventListener('keydown', (e) => {
    if(lb.classList.contains('active')){
      if(e.key === 'Escape') close();
      if(e.key === 'ArrowLeft') next();
      if(e.key === 'ArrowRight') prev();
    }
  });
})();

const wa = document.getElementById('wa-float');
const inline = document.querySelector('#contact a[href^="https://wa.me"]');
if(wa && inline) inline.setAttribute('href', wa.getAttribute('href'));
