import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { DownloadRecord } from '../model/FavoriteItem';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DownloadManager';

export class DownloadManager {
  private static instance: DownloadManager;
  private downloads: Map<string, DownloadRecord> = new Map();
  private context: Context | null = null;
  private listeners: Set<(records: DownloadRecord[]) => void> = new Set();

  private constructor() {}

  static getInstance(): DownloadManager {
    if (!DownloadManager.instance) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  init(context: Context): void {
    this.context = context;
  }

  addListener(cb: (records: DownloadRecord[]) => void): void {
    this.listeners.add(cb);
  }

  removeListener(cb: (records: DownloadRecord[]) => void): void {
    this.listeners.delete(cb);
  }

  private notifyListeners(): void {
    const records = Array.from(this.downloads.values());
    this.listeners.forEach(cb => cb(records));
  }

  getFileNameFromUrl(url: string, contentDisposition?: string): string {
    if (contentDisposition) {
      const match = contentDisposition.match(/filename\*?=['"]?(?:UTF-\d['"]*)?([^'";\r\n]+)/i);
      if (match && match[1]) {
        return decodeURIComponent(match[1].trim());
      }
    }
    try {
      const urlObj = url.split('?')[0];
      const parts = urlObj.split('/');
      const fileName = parts[parts.length - 1];
      if (fileName && fileName.length > 0) {
        return decodeURIComponent(fileName);
      }
    } catch {}
    return `download_${Date.now()}`;
  }

  async startDownload(url: string, contentDisposition?: string, mimeType?: string): Promise<void> {
    if (!this.context) {
      hilog.error(DOMAIN, TAG, 'Context not initialized');
      return;
    }

    const fileName = this.getFileNameFromUrl(url, contentDisposition);
    const downloadDir = `${this.context.filesDir}/downloads`;

    try {
      if (!fs.accessSync(downloadDir)) {
        fs.mkdirSync(downloadDir, true);
      }
    } catch {
      try {
        fs.mkdirSync(downloadDir, true);
      } catch {}
    }

    const filePath = `${downloadDir}/${fileName}`;
    const recordId = `${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;

    const record: DownloadRecord = {
      fileName: fileName,
      url: url,
      localPath: filePath,
      size: 0,
      status: 'downloading',
      progress: 0,
      createTime: Date.now()
    };
    this.downloads.set(recordId, record);
    this.notifyListeners();

    promptAction.showToast({ message: `开始下载: ${fileName}`, duration: 2000 });

    try {
      const task: request.DownloadTask = await request.downloadFile(this.context, {
        url: url,
        filePath: filePath
      });

      task.on('progress', (receivedSize: number, totalSize: number) => {
        const r = this.downloads.get(recordId);
        if (r) {
          r.size = totalSize;
          r.progress = totalSize > 0 ? Math.floor((receivedSize / totalSize) * 100) : 0;
          this.notifyListeners();
        }
      });

      task.on('complete', () => {
        const r = this.downloads.get(recordId);
        if (r) {
          r.status = 'completed';
          r.progress = 100;
          this.notifyListeners();
        }
        promptAction.showToast({ message: `下载完成: ${fileName}`, duration: 3000 });
      });

      task.on('fail', (err: number) => {
        const r = this.downloads.get(recordId);
        if (r) {
          r.status = 'failed';
          this.notifyListeners();
        }
        hilog.error(DOMAIN, TAG, `Download failed: ${err}`);
        promptAction.showToast({ message: `下载失败: ${fileName}`, duration: 3000 });
      });
    } catch (err) {
      const r = this.downloads.get(recordId);
      if (r) {
        r.status = 'failed';
        this.notifyListeners();
      }
      hilog.error(DOMAIN, TAG, `Download error: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: `下载失败: ${fileName}`, duration: 3000 });
    }
  }

  getDownloadRecords(): DownloadRecord[] {
    return Array.from(this.downloads.values());
  }
}
