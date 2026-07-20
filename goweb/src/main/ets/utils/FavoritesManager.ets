import { preferences } from '@kit.ArkData';
import { FavoriteItem } from '../model/FavoriteItem';

const PREF_NAME = 'goweb_favorites';
const KEY_FAVORITES = 'favorites_list';

export class FavoritesManager {
  private static instance: FavoritesManager;
  private pref: preferences.Preferences | null = null;

  private constructor() {}

  static getInstance(): FavoritesManager {
    if (!FavoritesManager.instance) {
      FavoritesManager.instance = new FavoritesManager();
    }
    return FavoritesManager.instance;
  }

  async init(context: Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, PREF_NAME);
  }

  async getAllFavorites(): Promise<FavoriteItem[]> {
    if (!this.pref) {
      return [];
    }
    const raw = await this.pref.get(KEY_FAVORITES, '[]') as string;
    try {
      return JSON.parse(raw) as FavoriteItem[];
    } catch {
      return [];
    }
  }

  async addFavorite(title: string, url: string): Promise<boolean> {
    if (!this.pref) {
      return false;
    }
    const list = await this.getAllFavorites();
    const exists = list.some(item => item.url === url);
    if (exists) {
      return false;
    }
    const newItem: FavoriteItem = {
      id: `${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
      title: title,
      url: url,
      createTime: Date.now()
    };
    list.push(newItem);
    await this.pref.put(KEY_FAVORITES, JSON.stringify(list));
    await this.pref.flush();
    return true;
  }

  async removeFavorite(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    const list = await this.getAllFavorites();
    const filtered = list.filter(item => item.id !== id);
    await this.pref.put(KEY_FAVORITES, JSON.stringify(filtered));
    await this.pref.flush();
  }

  async updateFavorite(id: string, title: string, url: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    const list = await this.getAllFavorites();
    const item = list.find(i => i.id === id);
    if (item) {
      item.title = title;
      item.url = url;
      await this.pref.put(KEY_FAVORITES, JSON.stringify(list));
      await this.pref.flush();
    }
  }

  async isFavorite(url: string): Promise<boolean> {
    const list = await this.getAllFavorites();
    return list.some(item => item.url === url);
  }
}
