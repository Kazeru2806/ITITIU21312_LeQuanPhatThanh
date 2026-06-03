/** VM / LAN defaults — browser on Mac, services on Ubuntu VM at 192.168.64.2 */
const DEFAULT_BACKEND_HOST = '192.168.64.2';
const DEFAULT_BACKEND_PORT = '4000';

export function getBackendHost(): string {
  const fromEnv = import.meta.env.VITE_BACKEND_HOST?.trim();
  if (fromEnv) return fromEnv;

  const pageHost = typeof window !== 'undefined' ? window.location.hostname : '';
  if (pageHost && pageHost !== 'localhost' && pageHost !== '127.0.0.1') {
    return pageHost;
  }

  return DEFAULT_BACKEND_HOST;
}

export function getBackendPort(): string {
  return import.meta.env.VITE_BACKEND_PORT?.trim() || DEFAULT_BACKEND_PORT;
}

export function getApiBaseUrl(): string {
  const explicit = import.meta.env.VITE_API_URL?.trim();
  if (explicit) return explicit.replace(/\/+$/, '');

  const protocol =
    typeof window !== 'undefined' && window.location.protocol === 'https:'
      ? 'https'
      : 'http';
  return `${protocol}://${getBackendHost()}:${getBackendPort()}/api`;
}

export function getWsUrl(): string {
  const explicit = import.meta.env.VITE_WS_URL?.trim();
  if (explicit) return explicit;

  const protocol =
    typeof window !== 'undefined' && window.location.protocol === 'https:'
      ? 'wss'
      : 'ws';
  return `${protocol}://${getBackendHost()}:${getBackendPort()}/socket`;
}
