import { camera } from '@kit.CameraKit';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { objectDetection, visionBase } from '@kit.CoreVisionKit';
import { RtspServer } from './RtspServer';
import { RtmpPushManager, RtmpPushConfig, parseRtmpUrl, RtmpPushStatus } from './RtmpPushManager';
import { PHONE_RTSP_PORT } from './NetworkUtils';
import { rstr, rstrNum } from './I18nUtils';
import { createEncoder, startEncoder, stopEncoder, releaseEncoder, EncodedFrame,
  createAudioEncoder, startAudioEncoder, stopAudioEncoder, releaseAudioEncoder, setAudioEncoderMuted, AacFrame } from 'librtspencoder.so';

const TAG = 'CameraStreamManager';

export interface StreamStatus {
  isStreaming: boolean;
  isPreviewReady: boolean;
  isPreviewRunning: boolean;
  statusText: string;
  clientCount: number;
  personDetected: boolean;
  personEvents: PersonEventLog[];
  torchSupported: boolean;
  zoomMin: number;
  zoomMax: number;
  audioMuted: boolean;
}

export interface PersonEventLog {
  timestamp: number;
  confidence: number;
  bounds: string;
}

export interface VideoConfig {
  width: number;
  height: number;
  bitrate: number;
  framerate: number;
}

export class CameraStreamManager {
  private context: common.Context;
  private rtspServer: RtspServer;
  private rtmpPushManager: RtmpPushManager | null = null;
  private streamMode: 'rtsp' | 'rtmp' = 'rtsp';
  private rtmpConfig: RtmpPushConfig | null = null;
  private rtmpStatusText: string = '';
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private videoOutput: camera.VideoOutput | null = null;
  private session: camera.VideoSession | null = null;
  private encoderSurfaceId: string = '';
  private previewSurfaceId: string = '';
  private audioEncoderReady: boolean = false;
  private audioMuted: boolean = false;
  private useFrontCamera: boolean = false;
  private streaming: boolean = false;
  private previewReady: boolean = false;
  private statusCallback: ((status: StreamStatus) => void) | null = null;
  private personDetectionEnabled: boolean = false;
  private personEvents: PersonEventLog[] = [];
  private personDetected: boolean = false;
  private pausedForBackground: boolean = false;
  private imageReceiver: image.ImageReceiver | null = null;
  private detectionPreviewOutput: camera.PreviewOutput | null = null;
  private detector: objectDetection.ObjectDetector | null = null;
  private lastDetectionTimeMs: number = 0;
  private detectionThrottleMs: number = 1000;
  private imageArrivalCount: number = 0;

  private width: number = 640;
  private height: number = 480;
  private bitrate: number = 1_200_000;
  private framerate: number = 30;
  private torchSupported: boolean = false;
  private torchOn: boolean = false;
  private zoomRange: number[] = [1, 1];

  constructor(context: common.Context) {
    this.context = context;
    this.rtspServer = new RtspServer(PHONE_RTSP_PORT);
    this.rtspServer.setOnClientCountChange((count: number) => {
      this.notifyStatus();
    });
  }

  setStatusCallback(cb: (status: StreamStatus) => void): void {
    this.statusCallback = cb;
  }

  setStreamMode(mode: 'rtsp' | 'rtmp'): void {
    if (this.streaming) return;
    this.streamMode = mode;
    console.info(`${TAG} stream mode set to ${mode}`);
  }

  setRtmpConfig(url: string, streamKey: string, username: string, password: string): void {
    const parsed = parseRtmpUrl(url);
    this.rtmpConfig = {
      host: parsed.host,
      port: parsed.port,
      app: parsed.app,
      streamKey: streamKey,
      username: username,
      password: password,
    };
    console.info(`${TAG} RTMP config: host=${parsed.host}, port=${parsed.port}, app=${parsed.app}, key=${streamKey}`);
  }

  getVideoConfig(): VideoConfig {
    return { width: this.width, height: this.height, bitrate: this.bitrate, framerate: this.framerate };
  }

  setVideoConfig(width: number, height: number, bitrate: number, framerate: number): boolean {
    if (this.streaming) {
      console.warn(`${TAG} setVideoConfig: cannot change while streaming`);
      return false;
    }
    this.width = width;
    this.height = height;
    this.bitrate = bitrate;
    this.framerate = framerate;
    console.info(`${TAG} setVideoConfig: ${width}x${height} bitrate=${bitrate} fps=${framerate}`);
    return true;
  }

  setAudioMuted(muted: boolean): void {
    this.audioMuted = muted;
    setAudioEncoderMuted(muted);
    console.info(`${TAG} setAudioMuted: ${muted}`);
  }

  isAudioMuted(): boolean {
    return this.audioMuted;
  }

  private startAudio(): void {
    try {
      const result = createAudioEncoder(44100, 2, 128000, (frame: AacFrame) => {
        this.onAudioFrame(frame);
      });
      if (result === 'ok') {
        this.audioEncoderReady = true;
        setAudioEncoderMuted(this.audioMuted);
        startAudioEncoder();
        console.info(`${TAG} audio encoder started`);
      } else {
        console.warn(`${TAG} audio encoder create failed, streaming video-only`);
        this.audioEncoderReady = false;
      }
    } catch (e) {
      console.error(`${TAG} startAudio failed (degrading to video-only): ${(e as Error).message}`);
      this.audioEncoderReady = false;
    }
  }

  private stopAudio(): void {
    try {
      stopAudioEncoder();
    } catch (e) {
      console.warn(`${TAG} stopAudioEncoder error: ${(e as Error).message}`);
    }
    try {
      releaseAudioEncoder();
    } catch (e) {
      console.warn(`${TAG} releaseAudioEncoder error: ${(e as Error).message}`);
    }
    this.audioEncoderReady = false;
    console.info(`${TAG} audio encoder stopped/released`);
  }

