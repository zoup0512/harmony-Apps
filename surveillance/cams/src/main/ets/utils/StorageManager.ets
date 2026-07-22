import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { RecordingFile, createRecordingFile } from '../model/RecordingFile';

export class StorageManager {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  getBaseDirectoryPath(): string {
    return this.context.filesDir;
  }

  getRecordingDirectoryPath(): string {
    const dir = `${this.getBaseDirectoryPath()}/recordings`;
    try {
      fileIo.accessSync(dir);
    } catch {
      try {
        fileIo.mkdirSync(dir, true);
      } catch (e) {
        console.error(`StorageManager mkdir failed: ${(e as Error).message}`);
      }
    }
    return dir;
  }

  getSnapshotDirectoryPath(rootPath?: string): string {
    const baseDir = rootPath && rootPath.trim() !== '' ? rootPath : this.getBaseDirectoryPath();
    const dir = `${baseDir}/snapshot`;
    try {
      fileIo.accessSync(dir);
    } catch {
      try {
        fileIo.mkdirSync(dir, true);
      } catch (e) {
        console.error(`StorageManager mkdir failed: ${(e as Error).message}`);
      }
    }
    return dir;
  }

  getAllRecordings(): RecordingFile[] {
    const result: RecordingFile[] = [];
    const dir = this.getRecordingDirectoryPath();
    try {
      const files = fileIo.listFileSync(dir);
      for (const fileName of files) {
        const filePath = `${dir}/${fileName}`;
        try {
          const stat = fileIo.statSync(filePath);
          if (stat.isDirectory()) continue;
          const cameraName = fileName.includes('_')
            ? fileName.substring(0, fileName.lastIndexOf('_'))
            : fileName.replace(/\.[^.]+$/, '');
          result.push(createRecordingFile(
            '',
            fileName,
            filePath,
            stat.size,
            stat.mtime * 1000,
            null,
            '',
            cameraName,
          ));
        } catch {
          // skip
        }
      }
    } catch {
      // dir not exist
    }
    result.sort((a, b) => (b.startTime ?? 0) - (a.startTime ?? 0));
    return result;
  }

  getAllSnapshots(rootPath?: string): RecordingFile[] {
    const result: RecordingFile[] = [];
    const dir = this.getSnapshotDirectoryPath(rootPath);
    this.walkSnapshots(dir, result);
    result.sort((a, b) => (b.startTime ?? 0) - (a.startTime ?? 0));
    return result;
  }

  private walkSnapshots(dirPath: string, result: RecordingFile[]) {
    try {
      const files = fileIo.listFileSync(dirPath);
      for (const fileName of files) {
        const filePath = `${dirPath}/${fileName}`;
        try {
          const stat = fileIo.statSync(filePath);
          if (stat.isDirectory()) {
            this.walkSnapshots(filePath, result);
          } else {
            const ext = fileName.split('.').pop()?.toLowerCase() ?? '';
            if (['png', 'jpg', 'jpeg', 'webp'].includes(ext)) {
              const cameraName = fileName.includes('_')
                ? fileName.substring(0, fileName.lastIndexOf('_'))
                : fileName.replace(/\.[^.]+$/, '');
              result.push(createRecordingFile(
                '',
                fileName,
                filePath,
                stat.size,
                stat.mtime * 1000,
                null,
                '',
                cameraName,
              ));
            }
          }
        } catch {
          // skip
        }
      }
    } catch {
      // dir not exist
    }
  }

  deleteFile(filePath: string): boolean {
    try {
      fileIo.unlinkSync(filePath);
      return true;
    } catch (e) {
      console.error(`StorageManager deleteFile failed: filePath='${filePath}', error=${(e as Error).message}`);
      return false;
    }
  }
}
