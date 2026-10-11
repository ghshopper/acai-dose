export const $ = (s, r = document) => r.querySelector(s);
export const $$ = (s, r = document) => [...r.querySelectorAll(s)];

export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
export const money = n => Number(n || 0).toFixed(3);
export const arNum = s => String(s).replace(/\d/g, d => '٠١٢٣٤٥٦٧٨٩'[d]);
export function ymd(d) {
  const z = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`;
}

/** Calls api/api.php?a=<action>. GET when no body, JSON POST otherwise. Throws Error(code). */
export async function api(action, body, query = {}) {
  const qs = new URLSearchParams({ a: action, ...query }).toString();
  const opt = body === undefined
    ? { credentials: 'same-origin' }
    : { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
  let res;
  try { res = await fetch('api/api.php?' + qs, opt); } catch { throw new Error('network'); }
  let data = null;
  try { data = await res.json(); } catch { /* empty */ }
  if (!res.ok) throw new Error(data?.error || 'http_' + res.status);
  return data;
}

const MSG = {
  bad_login: 'اسم المستخدم أو كلمة السر غلط',
  too_many: 'محاولات كثيرة، انتظر شوي وجرب',
  network: 'ما فيه اتصال بالإنترنت',
  login_required: 'لازم تسجل دخول',
  forbidden: 'ما عندك صلاحية',
  short_password: 'كلمة السر ٦ حروف أو أكثر',
  bad_username: 'اسم المستخدم: حروف إنجليزية أو أرقام، ٣ حروف أو أكثر',
  username_taken: 'اسم المستخدم مستخدم من قبل',
};
export const msg = e => MSG[e?.message] || 'صار خطأ، جرب مرة ثانية';
const MSG_EN = {
  bad_login: 'Wrong username or password', too_many: 'Too many attempts, wait a minute', network: 'No internet connection',
  login_required: 'Please log in', forbidden: 'No permission', void_window: 'You can only void your own sale within 15 minutes',
};
export const msgEn = e => MSG_EN[e?.message] || 'Something went wrong, try again';

/** Shows a login card until signed in; resolves with {username, role}. */
export async function requireLogin(root, title, en = false) {
  try { const me = await api('me'); if (me) return me; } catch { /* fall through */ }
  return new Promise(resolve => {
    root.innerHTML = `
      <div class="login-wrap">
        <form class="login card" novalidate>
          <img src="assets/logo-purple.png" alt="Açaí Dose">
          <h1 class="lal">${esc(title)}</h1>
          <div class="field"><label for="un">${en ? 'Username' : 'اسم المستخدم'}</label><input id="un" autocomplete="username" autocapitalize="off" dir="ltr" required></div>
          <div class="field"><label for="pw">${en ? 'Password' : 'كلمة السر'}</label><input id="pw" type="password" autocomplete="current-password" required></div>
          <div class="err" id="lerr" role="alert"></div>
          <button class="btn" id="go" type="submit">${en ? 'Log in' : 'تسجيل الدخول'}</button>
        </form>
      </div>`;
    $('form', root).onsubmit = async e => {
      e.preventDefault();
      const err = $('#lerr', root), go = $('#go', root);
      err.textContent = ''; go.disabled = true;
      try { resolve(await api('login', { username: $('#un', root).value.trim(), password: $('#pw', root).value })); }
      catch (ex) { err.textContent = en ? msgEn(ex) : msg(ex); go.disabled = false; }
    };
  });
}

export async function logout() { try { await api('logout', {}); } catch { /* ignore */ } location.reload(); }
