/**
 * CameraService.ets - 相机服务
 *
 * 职责：
 * 1. 打开相机，将预览输出到 XComponent 的 Surface（本地预览）；
 * 2. 同时向一个 ImageReceiver 输出预览帧，作为推流帧源；
 * 3. 对外提供 getLatestJpeg()：把最近一帧编码为 JPEG（按需，由推流器按帧率调用），
 *    避免每一帧都编码造成的 CPU 压力。
 *
 * 说明：预览帧通常为 YUV420，需转换为 PixelMap 再用 ImagePacker 打包为 JPEG。
 *      不同机型预览格式/行距(stride)可能不同，落地真机时以 CameraOutputCapability
 *      返回的实际 profile 为准，必要时按 stride 做行对齐裁剪。
 */
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { StreamConfig } from '../model/Models';

const TAG = 'CameraService';

export class CameraService {
  private cameraMgr: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private frameOutput: camera.PreviewOutput | null = null;
  private session: camera.PhotoSession | null = null;
  private receiver: image.ImageReceiver | null = null;

  private latestPixelMap: image.PixelMap | null = null;
  private packer: image.ImagePacker | null = null;
  private running: boolean = false;
  private config: StreamConfig = new StreamConfig();

  /**
   * 启动相机。previewSurfaceId 来自 UI 的 XComponent，用于本地预览。
   */
  async start(context: common.UIAbilityContext, previewSurfaceId: string, config: StreamConfig): Promise<boolean> {
    this.config = config;
    try {
      this.cameraMgr = camera.getCameraManager(context);
      const cameras = this.cameraMgr.getSupportedCameras();
      const target = this.pickCamera(cameras, config.useFront);
      if (!target) {
        hilog.error(0x0001, TAG, 'no camera found');
        return false;
      }

      // 输出能力（预览 profile）
      const capability = this.cameraMgr.getSupportedOutputCapability(target, camera.SceneMode.NORMAL_PHOTO);
      const profile = this.pickPreviewProfile(capability, config);

      // 本地预览输出
      this.previewOutput = this.cameraMgr.createPreviewOutput(profile, previewSurfaceId);

      // 推流帧输出：ImageReceiver
      this.receiver = image.createImageReceiver(
        { width: profile.size.width, height: profile.size.height },
        image.ImageFormat.JPEG, 4);
      const frameSurfaceId = await this.receiver.getReceivingSurfaceId();
      this.frameOutput = this.cameraMgr.createPreviewOutput(profile, frameSurfaceId);
      this.registerFrameListener();

      // 输入
      this.cameraInput = this.cameraMgr.createCameraInput(target);
      await this.cameraInput.open();

      // 会话
      this.session = this.cameraMgr.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session.beginConfig();
      this.session.addInput(this.cameraInput);
      this.session.addOutput(this.previewOutput);
      this.session.addOutput(this.frameOutput);
      await this.session.commitConfig();
      await this.session.start();

      this.packer = image.createImagePacker();
      this.running = true;
      hilog.info(0x0001, TAG, 'camera started %{public}s', profile.size.width + 'x' + profile.size.height);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0001, TAG, 'camera start error: %{public}s', JSON.stringify(err));
      await this.stop();
      return false;
    }
  }

  async stop(): Promise<void> {
    this.running = false;
    try {
      if (this.session) {
        await this.session.stop();
        await this.session.release();
        this.session = null;
      }
      if (this.cameraInput) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
      if (this.previewOutput) {
        await this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.frameOutput) {
        await this.frameOutput.release();
        this.frameOutput = null;
      }
      if (this.receiver) {
        this.receiver.off('imageArrival');
        await this.receiver.release();
        this.receiver = null;
      }
      if (this.latestPixelMap) {
        await this.latestPixelMap.release();
        this.latestPixelMap = null;
      }
      if (this.packer) {
        this.packer.release();
        this.packer = null;
      }
    } catch (e) {
      hilog.error(0x0001, TAG, 'camera stop error: %{public}s', JSON.stringify(e));
    }
  }

  /** 切换闪光灯/手电（推流补光） */
  setTorch(on: boolean): void {
    try {
      if (this.session && this.session.hasFlash()) {
        this.session.setFlashMode(on ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN : camera.FlashMode.FLASH_MODE_CLOSE);
      }
    } catch (e) {
      hilog.warn(0x0001, TAG, 'setTorch error');
    }
  }

  isRunning(): boolean {
    return this.running;
  }

  /**
   * 将最近一帧编码为 JPEG。由 MjpegStreamer 按目标帧率调用。
   * 返回 null 表示当前无可用帧。
   */
  async getLatestJpeg(): Promise<ArrayBuffer | null> {
    if (!this.running || this.latestPixelMap === null || this.packer === null) {
      return null;
    }
    try {
      const opts: image.PackingOption = { format: 'image/jpeg', quality: this.config.quality };
      return await this.packer.packing(this.latestPixelMap, opts);
    } catch (e) {
      hilog.error(0x0001, TAG, 'packing error: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  // ---------------- 内部 ----------------

  private registerFrameListener(): void {
    if (!this.receiver) {
      return;
    }
    this.receiver.on('imageArrival', () => {
      const recv = this.receiver;
      if (!recv) {
        return;
      }
      recv.readNextImage((err: BusinessError, img: image.Image) => {
        if (err || !img) {
          return;
        }
        img.getComponent(image.ComponentType.JPEG, async (compErr: BusinessError, comp: image.Component) => {
          if (!compErr && comp) {
            await this.updatePixelMap(comp.byteBuffer);
          }
          img.release();
        });
      });
    });
  }

  /** 用最新帧字节构造/更新 PixelMap（供打包）。此处按 JPEG 源解码为 PixelMap。 */
  private async updatePixelMap(buffer: ArrayBuffer): Promise<void> {
    try {
      const source = image.createImageSource(buffer);
      const pm = await source.createPixelMap();
      const old = this.latestPixelMap;
      this.latestPixelMap = pm;
      if (old) {
        await old.release();
      }
      source.release();
    } catch (e) {
      hilog.warn(0x0001, TAG, 'updatePixelMap error');
    }
  }

  private pickCamera(cameras: camera.CameraDevice[], useFront: boolean): camera.CameraDevice | null {
    const wanted = useFront ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
    for (const c of cameras) {
      if (c.cameraPosition === wanted) {
        return c;
      }
    }
    return cameras.length > 0 ? cameras[0] : null;
  }

  private pickPreviewProfile(cap: camera.CameraOutputCapability, config: StreamConfig): camera.Profile {
    const profiles = cap.previewProfiles;
    // 优先匹配所选分辨率，否则取最接近的
    let best = profiles[0];
    let bestDiff = Number.MAX_VALUE;
    for (const p of profiles) {
      const diff = Math.abs(p.size.width - config.resolution.width) +
        Math.abs(p.size.height - config.resolution.height);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }
    return best;
  }
}
