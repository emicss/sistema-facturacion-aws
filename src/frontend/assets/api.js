const sessionKey = 'cloudtech.session';
export const session = () => JSON.parse(sessionStorage.getItem(sessionKey) || 'null');
export const signIn = data => sessionStorage.setItem(sessionKey, JSON.stringify(data));
export function signOut() {
  sessionStorage.removeItem(sessionKey);
  window.dispatchEvent(new Event('session-ended'));
}

let base;
export async function request(path, method = 'GET', body, key) {
  if (base === undefined) {
    const response = await fetch(new URL('./config.json', import.meta.url));
    if (!response.ok) throw new Error('No se pudo cargar la configuración.');
    const config = await response.json();
    const url = new URL(config.apiBase || location.origin);
    if (url.protocol !== 'https:' && !['localhost','127.0.0.1','[::1]'].includes(url.hostname))
      throw new Error('La conexión a la API requiere HTTPS.');
    base = url.href.replace(/\/$/, '');
  }
  const token = path !== '/auth/login' && session()?.access_token;
  const headers = {Accept:'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  if (key) headers['Idempotency-Key'] = key;
  if (body) headers['Content-Type'] = 'application/json';
  let response;
  try {
    response = await fetch(base + path, {method, headers, body:JSON.stringify(body)});
  } catch {
    throw new Error('No se recibió respuesta de la API. Comprueba la conexión.');
  }
  if (response.status === 401 && token && token === session()?.access_token) signOut();
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = result?.detail;
    const message = Array.isArray(detail) ? detail.map(x => x.msg).join('. ') : detail;
    throw Object.assign(new Error(message || 'Error HTTP ' + response.status), {status:response.status});
  }
  if (!result) throw new Error('La respuesta de la API está incompleta.');
  return result;
}

// Keep the original request across lost responses, navigation and reloads.
const pendingKey = () => 'cloudtech.pending.' + session().usuario.id_usuario;
export const pending = () => JSON.parse(sessionStorage.getItem(pendingKey()) || 'null');
export async function transact(path, body) {
  const storage = pendingKey();
  let intent = pending();
  if (intent && (intent.path !== path || JSON.stringify(intent.body) !== JSON.stringify(body)))
    throw new Error('Resuelve la operación pendiente antes de iniciar otra.');
  if (!intent) {
    intent = {path, body, key:crypto.randomUUID()};
    sessionStorage.setItem(storage, JSON.stringify(intent));
  }
  try {
    const result = await request(path, 'POST', body, intent.key);
    sessionStorage.removeItem(storage);
    return result;
  } catch (error) {
    if ([400,403,404,422].includes(error.status)) sessionStorage.removeItem(storage);
    throw error;
  }
}

export async function catalog() {
  const rows = [];
  for (;;) {
    const {servicios} = await request('/servicios?limit=100&offset=' + rows.length);
    rows.push(...servicios);
    if (servicios.length < 100) return rows;
  }
}