  private onAudioFrame(frame: AacFrame): void {
    if (!this.streaming || this.audioMuted) return;
    const data = new Uint8Array(frame.data);
    if (this.streamMode === 'rtmp' && this.rtmpPushManager) {
      this.rtmpPushManager.sendAacData(data, frame.pts, frame.isConfig);
    } else {
      this.rtspServer.sendAacData(data, frame.pts, frame.isConfig);
    }
  }

  setPersonDetectionEnabled(enabled: boolean): void {
    this.personDetectionEnabled = enabled;
    console.info(`${TAG} setPersonDetectionEnabled: ${enabled}, streaming=${this.streaming}`);
    if (enabled) {
      this.initDetector().then(() => {
        console.info(`${TAG} setPersonDetectionEnabled: detector ready`);
      }).catch((e: Error) => {
        console.error(`${TAG} setPersonDetectionEnabled: initDetector failed: ${e.message}`);
      });
    } else {
      this.personDetected = false;
      this.destroyDetector().then(() => {
        console.info(`${TAG} setPersonDetectionEnabled: detector destroyed`);
      });
    }
    this.notifyStatus();
  }

  async initDetector(): Promise<void> {
    if (this.detector) {
      console.info(`${TAG} initDetector: detector already exists`);
      return;
    }
    try {
      console.info(`${TAG} initDetector: creating ObjectDetector...`);
      this.detector = await objectDetection.ObjectDetector.create();
      console.info(`${TAG} initDetector: ObjectDetector created`);
    } catch (e) {
      console.error(`${TAG} initDetector failed: ${(e as Error).message}`);
    }
  }

  async destroyDetector(): Promise<void> {
    if (this.detector) {
      try {
        await this.detector.destroy();
        console.info(`${TAG} destroyDetector: ObjectDetector destroyed`);
      } catch (e) {
        console.error(`${TAG} destroyDetector failed: ${(e as Error).message}`);
      }
      this.detector = null;
    }
  }

  getPersonEvents(): PersonEventLog[] {
    return this.personEvents;
  }

  isFrontCamera(): boolean {
    console.info(`${TAG} isFrontCamera() => ${this.useFrontCamera}`);
    return this.useFrontCamera;
  }

  isPreviewReady(): boolean {
    return this.previewReady;
  }

  hasTorchSupport(): boolean {
    return this.torchSupported;
  }

  isTorchOn(): boolean {
    return this.torchOn;
  }

  async setTorch(enabled: boolean): Promise<boolean> {
    const session = this.session;
    if (!session || !this.torchSupported) return false;
    try {
      const mode = enabled ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN : camera.FlashMode.FLASH_MODE_CLOSE;
      if (!session.isFlashModeSupported(mode)) {
        console.warn(`${TAG} setTorch: mode ${mode} not supported`);
        return false;
      }
      session.setFlashMode(mode);
      this.torchOn = enabled;
      console.info(`${TAG} setTorch: ${enabled}`);
      return true;
    } catch (e) {
      console.error(`${TAG} setTorch failed: ${(e as Error).message}`);
      return false;
    }
  }

  getZoomRange(): number[] {
    return this.zoomRange;
  }

  getZoomRatio(): number {
    const session = this.session;
    if (!session) return 1;
    try {
      return session.getZoomRatio();
    } catch (e) {
      console.warn(`${TAG} getZoomRatio failed: ${(e as Error).message}`);
      return 1;
    }
  }

  async setZoomRatio(ratio: number): Promise<number> {
    const session = this.session;
    if (!session) return 1;
    const min = this.zoomRange[0];
    const max = this.zoomRange[1];
    const clamped = Math.min(max, Math.max(min, ratio));
    try {
      session.setZoomRatio(clamped);
      console.info(`${TAG} setZoomRatio: ${clamped}`);
      return clamped;
    } catch (e) {
      console.error(`${TAG} setZoomRatio failed: ${(e as Error).message}`);
      return this.getZoomRatio();
    }
  }

  async restartPreview(): Promise<void> {
    console.info(`${TAG} restartPreview BEGIN`);
    if (this.streaming) {
      console.warn(`${TAG} restartPreview: cannot restart while streaming`);
      return;
    }
    if (this.session) {
      try { await this.session.stop(); } catch (e) {
        console.warn(`${TAG} restartPreview: session.stop() error: ${(e as Error).message}`);
      }
      try { this.session.release(); } catch (e) {
        console.warn(`${TAG} restartPreview: session.release() error: ${(e as Error).message}`);
      }
      this.session = null;
    }
    if (this.cameraInput) {
      try { this.cameraInput.close(); } catch (e) {
        console.warn(`${TAG} restartPreview: cameraInput.close() error: ${(e as Error).message}`);
      }
      this.cameraInput = null;
    }
    if (this.previewOutput) {
      try { this.previewOutput.release(); } catch (e) {
        console.warn(`${TAG} restartPreview: previewOutput.release() error: ${(e as Error).message}`);
      }
      this.previewOutput = null;
    }
    if (this.detectionPreviewOutput) {
      try { this.detectionPreviewOutput.release(); } catch (e) {
        console.warn(`${TAG} restartPreview: detectionPreviewOutput.release() error: ${(e as Error).message}`);
      }
      this.detectionPreviewOutput = null;
    }
    if (this.imageReceiver) {
      try { this.imageReceiver.release(); } catch (e) {
        console.warn(`${TAG} restartPreview: imageReceiver.release() error: ${(e as Error).message}`);
      }
      this.imageReceiver = null;
    }
    this.previewReady = false;
    console.info(`${TAG} restartPreview: old camera resources released, re-initializing...`);
    await this.initPreview(this.previewSurfaceId);
    console.info(`${TAG} restartPreview END: previewReady=${this.previewReady}`);
  }

