import { PrefStore } from './PrefStore';
import { BrowseFavorite, BrowseNetworkSource, BrowseSourceKind } from '../model/BrowseModels';

const PREF_KEY_BROWSE_FAVORITES = 'browse_favorites_json';
const PREF_KEY_BROWSE_NETWORK_SOURCES = 'browse_network_sources_json';

export async function loadBrowseFavorites(prefs: PrefStore): Promise<BrowseFavorite[]> {
  const raw = await prefs.getString(PREF_KEY_BROWSE_FAVORITES, '');
  if (raw === '') return [];
  try {
    return parseFavoritesJson(raw);
  } catch {
    return [];
  }
}

interface FavoriteJsonData {
  id: string;
  title: string;
  url: string;
  source: string;
  addedAtMs: number;
}

interface NetworkSourceJsonData {
  id: string;
  title: string;
  url: string;
  username: string;
  password: string;
  addedAtMs: number;
}

export async function saveBrowseFavorites(prefs: PrefStore, favorites: BrowseFavorite[]): Promise<void> {
  const items: FavoriteJsonData[] = favorites.map((f: BrowseFavorite) => ({
    id: f.id, title: f.title, url: f.url, source: f.source, addedAtMs: f.addedAtMs,
  } as FavoriteJsonData));
  const json = JSON.stringify(items);
  await prefs.putString(PREF_KEY_BROWSE_FAVORITES, json);
}

export async function addBrowseFavorite(prefs: PrefStore, favorite: BrowseFavorite): Promise<BrowseFavorite[]> {
  const current = await loadBrowseFavorites(prefs);
  if (current.some(f => f.url === favorite.url)) return current;
  const next = [...current, favorite];
  await saveBrowseFavorites(prefs, next);
  return next;
}

export async function removeBrowseFavorite(prefs: PrefStore, favoriteId: string): Promise<BrowseFavorite[]> {
  const current = await loadBrowseFavorites(prefs);
  const next = current.filter(f => f.id !== favoriteId);
  await saveBrowseFavorites(prefs, next);
  return next;
}

export async function loadBrowseNetworkSources(prefs: PrefStore): Promise<BrowseNetworkSource[]> {
  const raw = await prefs.getString(PREF_KEY_BROWSE_NETWORK_SOURCES, '');
  if (raw === '') return [];
  try {
    return parseNetworkSourcesJson(raw);
  } catch {
    return [];
  }
}

export async function saveBrowseNetworkSources(prefs: PrefStore, sources: BrowseNetworkSource[]): Promise<void> {
  const items: NetworkSourceJsonData[] = sources.map((s: BrowseNetworkSource) => ({
    id: s.id, title: s.title, url: s.url, username: s.username, password: s.password, addedAtMs: s.addedAtMs,
  } as NetworkSourceJsonData));
  const json = JSON.stringify(items);
  await prefs.putString(PREF_KEY_BROWSE_NETWORK_SOURCES, json);
}

export async function addBrowseNetworkSource(prefs: PrefStore, source: BrowseNetworkSource): Promise<BrowseNetworkSource[]> {
  const current = await loadBrowseNetworkSources(prefs);
  if (current.some(s => s.url === source.url)) return current;
  const next = [...current, source];
  await saveBrowseNetworkSources(prefs, next);
  return next;
}

export async function removeBrowseNetworkSource(prefs: PrefStore, sourceId: string): Promise<BrowseNetworkSource[]> {
  const current = await loadBrowseNetworkSources(prefs);
  const next = current.filter(s => s.id !== sourceId);
  await saveBrowseNetworkSources(prefs, next);
  return next;
}

function parseFavoritesJson(raw: string): BrowseFavorite[] {
  const arr = JSON.parse(raw) as Array<Record<string, string | number>>;
  return arr.map((obj: Record<string, string | number>) => {
    const fav: BrowseFavorite = {
      id: String(obj['id'] ?? ''),
      title: String(obj['title'] ?? ''),
      url: String(obj['url'] ?? ''),
      source: obj['source'] === 'LOCAL_FILE' ? BrowseSourceKind.LOCAL_FILE : BrowseSourceKind.NETWORK_URL,
      addedAtMs: Number(obj['addedAtMs'] ?? 0),
    };
    return fav;
  });
}

function parseNetworkSourcesJson(raw: string): BrowseNetworkSource[] {
  const arr = JSON.parse(raw) as Array<Record<string, string | number>>;
  return arr.map((obj: Record<string, string | number>) => {
    const src: BrowseNetworkSource = {
      id: String(obj['id'] ?? ''),
      title: String(obj['title'] ?? ''),
      url: String(obj['url'] ?? ''),
      username: String(obj['username'] ?? ''),
      password: String(obj['password'] ?? ''),
      addedAtMs: Number(obj['addedAtMs'] ?? 0),
    };
    return src;
  });
}

export function applyAuthToUrl(url: string, username: string, password: string): string {
  if (username === '' && password === '') return url;
  const schemeIdx = url.indexOf('://');
  if (schemeIdx < 0) return url;
  const scheme = url.substring(0, schemeIdx + 3);
  const rest = url.substring(schemeIdx + 3);
  if (rest.includes('@')) return url;
  const userInfo = password !== '' ? `${username}:${password}@` : `${username}@`;
  return `${scheme}${userInfo}${rest}`;
}
