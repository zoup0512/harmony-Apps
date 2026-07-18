export interface RecordingFile {
  id: string;
  fileName: string;
  filePath: string;
  fileSize: number;
  startTime: number | null;
  endTime: number | null;
  cameraId: string;
  cameraName: string;
}

export function createRecordingFile(
  id: string = '',
  fileName: string = '',
  filePath: string = '',
  fileSize: number = 0,
  startTime: number | null = null,
  endTime: number | null = null,
  cameraId: string = '',
  cameraName: string = '',
): RecordingFile {
  return { id, fileName, filePath, fileSize, startTime, endTime, cameraId, cameraName };
}

export function readableFileSize(fileSize: number): string {
  if (fileSize <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const digitGroups = Math.floor(Math.log10(fileSize) / Math.log10(1024));
  const safeIndex = Math.min(digitGroups, units.length - 1);
  return `${(fileSize / Math.pow(1024, safeIndex)).toFixed(2)} ${units[safeIndex]}`;
}

export function durationSeconds(startTime: number | null, endTime: number | null): number {
  if (startTime == null || endTime == null) return 0;
  return Math.floor((endTime - startTime) / 1000);
}

export function readableDuration(startTime: number | null, endTime: number | null): string {
  const duration = durationSeconds(startTime, endTime);
  const hours = Math.floor(duration / 3600);
  const minutes = Math.floor((duration % 3600) / 60);
  const seconds = duration % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
