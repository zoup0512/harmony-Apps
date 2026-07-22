/**
 * StreamClient.ets - 取流客户端
 *
 * MjpegClient：HTTP 流式读取 multipart 字节流，按 JPEG 魔数（FFD8/FFD9）
 * 切帧解码为 PixelMap。
 * JpegPollClient：单帧快照轮询（列表缩略图与快照通道共用）。
 * fetchSnapshot：单次快照抓取（RTSP 通道截图 / 缩略图一次性刷新）。
 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Camera } from '../model/Models';

const TAG = 'StreamClient';
const MAX_BUFFER = 4 * 1024 * 1024;

export type FrameListener = (pm: image.PixelMap) => void;
export type ErrorListener = (message: string) => void;

export function basicAuthOf(username: string, password: string): string {
  if (username === '') {
    return '';
  }
  const bytes = new util.TextEncoder().encodeInto(`${username}:${password}`);
  return 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes);
}

/** 单次抓取快照并解码；失败返回 null。rawOut 非空时同时带回原始 JPEG 字节。 */
export async function fetchSnapshot(url: string, username: string, password: string,
  rawOut: Uint8Array[] | null = null): Promise<image.PixelMap | null> {
  if (url === '') {
    return null;
  }
  const req = http.createHttp();
  try {
    const headers: Record<string, string> = {};
    const auth = basicAuthOf(username, password);
    if (auth !== '') {
      headers['Authorization'] = auth;
    }
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 5000,
      readTimeout: 8000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    if (resp.responseCode !== 200) {
      return null;
    }
    if (rawOut !== null) {
      rawOut.push(new Uint8Array(resp.result as ArrayBuffer));
    }
    const source = image.createImageSource(resp.result as ArrayBuffer);
    const pm = await source.createPixelMap();
    source.release();
    return pm;
  } catch (e) {
    return null;
  } finally {
    req.destroy();
  }
}

export class MjpegClient {
  private req: http.HttpRequest | null = null;
  private buffer: Uint8Array = new Uint8Array(0);
  private onFrame: FrameListener | null = null;
  private onError: ErrorListener | null = null;
  private decoding: boolean = false;
  private stopped: boolean = false;

  start(cam: Camera, onFrame: FrameListener, onError: ErrorListener): void {
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
    const auth = basicAuthOf(cam.username, cam.password);
    if (auth !== '') {
      headers['Authorization'] = auth;
    }
    req.requestInStream(cam.url, {
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

  /** intervalOverrideMs > 0 时覆盖相机自身间隔（缩略图 5s 用） */
  start(cam: Camera, onFrame: FrameListener, onError: ErrorListener,
    intervalOverrideMs: number = 0): void {
    this.stopped = false;
    let failCount = 0;
    const url = cam.snapshotUrl !== '' ? cam.snapshotUrl : cam.url;
    const tick = async (): Promise<void> => {
      if (this.busy || this.stopped) {
        return;
      }
      this.busy = true;
      const pm = await fetchSnapshot(url, cam.username, cam.password);
      this.busy = false;
      if (this.stopped) {
        if (pm !== null) {
          pm.release();
        }
        return;
      }
      if (pm !== null) {
        failCount = 0;
        onFrame(pm);
      } else {
        failCount++;
        if (failCount >= 3) {
          onError('连续获取快照失败');
          failCount = 0;
        }
      }
    };
    tick();
    const interval = intervalOverrideMs > 0 ? intervalOverrideMs : Math.max(300, cam.pollIntervalMs);
    this.timer = setInterval(tick, interval);
  }

  stop(): void {
    this.stopped = true;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