  private previewPaused: boolean = false;

  isPreviewRunning(): boolean {
    return this.previewReady && !this.previewPaused;
  }

  /**
   * Pause the live camera preview (freeze the surface) without tearing down the
   * whole camera session, when supported. Falls back to session stop+start.
   * Must not be called while streaming (streaming requires preview running).
   */
  async pausePreview(): Promise<void> {
    if (this.streaming) {
      console.warn(`${TAG} pausePreview: ignored, streaming is active`);
      return;
    }
    if (this.previewPaused || !this.session) {
      return;
    }
    try {
      await this.session.stop();
      this.previewPaused = true;
      console.info(`${TAG} pausePreview: session stopped (preview frozen)`);
    } catch (e) {
      console.warn(`${TAG} pausePreview failed: ${(e as Error).message}`);
    }
  }

  /**
   * Resume the live camera preview after pausePreview().
   */
  async resumePreview(): Promise<void> {
    if (!this.previewPaused || !this.session) {
      return;
    }
    try {
      await this.session.start();
      this.previewPaused = false;
      console.info(`${TAG} resumePreview: session started (preview live)`);
    } catch (e) {
      console.warn(`${TAG} resumePreview failed, re-initializing preview: ${(e as Error).message}`);
      // Fallback: rebuild the whole preview session.
      await this.restartPreview();
      this.previewPaused = false;
    }
  }

  private notifyStatus(): void {
    if (this.statusCallback) {
      this.statusCallback(this.buildStatus(this.getStatusText()));
    }
  }

  private buildStatus(statusText: string): StreamStatus {
    const clientCount = this.streamMode === 'rtsp' ? this.rtspServer.getClientCount() : 0;
    return {
      isStreaming: this.streaming,
      isPreviewReady: this.previewReady,
      isPreviewRunning: this.previewReady && !this.previewPaused,
      statusText: statusText,
      clientCount: clientCount,
      personDetected: this.personDetected,
      personEvents: this.personEvents,
      torchSupported: this.torchSupported,
      zoomMin: this.zoomRange[0],
      zoomMax: this.zoomRange[1],
      audioMuted: this.audioMuted,
    };
  }

  private getStatusText(): string {
    if (this.streaming) {
      if (this.streamMode === 'rtmp') {
        if (this.rtmpPushManager && this.rtmpPushManager.isPublishing()) {
          return rstr(this.context, 'cam_status_rtmp_streaming');
        }
        return this.rtmpStatusText || rstr(this.context, 'cam_status_rtmp_connecting');
      }
      const count = this.rtspServer.getClientCount();
      if (count > 0) {
        return rstrNum(this.context, 'cam_status_streaming_clients', count);
      }
      return rstr(this.context, 'cam_status_streaming_waiting');
    }
    if (this.previewReady) {
      return rstr(this.context, 'cam_status_preview_ready');
    }
    return rstr(this.context, 'cam_status_not_started');
  }

