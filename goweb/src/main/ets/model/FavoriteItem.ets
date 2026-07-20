export interface QuickLink {
  title: string;
  url: string;
}

export interface FavoriteItem {
  id: string;
  title: string;
  url: string;
  icon?: string;
  createTime: number;
}

export interface DownloadRecord {
  fileName: string;
  url: string;
  localPath: string;
  size: number;
  status: 'downloading' | 'completed' | 'failed';
  progress: number;
  createTime: number;
}
