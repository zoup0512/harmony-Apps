/**
 * StreamClient.ets - 取流客户端
 *
 * MjpegClient：HTTP 流式读取 multipart 字节流，按 JPEG 魔数（FFD8/FFD9）
 * 切帧解码为 PixelMap；同时把原始 JPEG 字节回调给录像器（如已开启）。
 * JpegPollClient：单帧快照轮询。
 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Channel } from '../model/Models';

const TAG = 'StreamClient';
const MAX_BUFFER = 4 * 1024 * 1024;

export type FrameListener = (pm: image.PixelMap) => void;
export type RawJpegListener = (jpeg: Uint8Array) => void;
export type ErrorListener = (message: string) => void;

export function basicAuth(ch: Channel): string {
  if (ch.username === '') {
    return '';
  }
  const bytes = new util.TextEncoder().encodeInto(`${ch.username}:${ch.password}`);
  return 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes);
}

export class MjpegClient {
  private req: http.HttpRequest | null = null;
  private buffer: Uint8Array = new Uint8Array(0);
  private onFrame: FrameListener | null = null;
  private onError: ErrorListener | null = null;
  /** 录像器挂钩：非空时每个完整 JPEG 原始字节都会回调 */
  rawListener: RawJpegListener | null = null;
  private decoding: boolean = false;
  private stopped: boolean = false;

  start(ch: Channel, onFrame: FrameListener, onError: ErrorListener): void {
    this.onFrame = onFrame;
    this.onError = onError;
    this.stopped = false;
    const req = http.createHttp();
    this.req = req;

    req.on('dataReceive', (data: ArrayBuffer) => {
      this.feed(new Uint8Array(data));
    });
    req.on('dataEnd', () => {
      if (!this.stopped && this.onError) {
        this.onError('连接已断开');
      }
    });

    const headers: Record<string, string> = {};
    const auth = basicAuth(ch);
    if (auth !== '') {
      headers['Authorization'] = auth;
    }
    req.requestInStream(ch.url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 8000,
      readTimeout: 0
    }).then((code: number) => {
      if (code !== 200 && !this.stopped && this.onError) {
        this.onError(`HTTP ${code}`);
      }
    }).catch((e: Object) => {
      hilog.error(0x0001, TAG, 'stream error: %{public}s', JSON.stringify(e));
      if (!this.stopped && this.onError) {
        this.onError('连接失败');
      }
    });
  }

  stop(): void {
    this.stopped = true;
    if (this.req) {
      try {
        this.req.off('dataReceive');
        this.req.off('dataEnd');
        this.req.destroy();
      } catch (e) { /* ignore */
      }
      this.req = null;
    }
    this.buffer = new Uint8Array(0);
    this.rawListener = null;
  }

  private feed(chunk: Uint8Array): void {
    if (this.stopped) {
      return;
    }
    const merged = new Uint8Array(this.buffer.length + chunk.length);
    merged.set(this.buffer, 0);
    merged.set(chunk, this.buffer.length);
    this.buffer = merged;

    if (this.buffer.length > MAX_BUFFER) {
      this.buffer = new Uint8Array(0);
      return;
    }
    while (true) {
      const soi = MjpegClient.indexOfMarker(this.buffer, 0xFF, 0xD8, 0);
      if (soi < 0) {
        if (this.buffer.length > 1) {
          this.buffer = this.buffer.subarray(this.buffer.length - 1);
        }
        return;
      }
      const eoi = MjpegClient.indexOfMarker(this.buffer, 0xFF, 0xD9, soi + 2);
      if (eoi < 0) {
        if (soi > 0) {
          this.buffer = this.buffer.subarray(soi);
        }
        return;
      }
      const frame = this.buffer.slice(soi, eoi + 2);
      this.buffer = this.buffer.subarray(eoi + 2);
      if (this.rawListener !== null) {
        this.rawListener(frame);
      }
      this.decode(frame);
    }
  }

  private static indexOfMarker(buf: Uint8Array, b0: number, b1: number, from: number): number {
    for (let i = from; i < buf.length - 1; i++) {
      if (buf[i] === b0 && buf[i + 1] === b1) {
        return i;
      }
    }
    return -1;
  }

  private async decode(frame: Uint8Array): Promise<void> {
    if (this.decoding || this.stopped) {
      return;
    }
    this.decoding = true;
    try {
      const source = image.createImageSource(frame.buffer.slice(frame.byteOffset,
        frame.byteOffset + frame.byteLength));
      const pm = await source.createPixelMap();
      source.release();
      if (!this.stopped && this.onFrame) {
        this.onFrame(pm);
      } else {
        pm.release();
      }
    } catch (e) {
      // 坏帧忽略
    } finally {
      this.decoding = false;
    }
  }
}

export class JpegPollClient {
  private timer: number = -1;
  private busy: boolean = false;
  private stopped: boolean = false;
  rawListener: RawJpegListener | null = null;

  start(ch: Channel, onFrame: FrameListener, onError: ErrorListener): void {
    this.stopped = false;
    let failCount = 0;
    const tick = async (): Promise<void> => {
      if (this.busy || this.stopped) {
        return;
      }
      this.busy = true;
      const req = http.createHttp();
      try {
        const headers: Record<string, string> = {};
        const auth = basicAuth(ch);
        if (auth !== '') {
          headers['Authorization'] = auth;
        }
        const resp = await req.request(ch.url, {
          method: http.RequestMethod.GET,
          header: headers,
          connectTimeout: 5000,
          readTimeout: 8000,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        if (resp.responseCode === 200) {
          failCount = 0;
          const raw = new Uint8Array(resp.result as ArrayBuffer);
          if (this.rawListener !== null) {
            this.rawListener(raw);
          }
          const source = image.createImageSource(resp.result as ArrayBuffer);
          const pm = await source.createPixelMap();
          source.release();
          if (!this.stopped) {
            onFrame(pm);
          } else {
            pm.release();
          }
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      } finally {
        req.destroy();
        this.busy = false;
      }
      if (failCount >= 3 && !this.stopped) {
        onError('连续获取快照失败');
        failCount = 0;
      }
    };
    tick();
    this.timer = setInterval(tick, Math.max(300, ch.pollIntervalMs));
  }

  stop(): void {
    this.stopped = true;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.rawListener = null;
  }
}