  private async ensureCameraPermission(): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const uiContext = this.context as common.UIAbilityContext;
      const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
      console.info(`${TAG} ensureCameraPermission: requesting CAMERA permission...`);
      const result = await atManager.requestPermissionsFromUser(uiContext, permissions);
      console.info(`${TAG} ensureCameraPermission: request result authResults=${JSON.stringify(result.authResults)}`);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} ensureCameraPermission EXCEPTION: ${err.message}`);
      return false;
    }
  }

  private async ensureMicrophonePermission(): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const uiContext = this.context as common.UIAbilityContext;
      const permissions: Array<Permissions> = ['ohos.permission.MICROPHONE'];
      console.info(`${TAG} ensureMicrophonePermission: requesting MICROPHONE permission...`);
      const result = await atManager.requestPermissionsFromUser(uiContext, permissions);
      console.info(`${TAG} ensureMicrophonePermission: request result authResults=${JSON.stringify(result.authResults)}`);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} ensureMicrophonePermission EXCEPTION: ${err.message}`);
      return false;
    }
  }

  async initPreview(previewSurfaceId: string): Promise<void> {
    this.previewSurfaceId = previewSurfaceId;
    console.info(`${TAG} initPreview BEGIN: surfaceId=${previewSurfaceId}`);
    try {
      console.info(`${TAG} initPreview: checking camera permission...`);
      const hasPermission = await this.ensureCameraPermission();
      if (!hasPermission) {
        console.error(`${TAG} initPreview: CAMERA permission denied`);
        this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_need_camera_permission')));
        return;
      }
      console.info(`${TAG} initPreview: camera permission granted`);

      console.info(`${TAG} initPreview: getting CameraManager...`);
      this.cameraManager = camera.getCameraManager(this.context);
      console.info(`${TAG} initPreview: CameraManager obtained`);

      const cameras = this.cameraManager.getSupportedCameras();
      console.info(`${TAG} initPreview: found ${cameras.length} cameras`);
      if (cameras.length === 0) {
        console.error(`${TAG} initPreview: No cameras found`);
        this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_no_camera')));
        return;
      }

      const cameraDevice = this.useFrontCamera ? cameras[cameras.length - 1] : cameras[0];
      console.info(`${TAG} initPreview: selected camera index=${this.useFrontCamera ? cameras.length - 1 : 0}, id=${cameraDevice.cameraId}`);

      const outputCapability = this.cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_VIDEO);
      console.info(`${TAG} initPreview: previewProfiles count=${outputCapability.previewProfiles.length}, videoProfiles count=${outputCapability.videoProfiles.length}`);

      console.info(`${TAG} initPreview: creating CameraInput...`);
      this.cameraInput = this.cameraManager.createCameraInput(cameraDevice);
      console.info(`${TAG} initPreview: CameraInput created, opening...`);
      await this.cameraInput.open();
      console.info(`${TAG} initPreview: CameraInput opened`);

      const previewProfile = outputCapability.previewProfiles.find((p: camera.Profile) => {
        return p.size.width === this.width && p.size.height === this.height;
      }) ?? outputCapability.previewProfiles[0];
      console.info(`${TAG} initPreview: previewProfile size=${previewProfile.size.width}x${previewProfile.size.height}, format=${previewProfile.format}`);
      console.info(`${TAG} initPreview: creating PreviewOutput with surfaceId=${previewSurfaceId}...`);
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, previewSurfaceId);
      console.info(`${TAG} initPreview: PreviewOutput created`);

      // Create ImageReceiver for person detection (dual-channel preview)
      const detWidth = 320;
      const detHeight = 240;
      try {
        console.info(`${TAG} initPreview: creating ImageReceiver ${detWidth}x${detHeight}...`);
        this.imageReceiver = image.createImageReceiver(
          { width: detWidth, height: detHeight },
          image.ImageFormat.JPEG, 8);
        const receiverSurfaceId = await this.imageReceiver.getReceivingSurfaceId();
        console.info(`${TAG} initPreview: ImageReceiver surfaceId=${receiverSurfaceId}`);

        const detPreviewProfile = outputCapability.previewProfiles.find((p: camera.Profile) => {
          return p.size.width === detWidth && p.size.height === detHeight;
        }) ?? outputCapability.previewProfiles[0];
        this.detectionPreviewOutput = this.cameraManager.createPreviewOutput(detPreviewProfile, receiverSurfaceId);
        console.info(`${TAG} initPreview: detection PreviewOutput created`);

        this.imageReceiver.on('imageArrival', () => {
          this.imageArrivalCount++;
          if (this.imageArrivalCount % 100 === 1) {
            console.info(`${TAG} imageArrival callback #${this.imageArrivalCount}, detectionEnabled=${this.personDetectionEnabled}`);
          }
          this.onDetectionFrame();
        });
      } catch (e) {
        console.warn(`${TAG} initPreview: ImageReceiver creation failed (detection disabled): ${(e as Error).message}`);
        this.imageReceiver = null;
        this.detectionPreviewOutput = null;
      }

      console.info(`${TAG} initPreview: creating VideoSession...`);
      this.session = this.cameraManager.createSession(camera.SceneMode.NORMAL_VIDEO) as camera.VideoSession;
      console.info(`${TAG} initPreview: VideoSession created: ${this.session !== null}`);
      if (!this.session || !this.cameraInput || !this.previewOutput) {
        console.error(`${TAG} initPreview: Failed to create session/input/output: session=${this.session !== null}, input=${this.cameraInput !== null}, output=${this.previewOutput !== null}`);
        this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_session_failed')));
        return;
      }
      console.info(`${TAG} initPreview: beginConfig...`);
      this.session.beginConfig();
      console.info(`${TAG} initPreview: addInput...`);
      this.session.addInput(this.cameraInput);
      console.info(`${TAG} initPreview: addOutput(preview)...`);
      this.session.addOutput(this.previewOutput);
      if (this.detectionPreviewOutput) {
        console.info(`${TAG} initPreview: addOutput(detection preview)...`);
        this.session.addOutput(this.detectionPreviewOutput);
      }

      console.info(`${TAG} initPreview: commitConfig...`);
      await this.session.commitConfig();
      console.info(`${TAG} initPreview: commitConfig done, starting session...`);
      await this.session.start();
      console.info(`${TAG} initPreview: session started`);

      this.previewReady = true;
      this.torchOn = false;
      if (this.session) {
        try {
          this.torchSupported = this.session.hasFlash();
        } catch (e) {
          this.torchSupported = false;
          console.warn(`${TAG} initPreview: hasFlash() failed: ${(e as Error).message}`);
        }
        try {
          const range = this.session.getZoomRatioRange();
          this.zoomRange = (range && range.length >= 2) ? [range[0], range[1]] : [1, 1];
        } catch (e) {
          this.zoomRange = [1, 1];
          console.warn(`${TAG} initPreview: getZoomRatioRange() failed: ${(e as Error).message}`);
        }
      } else {
        this.torchSupported = false;
        this.zoomRange = [1, 1];
      }
      console.info(`${TAG} initPreview: torchSupported=${this.torchSupported}, zoomRange=[${this.zoomRange[0]},${this.zoomRange[1]}]`);
      this.notifyStatus();
      console.info(`${TAG} initPreview END: success`);
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} initPreview EXCEPTION: ${err.message}, stack=${err.stack}`);
      this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_preview_init_failed', err.message)));
    }
  }

  async startStream(): Promise<void> {
    if (this.streaming) return;
    console.info(`${TAG} startStream BEGIN`);
    if (!this.previewReady || !this.cameraManager || !this.session) {
      console.error(`${TAG} startStream ABORT: preview not ready (previewReady=${this.previewReady}, cameraManager=${this.cameraManager !== null}, session=${this.session !== null})`);
      this.streaming = false;
      this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_need_camera_permission')));
      return;
    }
    try {
      console.info(`${TAG} startStream: creating encoder ${this.width}x${this.height} bitrate=${this.bitrate} fps=${this.framerate}...`);
      this.encoderSurfaceId = createEncoder(this.width, this.height, this.bitrate, this.framerate,
        (frame: EncodedFrame) => {
          this.onEncodedFrame(frame);
        });
      console.info(`${TAG} startStream: encoder surfaceId=${this.encoderSurfaceId}`);

      if (!this.encoderSurfaceId) {
        console.error(`${TAG} startStream: Failed to create encoder, surfaceId is empty`);
        this.notifyStatus();
        return;
      }

      if (this.streamMode === 'rtmp') {
        console.info(`${TAG} startStream: RTMP mode, connecting to server...`);
        if (!this.rtmpConfig) {
          console.error(`${TAG} startStream: RTMP config not set`);
          this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_configure_rtmp')));
          return;
        }
        this.rtmpPushManager = new RtmpPushManager(this.context);
        this.rtmpPushManager.setContext(this.context);
        this.rtmpPushManager.setOnStatusChange((status: RtmpPushStatus, message?: string) => {
          if (message) this.rtmpStatusText = message;
          else this.rtmpStatusText = '';
          this.notifyStatus();
        });
        try {
          await this.rtmpPushManager.connect(this.rtmpConfig);
          console.info(`${TAG} startStream: RTMP connect initiated`);
        } catch (connectErr) {
          console.error(`${TAG} startStream: RTMP connect failed: ${(connectErr as Error).message}`);
          this.streaming = false;
          this.rtmpPushManager = null;
          this.notifyStatus();
          return;
        }
      } else {
        console.info(`${TAG} startStream: starting RTSP server...`);
        await this.rtspServer.start();
        console.info(`${TAG} startStream: RTSP server started`);
      }

      if (this.cameraManager && this.session) {
        console.info(`${TAG} startStream: creating VideoOutput...`);
        const cameras = this.cameraManager.getSupportedCameras();
        const cameraDevice = this.useFrontCamera ? cameras[cameras.length - 1] : cameras[0];
        const outputCapability = this.cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_VIDEO);

        const videoProfile = outputCapability.videoProfiles.find((p: camera.VideoProfile) => {
          return p.size.width === this.width && p.size.height === this.height;
        }) ?? outputCapability.videoProfiles[0];
        console.info(`${TAG} startStream: videoProfile size=${videoProfile.size.width}x${videoProfile.size.height}`);

        this.videoOutput = this.cameraManager.createVideoOutput(videoProfile, this.encoderSurfaceId);
        console.info(`${TAG} startStream: VideoOutput created`);

        console.info(`${TAG} startStream: stopping session before reconfig...`);
        try {
          await this.session.stop();
        } catch (stopErr) {
          console.warn(`${TAG} startStream: session.stop() failed (may already be stopped): ${(stopErr as Error).message}`);
        }
        console.info(`${TAG} startStream: session stopped, beginConfig...`);
        this.session.beginConfig();
        this.session.addOutput(this.videoOutput);
        await this.session.commitConfig();
        console.info(`${TAG} startStream: session reconfigured with video output, restarting...`);
        await this.session.start();
        console.info(`${TAG} startStream: session restarted`);

        this.videoOutput.start();
        console.info(`${TAG} startStream: videoOutput started`);
      } else {
        console.warn(`${TAG} startStream: cameraManager or session is null, skipping video output`);
      }

      console.info(`${TAG} startStream: starting encoder...`);
      startEncoder();
      console.info(`${TAG} startStream: encoder started`);

      // Audio: request mic permission and start the AAC pipeline (degrades to video-only on failure).
      const micGranted = await this.ensureMicrophonePermission();
      if (micGranted) {
        this.startAudio();
      } else {
        console.warn(`${TAG} startStream: MICROPHONE permission denied, streaming video-only`);
      }

      if (this.personDetectionEnabled) {
        await this.initDetector();
        console.info(`${TAG} startStream: person detection enabled`);
      } else {
        console.info(`${TAG} startStream: person detection NOT enabled`);
      }

      this.streaming = true;
      this.notifyStatus();
      console.info(`${TAG} startStream END: success`);
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} startStream EXCEPTION: ${err.message}, stack=${err.stack}`);
      this.statusCallback?.(this.buildStatus(rstr(this.context, 'cam_status_start_failed', err.message)));
    }
  }

  async stopStream(): Promise<void> {
    if (!this.streaming) return;
    try {
      this.streaming = false;
      this.pausedForBackground = false;

      this.personDetected = false;
      await this.destroyDetector();

      this.stopAudio();
      stopEncoder();

      if (this.videoOutput) {
        try { this.videoOutput.stop(); } catch (e) {
          console.warn(`${TAG} stopStream: videoOutput.stop() error: ${(e as Error).message}`);
        }
        if (this.session) {
          try {
            this.session.beginConfig();
            this.session.removeOutput(this.videoOutput);
            await this.session.commitConfig();
          } catch (e) {
            console.warn(`${TAG} stopStream: removeOutput error: ${(e as Error).message}`);
          }
        }
        try { this.videoOutput.release(); } catch (e) {
          console.warn(`${TAG} stopStream: videoOutput.release() error: ${(e as Error).message}`);
        }
        this.videoOutput = null;
      }

      releaseEncoder();
      if (this.streamMode === 'rtmp' && this.rtmpPushManager) {
        await this.rtmpPushManager.disconnect();
        this.rtmpPushManager = null;
      } else {
        await this.rtspServer.stop();
      }

      this.notifyStatus();
      console.info(`${TAG} Stream stopped`);
    } catch (e) {
      console.error(`${TAG} stopStream failed: ${(e as Error).message}`);
    }
  }

  async pauseStream(): Promise<void> {
    console.info(`${TAG} pauseStream BEGIN: streaming=${this.streaming}, pausedForBackground=${this.pausedForBackground}`);
    if (!this.streaming || this.pausedForBackground) {
      console.info(`${TAG} pauseStream: skipped (streaming=${this.streaming}, paused=${this.pausedForBackground})`);
      return;
    }
    try {
      this.pausedForBackground = true;

      this.personDetected = false;

      console.info(`${TAG} pauseStream: stopping encoder...`);
      stopEncoder();
      this.stopAudio();
      console.info(`${TAG} pauseStream: encoder stopped`);

      if (this.videoOutput) {
        console.info(`${TAG} pauseStream: stopping videoOutput...`);
        try { this.videoOutput.stop(); } catch (e) {
          console.warn(`${TAG} pauseStream: videoOutput.stop() error: ${(e as Error).message}`);
        }
        try {
          if (this.session) {
            this.session.beginConfig();
            this.session.removeOutput(this.videoOutput);
            await this.session.commitConfig();
          }
        } catch (e) {
          console.warn(`${TAG} pauseStream: removeOutput error (expected if session dead): ${(e as Error).message}`);
        }
        this.videoOutput.release();
        this.videoOutput = null;
        console.info(`${TAG} pauseStream: videoOutput released`);
      }

      console.info(`${TAG} pauseStream: releasing session/input/preview (will be dead in background)...`);
      if (this.session) {
        try { await this.session.stop(); } catch (e) {}
        try { this.session.release(); } catch (e) {}
        this.session = null;
      }
      if (this.cameraInput) {
        try { this.cameraInput.close(); } catch (e) {}
        this.cameraInput = null;
      }
      if (this.previewOutput) {
        try { this.previewOutput.release(); } catch (e) {}
        this.previewOutput = null;
      }
      if (this.detectionPreviewOutput) {
        try { this.detectionPreviewOutput.release(); } catch (e) {}
        this.detectionPreviewOutput = null;
      }
      if (this.imageReceiver) {
        try { this.imageReceiver.release(); } catch (e) {}
        this.imageReceiver = null;
      }
      this.previewReady = false;

      console.info(`${TAG} pauseStream: releasing encoder...`);
      releaseEncoder();
      console.info(`${TAG} pauseStream END: all camera resources released, RTSP server kept alive`);
    } catch (e) {
      console.error(`${TAG} pauseStream EXCEPTION: ${(e as Error).message}, stack=${(e as Error).stack}`);
    }
  }

  async resumeStream(): Promise<void> {
    console.info(`${TAG} resumeStream BEGIN: streaming=${this.streaming}, pausedForBackground=${this.pausedForBackground}`);
    if (!this.pausedForBackground) {
      console.info(`${TAG} resumeStream: skipped (not paused)`);
      return;
    }
    try {
      this.pausedForBackground = false;

      // Step 1: Recreate camera session (session/input/preview were released in pauseStream)
      console.info(`${TAG} resumeStream: re-initializing camera preview...`);
      await this.initPreview(this.previewSurfaceId);
      if (!this.session || !this.cameraInput || !this.previewOutput) {
        console.error(`${TAG} resumeStream: initPreview failed, cannot resume`);
        this.streaming = false;
        this.notifyStatus();
        return;
      }
      console.info(`${TAG} resumeStream: camera session recreated`);

      // Step 2: Create encoder
      console.info(`${TAG} resumeStream: creating encoder ${this.width}x${this.height}...`);
      this.encoderSurfaceId = createEncoder(this.width, this.height, this.bitrate, this.framerate,
        (frame: EncodedFrame) => {
          this.onEncodedFrame(frame);
        });
      console.info(`${TAG} resumeStream: encoder surfaceId=${this.encoderSurfaceId}`);

      if (!this.encoderSurfaceId) {
        console.error(`${TAG} resumeStream: Failed to create encoder, stopping stream`);
        this.streaming = false;
        this.notifyStatus();
        return;
      }

      // Step 3: Create video output and add to session
      console.info(`${TAG} resumeStream: getting camera list...`);
      const cameras = this.cameraManager!.getSupportedCameras();
      const cameraDevice = this.useFrontCamera ? cameras[cameras.length - 1] : cameras[0];
      const outputCapability = this.cameraManager!.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_VIDEO);
      const videoProfile = outputCapability.videoProfiles.find((p: camera.VideoProfile) => {
        return p.size.width === this.width && p.size.height === this.height;
      }) ?? outputCapability.videoProfiles[0];

      console.info(`${TAG} resumeStream: creating VideoOutput...`);
      this.videoOutput = this.cameraManager!.createVideoOutput(videoProfile, this.encoderSurfaceId);
      console.info(`${TAG} resumeStream: VideoOutput created`);

      console.info(`${TAG} resumeStream: stopping session to add video output...`);
      try { await this.session.stop(); } catch (e) {
        console.warn(`${TAG} resumeStream: session.stop() error: ${(e as Error).message}`);
      }
      console.info(`${TAG} resumeStream: reconfiguring session with video output...`);
      this.session.beginConfig();
      this.session.addOutput(this.videoOutput);
      await this.session.commitConfig();
      console.info(`${TAG} resumeStream: starting session...`);
      await this.session.start();
      console.info(`${TAG} resumeStream: starting videoOutput...`);
      this.videoOutput.start();
      console.info(`${TAG} resumeStream: session+videoOutput restarted`);

      // Step 4: Start encoder
      console.info(`${TAG} resumeStream: starting encoder...`);
      startEncoder();
      console.info(`${TAG} resumeStream: encoder started`);

      // Step 4b: Restart audio pipeline (permission already granted during initial startStream).
      this.startAudio();

      // Step 5: Re-enable person detection if needed
      if (this.personDetectionEnabled) {
        await this.initDetector();
        console.info(`${TAG} resumeStream: person detection re-enabled`);
      }

      console.info(`${TAG} resumeStream END: success`);
    } catch (e) {
      console.error(`${TAG} resumeStream EXCEPTION: ${(e as Error).message}, stack=${(e as Error).stack}`);
      this.streaming = false;
      this.notifyStatus();
    }
  }

  private async onDetectionFrame(): Promise<void> {
    if (!this.imageReceiver) {
      return;
    }

    const now = Date.now();
    const shouldDetect = this.personDetectionEnabled && this.detector &&
      (now - this.lastDetectionTimeMs >= this.detectionThrottleMs);

    if (!shouldDetect) {
      try {
        const imgObj = await this.imageReceiver.readNextImage();
        if (imgObj) {
          imgObj.release();
        }
      } catch (e) {
      }
      return;
    }

    this.lastDetectionTimeMs = now;
    console.info(`${TAG} onDetectionFrame: running detection, arrivalCount=${this.imageArrivalCount}`);

    try {
      const imgObj = await this.imageReceiver.readNextImage();
      if (!imgObj) {
        console.warn(`${TAG} onDetectionFrame: readNextImage returned null`);
        return;
      }

      const component = await imgObj.getComponent(image.ComponentType.JPEG);
      if (!component || !component.byteBuffer) {
        console.warn(`${TAG} onDetectionFrame: no JPEG component`);
        imgObj.release();
        return;
      }

      const imageSource = image.createImageSource(component.byteBuffer);
      const pixelMap = await imageSource.createPixelMap({
        desiredSize: { width: 320, height: 240 },
      });

      const request: visionBase.Request = {
        inputData: { pixelMap: pixelMap },
      };

      if (!this.detector) {
        imgObj.release();
        pixelMap.release();
        imageSource.release();
        return;
      }

      const response = await this.detector.process(request);
      imgObj.release();
      pixelMap.release();
      imageSource.release();

      const objCount = response?.objects?.length ?? 0;
      console.info(`${TAG} onDetectionFrame: detection result, objects=${objCount}`);

      if (objCount > 0) {
        for (const obj of response.objects) {
          const labels = obj.labels ?? [];
          console.info(`${TAG} onDetectionFrame: obj labels=${JSON.stringify(labels)}, score=${obj.score}`);
          const isPerson = labels.includes(13) || labels.includes(8) || labels.includes(5);
          if (isPerson) {
            this.onPersonDetected(now, obj.score, obj.boundingBox);
            break;
          }
        }
      }
    } catch (e) {
      console.error(`${TAG} onDetectionFrame error: ${(e as Error).message}`);
    }
  }

  private onPersonDetected(timestamp: number, confidence: number, bounds: visionBase.BoundingBox): void {
    const boundsStr = `(${bounds.left},${bounds.top}),${bounds.width}x${bounds.height}`;
    console.info(`${TAG} onPersonDetected: ts=${timestamp}, confidence=${confidence.toFixed(2)}, bounds=${boundsStr}`);

    const log: PersonEventLog = {
      timestamp: timestamp,
      confidence: confidence,
      bounds: boundsStr,
    };
    this.personEvents.unshift(log);
    if (this.personEvents.length > 50) {
      this.personEvents = this.personEvents.slice(0, 50);
    }
    this.personDetected = true;
    this.notifyStatus();

    this.rtspServer.broadcastNotification('person_detected',
      JSON.stringify({ timestamp, confidence: confidence.toFixed(2), bounds: boundsStr }));

    setTimeout(() => {
      this.personDetected = false;
      this.notifyStatus();
    }, 2000);
  }

  async switchCamera(): Promise<void> {
    console.info(`${TAG} switchCamera BEGIN: currentFront=${this.useFrontCamera}, streaming=${this.streaming}`);
    const oldFront = this.useFrontCamera;
    const newFront = !this.useFrontCamera;
    const wasStreaming = this.streaming;

    try {
      if (wasStreaming) {
        console.info(`${TAG} switchCamera: stopping stream...`);
        await this.stopStream();
      }

      // Release current preview
      console.info(`${TAG} switchCamera: releasing session/input/preview...`);
      if (this.session) {
        try { await this.session.stop(); } catch (e) {
          console.warn(`${TAG} switchCamera: session.stop() error: ${(e as Error).message}`);
        }
        try { this.session.release(); } catch (e) {
          console.warn(`${TAG} switchCamera: session.release() error: ${(e as Error).message}`);
        }
        this.session = null;
      }
      if (this.cameraInput) {
        try { this.cameraInput.close(); } catch (e) {
          console.warn(`${TAG} switchCamera: cameraInput.close() error: ${(e as Error).message}`);
        }
        this.cameraInput = null;
      }
      if (this.previewOutput) {
        try { this.previewOutput.release(); } catch (e) {
          console.warn(`${TAG} switchCamera: previewOutput.release() error: ${(e as Error).message}`);
        }
        this.previewOutput = null;
      }
      if (this.detectionPreviewOutput) {
        try { this.detectionPreviewOutput.release(); } catch (e) {
          console.warn(`${TAG} switchCamera: detectionPreviewOutput.release() error: ${(e as Error).message}`);
        }
        this.detectionPreviewOutput = null;
      }
      if (this.imageReceiver) {
        try { this.imageReceiver.release(); } catch (e) {
          console.warn(`${TAG} switchCamera: imageReceiver.release() error: ${(e as Error).message}`);
        }
        this.imageReceiver = null;
      }
      this.previewReady = false;
      console.info(`${TAG} switchCamera: old camera resources released`);

      this.useFrontCamera = newFront;

      // Re-init preview with new camera
      console.info(`${TAG} switchCamera: re-init preview with ${newFront ? 'front' : 'back'} camera...`);
      await this.initPreview(this.previewSurfaceId);
      if (!this.previewReady) {
        console.error(`${TAG} switchCamera: initPreview failed, reverting useFrontCamera to ${oldFront}`);
        this.useFrontCamera = oldFront;
        this.notifyStatus();
        return;
      }
      console.info(`${TAG} switchCamera: preview re-initialized, previewReady=${this.previewReady}`);

      if (wasStreaming) {
        console.info(`${TAG} switchCamera: restarting stream...`);
        await this.startStream();
      }

      this.notifyStatus();
      console.info(`${TAG} switchCamera END: success, useFrontCamera=${this.useFrontCamera}`);
    } catch (e) {
      console.error(`${TAG} switchCamera EXCEPTION: ${(e as Error).message}, stack=${(e as Error).stack}`);
      console.error(`${TAG} switchCamera: reverting useFrontCamera from ${newFront} back to ${oldFront}`);
      this.useFrontCamera = oldFront;
      this.notifyStatus();
      throw new Error(`switchCamera failed: ${(e as Error).message}`);
    }
  }

  private onEncodedFrame(frame: EncodedFrame): void {
    const data = new Uint8Array(frame.data);
    console.info(`${TAG} onEncodedFrame: size=${data.length}, pts=${frame.pts}, isKeyFrame=${frame.isKeyFrame}, flags=${frame.flags}`);
    this.parseAndSendNalu(data, frame.pts, frame.isKeyFrame);
  }

  private parseAndSendNalu(data: Uint8Array, pts: number, isKeyFrame: boolean): void {
    // Detect format: Annex-B (start codes 00 00 00 01 / 00 00 01) or AVCC (4-byte length prefix)
    const isAnnexB = (data.length >= 4 && data[0] === 0 && data[1] === 0 && data[2] === 0 && data[3] === 1) ||
                     (data.length >= 3 && data[0] === 0 && data[1] === 0 && data[2] === 1);

    if (isAnnexB) {
      this.parseAnnexBNalu(data, pts, isKeyFrame);
    } else {
      this.parseAvccNalu(data, pts, isKeyFrame);
    }
  }

  private parseAnnexBNalu(data: Uint8Array, pts: number, isKeyFrame: boolean): void {
    let offset = 0;
    while (offset < data.length) {
      // Find start code
      if (offset + 3 <= data.length && data[offset] === 0 && data[offset + 1] === 0 && data[offset + 2] === 1) {
        offset += 3;
      } else if (offset + 4 <= data.length && data[offset] === 0 && data[offset + 1] === 0 && data[offset + 2] === 0 && data[offset + 3] === 1) {
        offset += 4;
      } else {
        offset++;
        continue;
      }

      // Find next start code or end of data
      let end = offset;
      while (end < data.length) {
        if (end + 3 <= data.length && data[end] === 0 && data[end + 1] === 0 && data[end + 2] === 1) break;
        if (end + 4 <= data.length && data[end] === 0 && data[end + 1] === 0 && data[end + 2] === 0 && data[end + 3] === 1) break;
        end++;
      }

      if (end > offset) {
        const nalu = data.subarray(offset, end);
        const naluType = nalu.length > 0 ? nalu[0] & 0x1F : 0;
        console.info(`${TAG} NALU(Annex-B): type=${naluType}, len=${nalu.length}, isKeyFrame=${isKeyFrame}`);
        if (this.streamMode === 'rtmp' && this.rtmpPushManager) {
          this.rtmpPushManager.sendH264Data(nalu, pts);
        } else {
          this.rtspServer.sendH264Data(nalu, pts);
        }
        if (naluType === 7) {
          this.rtspServer.setSps(nalu);
          if (this.rtmpPushManager) this.rtmpPushManager.setSps(nalu);
        } else if (naluType === 8) {
          this.rtspServer.setPps(nalu);
          if (this.rtmpPushManager) this.rtmpPushManager.setPps(nalu);
        }
      }
      offset = end;
    }
  }

  private parseAvccNalu(data: Uint8Array, pts: number, isKeyFrame: boolean): void {
    let offset = 0;
    while (offset < data.length) {
      if (offset + 4 > data.length) break;

      const naluLength = (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
      offset += 4;

      if (naluLength <= 0 || offset + naluLength > data.length) break;

      const nalu = data.subarray(offset, offset + naluLength);
      const naluType = nalu.length > 0 ? nalu[0] & 0x1F : 0;
      console.info(`${TAG} NALU(AVCC): type=${naluType}, len=${naluLength}, isKeyFrame=${isKeyFrame}`);
      if (this.streamMode === 'rtmp' && this.rtmpPushManager) {
        this.rtmpPushManager.sendH264Data(nalu, pts);
      } else {
        this.rtspServer.sendH264Data(nalu, pts);
      }
      if (naluType === 7) {
        this.rtspServer.setSps(nalu);
        if (this.rtmpPushManager) this.rtmpPushManager.setSps(nalu);
      } else if (naluType === 8) {
        this.rtspServer.setPps(nalu);
        if (this.rtmpPushManager) this.rtmpPushManager.setPps(nalu);
      }

      offset += naluLength;
    }
  }

  async release(): Promise<void> {
    await this.stopStream();
    await this.destroyDetector();

    if (this.session) {
      this.session.release();
      this.session = null;
    }
    if (this.cameraInput) {
      this.cameraInput.close();
      this.cameraInput = null;
    }
    if (this.previewOutput) {
      this.previewOutput.release();
      this.previewOutput = null;
    }
    if (this.detectionPreviewOutput) {
      try { this.detectionPreviewOutput.release(); } catch (e) {}
      this.detectionPreviewOutput = null;
    }
    if (this.imageReceiver) {
      try { this.imageReceiver.release(); } catch (e) {}
      this.imageReceiver = null;
    }
    this.cameraManager = null;
    this.previewReady = false;
  }
}
