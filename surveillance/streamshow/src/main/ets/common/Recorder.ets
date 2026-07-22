/**
 * Recorder.ets - MJPEG 录像器
 *
 * 把取流客户端回调的原始 JPEG 帧顺序写入 .mjpeg 文件
 * （连续 JPEG 拼接，VLC/ffplay 可直接播放，ffmpeg 可转 mp4）。
 * 文件写入应用沙箱 filesDir/records/，落盘用同步写保证顺序。
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'Recorder';

export class Recorder {
  private fd: number = -1;
  private filePath: string = '';
  private frames: number = 0;
  private bytes: number = 0;
  private startAt: number = 0;

  isRecording(): boolean {
    return this.fd >= 0;
  }

  getFilePath(): string {
    return this.filePath;
  }

  getFrames(): number {
    return this.frames;
  }

  getSeconds(): number {
    return this.startAt > 0 ? Math.floor((Date.now() - this.startAt) / 1000) : 0;
  }

  /** 开始录像；返回文件路径，失败返回 '' */
  start(context: common.UIAbilityContext, channelName: string): string {
    try {
      const dir = context.filesDir + '/records';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
      const stamp = Recorder.timestamp();
      const safe = channelName.replace(/[^\w\u4e00-\u9fa5-]/g, '_');
      this.filePath = `${dir}/${safe}_${stamp}.mjpeg`;
      const file = fileIo.openSync(this.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.fd = file.fd;
      this.frames = 0;
      this.bytes = 0;
      this.startAt = Date.now();
      hilog.info(0x0001, TAG, 'recording to %{public}s', this.filePath);
      return this.filePath;
    } catch (e) {
      hilog.error(0x0001, TAG, 'start error: %{public}s', JSON.stringify(e));
      this.fd = -1;
      return '';
    }
  }

  /** 写入一帧（由取流客户端 rawListener 调用） */
  writeFrame(jpeg: Uint8Array): void {
    if (this.fd < 0) {
      return;
    }
    try {
      fileIo.writeSync(this.fd,
        jpeg.buffer.slice(jpeg.byteOffset, jpeg.byteOffset + jpeg.byteLength));
      this.frames++;
      this.bytes += jpeg.byteLength;
    } catch (e) {
      hilog.warn(0x0001, TAG, 'writeFrame error');
    }
  }

  /** 停止录像；返回摘要文本 */
  stop(): string {
    if (this.fd < 0) {
      return '';
    }
    try {
      fileIo.closeSync(this.fd);
    } catch (e) { /* ignore */
    }
    const secs = this.getSeconds();
    const mb = (this.bytes / (1024 * 1024)).toFixed(1);
    const summary = `已保存 ${this.frames} 帧 / ${secs}s / ${mb}MB`;
    this.fd = -1;
    this.startAt = 0;
    return summary;
  }

  private static timestamp(): string {
    const d = new Date();
    const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
      `_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  }
}
