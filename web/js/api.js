// Talks to the Python back end. Every failure becomes an ApiError whose
// `message` is the sentence to show the user and whose `code` identifies it.

export class ApiError extends Error {
  constructor(status, error) {
    super(error?.message || `Request failed (${status})`);
    this.status = status;
    this.code = error?.code || 'error';
    this.data = error || {};
  }
}

let onSignedOut = () => {};
export const setSignedOutHandler = (fn) => { onSignedOut = fn; };

async function request(method, path, { json, form, query, raw = false } = {}) {
  const url = query ? `${path}?${new URLSearchParams(query)}` : path;
  const options = { method, headers: { 'X-Requested-With': 'duka' }, credentials: 'same-origin' };
  if (json !== undefined) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(json);
  } else if (form) {
    options.body = form;
  }

  let response;
  try {
    response = await fetch(url, options);
  } catch {
    throw new ApiError(0, { code: 'offline', message: "Can't reach the till's server. Check that it is running and try again." });
  }

  if (response.ok) {
    if (raw) return response;
    const type = response.headers.get('content-type') || '';
    return type.includes('application/json') ? response.json() : response;
  }

  let error = null;
  try { error = (await response.json()).error; } catch { /* not JSON */ }
  const failure = new ApiError(response.status, error);
  if (response.status === 401 && failure.code === 'not_signed_in') onSignedOut();
  throw failure;
}

export const api = {
  get: (path, query) => request('GET', path, { query }),
  post: (path, json = {}) => request('POST', path, { json }),
  put: (path, json = {}) => request('PUT', path, { json }),
  del: (path) => request('DELETE', path),
  upload: (path, form) => request('POST', path, { form }),
};

/** Saves a file the server produced (CSV / PDF / backup) through the browser. */
export async function download(path, query) {
  const response = await request('GET', path, { query, raw: true });
  const disposition = response.headers.get('content-disposition') || '';
  const match = /filename="?([^";]+)"?/.exec(disposition);
  const blob = await response.blob();
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = match ? match[1] : 'download';
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
  return blob;
}
