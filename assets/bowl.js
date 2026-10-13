// Açaí bowl drawing for the "build your bowl" picker. Every topping is its own layer,
// so the page can drop it in when the customer picks it (class "on").

// Small seeded random so the toppings sit in the same places every time
function rng(seed) {
  let s = seed;
  return () => { s = (s * 16807) % 2147483647; return (s - 1) / 2147483646; };
}

// Is (x, y) inside the açaí surface?
const inBowl = (x, y) => ((x - 200) / 142) ** 2 + ((y - 124) / 44) ** 2 < 1;

function scatter(seed, n, x0, x1, y0, y1) {
  const r = rng(seed), pts = [];
  let guard = 0;
  while (pts.length < n && guard++ < 4000) {
    const x = x0 + r() * (x1 - x0), y = y0 + r() * (y1 - y0);
    if (inBowl(x, y)) pts.push([x, y, r()]);
  }
  return pts.sort((a, b) => a[1] - b[1]);   // back to front
}

const f = v => v.toFixed(1);
// A thin wavy drizzle across the bowl
const drizzle = (y, amp, color, light, w) => {
  let d = `M78 ${y}`;
  for (let i = 0; i < 9; i++) { const x = 78 + i * 28; d += ` Q${x + 14} ${y + (i % 2 ? amp : -amp)} ${x + 28} ${y}`; }
  return `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${light}" stroke-width="${w / 3}" stroke-linecap="round" transform="translate(0 -1)"/>`;
};

const LAYERS = {
  granola: () => scatter(11, 46, 62, 158, 88, 162).map(([x, y, t]) =>
    `<path d="M${f(x)} ${f(y)} l${f(5 + t * 5)} -${f(3 + t * 3)} l${f(4 + t * 3)} ${f(5 + t * 2)} l-${f(6 + t * 4)} ${f(4 + t)}z" fill="${t > .5 ? '#C98B3C' : '#B07430'}" stroke="#8A5520" stroke-width=".8"/>`).join(''),
  banana: () => [[160, 92], [184, 89], [208, 88], [232, 89], [256, 92]].map(([x, y]) =>
    `<ellipse cx="${x}" cy="${y}" rx="14" ry="8.5" fill="#FFF3C4" stroke="#E8C766" stroke-width="2.4"/><ellipse cx="${x}" cy="${y}" rx="4" ry="2.4" fill="#E9D58E"/>`).join(''),
  straw: () => [[268, 98, -20], [296, 104, 15], [318, 116, -10], [282, 120, 25]].map(([x, y, a]) =>
    `<g transform="translate(${x} ${y}) rotate(${a}) scale(1.45)"><path d="M0 -9 C9 -9 11 2 0 9 C-11 2 -9 -9 0 -9z" fill="#E2394B" stroke="#B5212F" stroke-width="1"/><path d="M-3 -4h1M2 -2h1M-1 2h1M3 3h1M-4 1h1" stroke="#FFD9A0" stroke-width="1.3" stroke-linecap="round"/><path d="M-4 -9 L0 -12 L4 -9" fill="none" stroke="#3E8E41" stroke-width="2" stroke-linecap="round"/></g>`).join(''),
  blue: () => scatter(51, 16, 252, 334, 126, 164).map(([x, y]) =>
    `<circle cx="${f(x)}" cy="${f(y)}" r="6.6" fill="#33428F"/><circle cx="${f(x - 2)}" cy="${f(y - 2.2)}" r="1.8" fill="#8E9BE0"/>`).join(''),
  rasp: () => [[168, 146], [192, 152], [216, 150], [240, 145], [180, 132], [228, 133]].map(([x, y]) =>
    [[-3, -3], [3, -3], [0, 0], [-3, 3], [3, 3], [0, -5.5], [0, 5.5], [-5.5, 0], [5.5, 0]].map(([dx, dy]) =>
      `<circle cx="${x + dx}" cy="${y + dy}" r="3.2" fill="#D23C6E" stroke="#A2264F" stroke-width=".6"/>`).join('')).join(''),
  almond: () => scatter(83, 30, 120, 285, 100, 150).map(([x, y, t]) =>
    `<path d="M${f(x)} ${f(y)} l${f(4 + t * 3)} -2 l1.2 ${f(3 + t)} l-${f(5 + t * 2)} 1z" fill="#F4E1C3" stroke="#C9A27A" stroke-width=".7"/>`).join(''),
  pb: () => drizzle(112, 7, '#8B5A2B', '#B7804A', 4.5),
  honey: () => drizzle(136, 7, '#F2B233', '#FFE08A', 4),
};

// Drawing order: things lying under the drizzles first
export const TOPPING_ORDER = ['granola', 'banana', 'straw', 'blue', 'rasp', 'almond', 'pb', 'honey'];

/** The bowl as an SVG string. `on` = the topping keys to show. */
export function bowlSVG(on = [], { label = '' } = {}) {
  // `on` may repeat a key (double banana); the 2nd and 3rd portions are extra copies, shifted a little
  const n = {}; on.forEach(k => { n[k] = (n[k] || 0) + 1; });
  const SHIFT = { 2: 'translate(10 9)', 3: 'translate(-11 7)' };
  const layers = [1, 2, 3].map(i => TOPPING_ORDER.map(k => {
    const g = `<g class="tp tp-${k} tp-${k}-${i}${(n[k] || 0) >= i ? ' on' : ''}">${LAYERS[k]()}</g>`;
    return i === 1 ? g : `<g transform="${SHIFT[i]}">${g}</g>`;
  }).join('')).join('');
  return `<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${label}">
  <ellipse cx="200" cy="278" rx="118" ry="13" fill="#470D43" opacity=".12"/>
  <path d="M32 124 C38 226 118 270 200 270 C282 270 362 226 368 124 Z" fill="#FFFFFF"/>
  <path d="M32 124 C38 226 118 270 200 270 C282 270 362 226 368 124 Z" fill="none" stroke="#E6D9C3" stroke-width="3"/>
  <path d="M58 196 C100 232 150 240 200 240 C250 240 300 232 342 196" fill="none" stroke="#470D43" stroke-width="10" stroke-linecap="round" opacity=".9"/>
  <ellipse cx="200" cy="122" rx="168" ry="64" fill="#FFFFFF" stroke="#E6D9C3" stroke-width="3"/>
  <ellipse cx="200" cy="125" rx="150" ry="51" fill="#4A1246"/>
  <ellipse cx="190" cy="112" rx="104" ry="30" fill="#5A1A55" opacity=".85"/>
  <ellipse cx="150" cy="98" rx="46" ry="10" fill="#7A3474" opacity=".5"/>
  ${layers}
</svg>`;
}
