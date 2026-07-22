/**
 * PlayerController.ets - AVPlayer 封装
 *
 * 管理 AVPlayer 状态机（idle→initialized→prepared→playing…），
 * 对 UI 暴露：prepare/play/pause/seek/speed/循环/进度回调。
 * 网络源（WebDAV Basic Auth）通过带 header 的 MediaSource 流式播放。
 */
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoItem } from '../model/Models';

const TAG = 'PlayerController';

export interface PlayerCallbacks {
  onStateChanged: (state: string) => void;
  onProgress: (currentMs: number, durationMs: number) => void;
  onVideoSize: (width: number, height: number) => void;
  onError: (message: string) => void;
}

export class PlayerController {
  private player: media.AVPlayer | null = null;
  private callbacks: PlayerCallbacks | null = null;
  private surfaceId: string = '';
  durationMs: number = 0;
  currentMs: number = 0;

  setCallbacks(cb: PlayerCallbacks): void {
    this.callbacks = cb;
  }

  /**
   * 创建播放器并加载媒体。
   * item.authHeader 非空时用 MediaSource 携带请求头（WebDAV 鉴权）。
   */
  async open(item: VideoItem, surfaceId: string, startAtMs: number): Promise<void> {
    this.surfaceId = surfaceId;
    const player = await media.createAVPlayer();
    this.player = player;
    this.bindEvents(player, startAtMs);

    if (item.authHeader !== '' && item.uri.startsWith('http')) {
      const headers: Record<string, string> = { 'Authorization': item.authHeader };
      const source = media.createMediaSourceWithUrl(item.uri, headers);
      const strategy: media.PlaybackStrategy = {
        preferredBufferDuration: 4
      };
      player.setMediaSource(source, strategy);
    } else {
      player.url = item.uri;
    }
  }

  private bindEvents(player: media.AVPlayer, startAtMs: number): void {
    player.on('stateChange', async (state: string) => {
      hilog.info(0x0001, TAG, 'state: %{public}s', state);
      if (this.callbacks) {
        this.callbacks.onStateChanged(state);
      }
      switch (state) {
        case 'initialized':
          player.surfaceId = this.surfaceId;
          player.prepare();
          break;
        case 'prepared':
          this.durationMs = player.duration;
          if (startAtMs > 3000 && startAtMs < this.durationMs - 5000) {
            player.seek(startAtMs, media.SeekMode.SEEK_CLOSEST);
          }
          player.play();
          break;
        case 'completed':
          this.currentMs = this.durationMs;
          break;
        default:
          break;
      }
    });
    player.on('timeUpdate', (timeMs: number) => {
      this.currentMs = timeMs;
      if (this.callbacks) {
        this.callbacks.onProgress(timeMs, this.durationMs);
      }
    });
    player.on('videoSizeChange', (w: number, h: number) => {
      if (this.callbacks) {
        this.callbacks.onVideoSize(w, h);
      }
    });
    player.on('error', (err: BusinessError) => {
      hilog.error(0x0001, TAG, 'player error: %{public}s', JSON.stringify(err));
      if (this.callbacks) {
        this.callbacks.onError(`播放失败 (${err.code})`);
      }
    });
  }

  isPlaying(): boolean {
    return this.player !== null && this.player.state === 'playing';
  }

  async play(): Promise<void> {
    if (this.player && (this.player.state === 'paused' || this.player.state === 'prepared'
      || this.player.state === 'completed')) {
      await this.player.play();
    }
  }

  async pause(): Promise<void> {
    if (this.player && this.player.state === 'playing') {
      await this.player.pause();
    }
  }

  seek(ms: number): void {
    if (this.player) {
      const target = Math.max(0, Math.min(ms, this.durationMs));
      this.player.seek(target, media.SeekMode.SEEK_CLOSEST);
    }
  }

  setSpeed(speed: number): void {
    if (!this.player) {
      return;
    }
    // AVPlayer 的枚举速度档
    let mode = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (speed === 0.75) {
      mode = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    } else if (speed === 1.25) {
      mode = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    } else if (speed === 1.5) {
      mode = media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    } else if (speed === 2) {
      mode = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    }
    this.player.setSpeed(mode);
  }

  setLoop(loop: boolean): void {
    if (this.player) {
      this.player.loop = loop;
    }
  }

  async release(): Promise<void> {
    if (this.player) {
      try {
        this.player.off('stateChange');
        this.player.off('timeUpdate');
        this.player.off('videoSizeChange');
        this.player.off('error');
        await this.player.release();
      } catch (e) {
        // ignore
      }
      this.player = null;
    }
  }
}
