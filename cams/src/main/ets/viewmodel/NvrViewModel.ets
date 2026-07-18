import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo, Environment } from '@kit.CoreFileKit';
import { CameraDevice, createCameraDevice } from '../model/CameraDevice';
import { rstr, rstrNum } from '../utils/I18nUtils';
import { RecordingFile, createRecordingFile } from '../model/RecordingFile';
import { DatabaseHelper } from '../utils/DatabaseHelper';
import { StorageManager } from '../utils/StorageManager';
import { VideoStreamManager } from '../utils/VideoStreamManager';
import { PrefStore } from '../utils/PrefStore';
import { loadStreamConfig, StreamDefaultConfig } from '../utils/StreamConfig';
import {
  DeviceFlowStep, VerificationPreview, PlaybackStreamType,
  buildPlaybackUrl, defaultPlaybackPort, parsePlaybackUrl, sanitizePlaybackUrl,
  playbackStreamTypeFromScheme, playbackStreamTypeFromUrl,
  buildDeviceManageFormValue, emptyDeviceManageFormValue,
  copyCameraPreferences, clearCameraPreferences,
  enrichCameraRtspUrl, cameraBadge, DeviceManageFormValue, snapshotCameraKey,
} from '../utils/PlaybackModels';
import {
  NvrUiState, defaultUiState, NvrPlaybackState, NvrDeviceFormState,
  NvrSettingsState, defaultSettingsState, defaultDeviceFormState, defaultPlaybackState,
} from './NvrUiState';
import { AppearanceThemeState } from '../theme/NvrTheme';
import { checkCameraReachable, HealthCheckResult } from '../utils/CameraHealthChecker';

function safeShowToast(message: string): void {
  try {
    promptAction.openToast({ message });
  } catch (e) {
    console.error(`showToast failed: ${(e as Error).message}`);
  }
}

function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

export class NvrViewModel {
  private context: common.Context;
  dbHelper: DatabaseHelper;
  storageManager: StorageManager;
  streamManager: VideoStreamManager;
  prefs: PrefStore;

  cameras: CameraDevice[] = [];
  recordings: RecordingFile[] = [];
  snapshots: RecordingFile[] = [];
  filteredCameras: CameraDevice[] = [];
  cameraGroups: string[] = [];

  uiState: NvrUiState = defaultUiState();

  constructor(context: common.Context) {
    this.context = context;
    this.dbHelper = new DatabaseHelper(context);
    this.storageManager = new StorageManager(context);
    this.streamManager = VideoStreamManager.getInstance(context);
    this.prefs = new PrefStore(context);
  }

  async init(): Promise<void> {
    await this.dbHelper.init();
    await this.prefs.init();

    const streamConfig = await loadStreamConfig(this.context);

    const prefResults = await Promise.all([
      this.prefs.getString('storage_path', ''),
      this.prefs.getString('recording_quality', '1080p'),
      this.prefs.getString('recording_duration', '30'),
      this.prefs.getString('rtmp_push_url', streamConfig.rtmp.url),
      this.prefs.getString('rtmp_push_stream_key', streamConfig.rtmp.streamKey),
      this.prefs.getString('rtmp_push_username', streamConfig.rtmp.username),
      this.prefs.getString('rtmp_push_password', streamConfig.rtmp.password),
      this.prefs.getBoolean('rtmp_push_audio_enabled', true),
      this.prefs.getBoolean('rtmp_auto_stream', false),
      this.prefs.getString('appearance_theme_mode', 'light'),
      this.prefs.getBoolean('allow_background_playback', false),
      this.prefs.getBoolean('app_lock_enabled', false),
      this.prefs.getNumber('grid_columns', 1),
    ]);
    const savedStoragePath = prefResults[0] as string;
    const recordingQuality = prefResults[1] as string;
    const recordingDuration = prefResults[2] as string;
    const rtmpUrl = prefResults[3] as string;
    const rtmpStreamKey = prefResults[4] as string;
    const rtmpUsername = prefResults[5] as string;
    const rtmpPassword = prefResults[6] as string;
    const rtmpAudioEnabled = prefResults[7] as boolean;
    const rtmpAutoStreamEnabled = prefResults[8] as boolean;
    const appearanceThemeMode = prefResults[9] as string;
    const bgPlaybackEnabled = prefResults[10] as boolean;
    const appLockEnabled = prefResults[11] as boolean;
    const gridColumns = prefResults[12] as number;

    let defaultDocsPath: string;
    try {
      const userDocsDir = Environment.getUserDocumentDir();
      defaultDocsPath = `${userDocsDir}/cams/data`;
    } catch (e) {
      console.error(`Environment.getUserDocumentDir failed: ${(e as Error).message}`);
      defaultDocsPath = `${this.context.filesDir}/cams/data`;
    }
    const isFirstLaunch = !savedStoragePath || savedStoragePath.trim() === '';
    const initialStorage = savedStoragePath && savedStoragePath.trim() !== '' && savedStoragePath !== '/sdcard/NVR' && savedStoragePath.startsWith('/')
      ? savedStoragePath
      : defaultDocsPath;

    if (isFirstLaunch) {
      await this.prefs.putString('storage_path', defaultDocsPath);
      await this.ensureDefaultStorageMarker(defaultDocsPath);
    }

    this.uiState.settings = {
        storagePathInput: initialStorage,
        recordingQualityInput: recordingQuality,
        recordingDurationInput: recordingDuration,
        rtmpUrlInput: rtmpUrl,
        rtmpStreamKeyInput: rtmpStreamKey,
        rtmpUsernameInput: rtmpUsername,
        rtmpPasswordInput: rtmpPassword,
        rtmpAudioEnabled: rtmpAudioEnabled,
        rtmpAutoStreamEnabled: rtmpAutoStreamEnabled,
        appearanceThemeMode: appearanceThemeMode,
        bgPlaybackEnabled: bgPlaybackEnabled,
      };

    AppearanceThemeState.initFromPrefs(appearanceThemeMode);

    this.uiState.appLockEnabled = appLockEnabled;
    this.uiState.isAppLocked = appLockEnabled;
    this.uiState.gridColumns = gridColumns;

    await this.addDefaultCameraIfNeeded(streamConfig);
    await this.reloadCameras();
    this.reloadRecordings();
    this.reloadSnapshots();
  }

  private async addDefaultCameraIfNeeded(streamConfig?: StreamDefaultConfig): Promise<void> {
    try {
      const config = streamConfig ?? await loadStreamConfig(this.context);
      const hlsUrl = config.hls.url;
      const hlsName = config.hls.name;
      const cameras = await this.dbHelper.getAllCameras();
      console.info(`addDefaultCameraIfNeeded: existing cameras=${cameras.length}, hlsUrl=${hlsUrl}`);
      const exists = cameras.some(c => c.rtspUrl === hlsUrl);
      if (!exists) {
        const defaultCamera = createCameraDevice(generateUUID(), hlsName, hlsUrl);
        const added = await this.dbHelper.addCamera(defaultCamera);
        console.info(`addDefaultCameraIfNeeded: added default camera '${hlsName}' -> ${added}`);
      } else {
        console.info(`addDefaultCameraIfNeeded: default camera already exists`);
      }
    } catch (e) {
      console.error(`addDefaultCameraIfNeeded failed: ${(e as Error).message}`);
    }
  }

  async reloadCameras(): Promise<void> {
    const previousCameras = this.cameras;
    this.cameras = await this.dbHelper.getAllCameras();
    for (const cam of this.cameras) {
      const prev = previousCameras.find(p => p.id === cam.id);
      if (prev) {
        cam.isConnected = prev.isConnected;
        cam.connectionQuality = prev.connectionQuality;
        cam.lastSeen = prev.lastSeen;
      }
    }
    console.info(`reloadCameras: loaded ${this.cameras.length} cameras from DB`);
    await this.loadCameraCoverImages();
    this.updateFilteredCameras();
    console.info(`reloadCameras: filteredCameras=${this.filteredCameras.length}`);
    this.updateCameraGroups();
    if (this.uiState.selectedCameraIndex >= this.cameras.length) {
      this.uiState.selectedCameraIndex = 0;
    }
  }

  private updateFilteredCameras(): void {
    const query = this.uiState.searchQuery?.toLowerCase() ?? '';
    const filter = this.uiState.cameraFilter ?? 'all';
    this.filteredCameras = this.cameras.filter(c => {
      if (query && !c.name.toLowerCase().includes(query) && !c.rtspUrl.toLowerCase().includes(query)) {
        return false;
      }
      if (filter === 'online' && !c.isConnected) return false;
      if (filter === 'offline' && c.isConnected) return false;
      return true;
    });
  }

  private updateCameraGroups(): void {
    const groups = new Set<string>();
    for (const c of this.cameras) {
      if (c.group && c.group.trim() !== '') {
        groups.add(c.group.trim());
      }
    }
    this.cameraGroups = Array.from(groups).sort();
  }

  setSearchQuery(query: string): void {
    this.uiState.searchQuery = query;
    this.updateFilteredCameras();
  }

  setCameraFilter(filter: 'all' | 'online' | 'offline'): void {
    this.uiState.cameraFilter = filter;
    this.updateFilteredCameras();
  }

  async reorderCamera(fromIndex: number, toIndex: number): Promise<void> {
    if (fromIndex < 0 || fromIndex >= this.cameras.length) return;
    if (toIndex < 0 || toIndex >= this.cameras.length) return;
    const moved = this.cameras[fromIndex];
    const remaining = [...this.cameras];
    remaining.splice(fromIndex, 1);
    remaining.splice(toIndex, 0, moved);
    for (let i = 0; i < remaining.length; i++) {
      remaining[i].sortOrder = i;
      await this.dbHelper.updateCamera(remaining[i]);
    }
    this.cameras = remaining;
    this.updateFilteredCameras();
  }

  async setCameraGroup(cameraId: string, group: string): Promise<void> {
    const camera = this.cameras.find(c => c.id === cameraId);
    if (!camera) return;
    camera.group = group;
    await this.dbHelper.updateCamera(camera);
    this.updateCameraGroups();
    this.updateFilteredCameras();
  }

  private healthCheckRunning = false;
  private readonly healthCheckTimeoutMs = 3000;

  async checkCameraHealth(): Promise<void> {
    if (this.healthCheckRunning) {
      console.info('checkCameraHealth: already running, skipping');
      return;
    }
    this.healthCheckRunning = true;
    try {
      const playingCameraId = this.uiState.playback.playingCameraId;
      const camerasToCheck = this.cameras.filter(c => c.rtspUrl && c.rtspUrl.trim() !== '');
      for (const camera of camerasToCheck) {
        if (camera.rtspUrl === '') {
          camera.isConnected = false;
          camera.connectionQuality = 'unknown';
          continue;
        }
        if (camera.id === playingCameraId) {
          continue;
        }
        try {
          const result = await checkCameraReachable(camera, this.healthCheckTimeoutMs, this.context);
          if (result.reachable) {
            camera.isConnected = true;
            camera.lastSeen = Date.now();
            if (result.latencyMs < 500) {
              camera.connectionQuality = 'good';
            } else if (result.latencyMs < 1500) {
              camera.connectionQuality = 'fair';
            } else {
              camera.connectionQuality = 'poor';
            }
          } else {
            camera.isConnected = false;
            camera.connectionQuality = 'unknown';
          }
        } catch {
          camera.isConnected = false;
          camera.connectionQuality = 'unknown';
        }
      }
      this.updateFilteredCameras();
    } finally {
      this.healthCheckRunning = false;
    }
  }

  async reloadRecordings(): Promise<void> {
    this.recordings = this.storageManager.getAllRecordings();
  }

  async reloadSnapshots(): Promise<void> {
    const rootPath = this.resolveStorageRoot();
    this.snapshots = this.storageManager.getAllSnapshots(rootPath);
  }

  getCameraBadge(camera: CameraDevice): string {
    return cameraBadge(camera, '');
  }

  async getCameraBadgeAsync(camera: CameraDevice): Promise<string> {
    const vendor = await this.prefs.getString(`camera_vendor_${camera.id}`, '');
    return cameraBadge(camera, vendor);
  }

  /* Playback */
  async clearPlaybackState(): Promise<void> {
    if (this.uiState.playback.isRecording) {
      this.uiState.playback.isRecording = false;
    }
    await this.streamManager.stopStream();
    this.uiState.playback.playingCameraId = null;
    this.uiState.playback.pendingPlaybackCamera = null;
    this.uiState.playback.pendingPlaybackRequestId = 0;
    this.uiState.playback.adHocPlaybackCamera = null;
    this.uiState.playback.isVideoReady = false;
  }

  async saveExitCoverImage(cameraId: string): Promise<void> {
    console.info(`NvrViewModel saveExitCoverImage: BEGIN cameraId='${cameraId}'`);
    if (!cameraId) {
      console.warn(`NvrViewModel saveExitCoverImage: cameraId is empty, aborting`);
      return;
    }
    const pixelMap = await this.streamManager.captureSurfaceFrame();
    if (!pixelMap) {
      console.warn(`NvrViewModel saveExitCoverImage: no frame captured for cameraId='${cameraId}'`);
      return;
    }
    try {
      const coversDir = this.context.cacheDir;
      console.info(`NvrViewModel saveExitCoverImage: cacheDir='${this.context.cacheDir}', filesDir='${this.context.filesDir}'`);
      try {
        const list = fileIo.listFileSync(coversDir);
        console.info(`NvrViewModel saveExitCoverImage: cacheDir listable, contents count=${list.length}`);
      } catch (le) {
        console.warn(`NvrViewModel saveExitCoverImage: listFileSync(cacheDir) failed: ${(le as Error).message}`);
      }
      const coverFileName = `${snapshotCameraKey(cameraId)}_cover.png`;
      const coverFilePath = `${coversDir}/${coverFileName}`;
      console.info(`NvrViewModel saveExitCoverImage: coverFilePath='${coverFilePath}'`);

      const imagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/png', quality: 90 };
      console.info(`NvrViewModel saveExitCoverImage: opening file...`);
      const file = await fileIo.open(coverFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      console.info(`NvrViewModel saveExitCoverImage: file opened, fd=${file.fd}`);
      await imagePacker.packToFile(pixelMap, file.fd, packOpts);
      console.info(`NvrViewModel saveExitCoverImage: packToFile succeeded`);
      imagePacker.release();
      pixelMap.release();
      await fileIo.close(file);
      console.info(`NvrViewModel saveExitCoverImage: file closed`);

      await this.prefs.putString(`camera_cover_${cameraId}`, coverFilePath);
      console.info(`NvrViewModel saveExitCoverImage: saved to prefs key='camera_cover_${cameraId}'`);
      const camera = this.cameras.find(c => c.id === cameraId);
      if (camera) {
        camera.coverImagePath = coverFilePath;
        console.info(`NvrViewModel saveExitCoverImage: set coverImagePath on camera '${camera.name}' in memory`);
      } else {
        console.warn(`NvrViewModel saveExitCoverImage: camera not found in this.cameras for id='${cameraId}'`);
      }
      console.info(`NvrViewModel saveExitCoverImage: DONE`);
    } catch (e) {
      console.error(`NvrViewModel saveExitCoverImage FAILED: ${(e as Error).message}, stack=${(e as Error).stack}`);
      try { pixelMap.release(); } catch { /* ignore */ }
    }
  }

  async loadCameraCoverImages(): Promise<void> {
    console.info(`NvrViewModel loadCameraCoverImages: BEGIN, cameraCount=${this.cameras.length}`);
    const paths = await Promise.all(
      this.cameras.map(c => this.prefs.getString(`camera_cover_${c.id}`, ''))
    );
    for (let i = 0; i < this.cameras.length; i++) {
      const path = paths[i];
      if (path !== '') {
        let fileExists = false;
        try {
          const stat = fileIo.statSync(path);
          fileExists = stat.isFile();
        } catch {
          fileExists = false;
        }
        if (fileExists) {
          this.cameras[i].coverImagePath = path;
        } else {
          this.cameras[i].coverImagePath = undefined;
        }
      }
    }
    const withCover = this.cameras.filter(c => c.coverImagePath).length;
    console.info(`NvrViewModel loadCameraCoverImages: DONE, cameras with cover=${withCover}/${this.cameras.length}`);
  }

  queuePlayback(cameraToPlay: CameraDevice): void {
    this.uiState.playback.lastRequestedPlaybackCameraId = cameraToPlay.id;
    this.uiState.playback.pendingPlaybackCamera = createCameraDevice(
      cameraToPlay.id, cameraToPlay.name, cameraToPlay.rtspUrl,
      cameraToPlay.isRecording, false,
      cameraToPlay.group ?? '', cameraToPlay.sortOrder ?? 0,
    );
    this.uiState.playback.pendingPlaybackRequestId = this.uiState.playback.pendingPlaybackRequestId + 1;
  }

  rememberLastRequestedPlayback(cameraId: string): void {
    this.uiState.playback.lastRequestedPlaybackCameraId = cameraId;
  }

  clearLastRequestedPlaybackCameraId(): void {
    this.uiState.playback.lastRequestedPlaybackCameraId = null;
  }

  queuePendingPlaybackResume(cameraToResume: CameraDevice): void {
    this.uiState.playback.pendingPlaybackCamera = createCameraDevice(
      cameraToResume.id, cameraToResume.name, cameraToResume.rtspUrl,
      cameraToResume.isRecording, false,
      cameraToResume.group ?? '', cameraToResume.sortOrder ?? 0,
    );
    this.uiState.playback.pendingPlaybackRequestId = this.uiState.playback.pendingPlaybackRequestId + 1;
  }

  clearPendingPlaybackRequest(): void {
    this.uiState.playback.pendingPlaybackCamera = null;
    this.uiState.playback.pendingPlaybackRequestId = 0;
  }

  async playAdHocUrl(title: string, url: string): Promise<void> {
    const friendlyName = title || rstr(this.context, 'toast_ad_hoc_name');
    const safeId = `adhoc_${generateUUID()}`;
    const adhoc = createCameraDevice(safeId, friendlyName, url);
    await this.clearPlaybackState();
    const previousTab = this.uiState.selectedTab;
    this.uiState.selectedTab = 0;
    this.uiState.playback.adHocPlaybackCamera = adhoc;
    this.uiState.playback.tabBeforeFullscreen = previousTab;
    this.uiState.playback.isPlaybackFullscreen = true;
    this.queuePlayback(adhoc);
  }

  async startPlayback(cameraToPlay: CameraDevice): Promise<void> {
    console.info(`NvrViewModel startPlayback: cameraId=${cameraToPlay.id}, name=${cameraToPlay.name}, url=${cameraToPlay.rtspUrl}`);
    this.uiState.playback.pendingPlaybackCamera = null;
    this.uiState.playback.pendingPlaybackRequestId = 0;
    await this.clearPlaybackState();
    cameraToPlay.isConnected = false;

    const player = await this.streamManager.startStream(cameraToPlay);

    if (!player) {
      const diagnosis = this.streamManager.getLastDiagnosticMessage();
      console.error(`NvrViewModel startPlayback: startStream returned null, diagnosis=${diagnosis}, url=${cameraToPlay.rtspUrl}`);
      safeShowToast(rstr(this.context, 'toast_stream_failed', diagnosis));
      return;
    }

    console.info(`NvrViewModel startPlayback: success, playerState=${player.state}, url=${cameraToPlay.rtspUrl}`);
    this.uiState.playback.playingCameraId = cameraToPlay.id;
    this.uiState.playback.lastRequestedPlaybackCameraId = cameraToPlay.id;
    cameraToPlay.isConnected = true;
    cameraToPlay.lastSeen = Date.now();
    this.streamManager.setVolume(this.uiState.playback.lastNonZeroVolume);
  }

  async saveSnapshot(cameraId: string, cameraName: string): Promise<boolean> {
    console.info(`NvrViewModel saveSnapshot: BEGIN cameraId='${cameraId}', name='${cameraName}'`);
    if (!cameraId) {
      safeShowToast(rstr(this.context, 'toast_no_camera_info'));
      return false;
    }
    const pixelMap = await this.streamManager.captureSurfaceFrame();
    if (!pixelMap) {
      safeShowToast(rstr(this.context, 'toast_snapshot_need_video'));
      return false;
    }
    try {
      const rootPath = this.resolveStorageRoot();
      const snapshotDir = this.storageManager.getSnapshotDirectoryPath(rootPath);
      const now = new Date();
      const dateFolder = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      const timestamp = `${String(now.getHours()).padStart(2, '0')}-${String(now.getMinutes()).padStart(2, '0')}-${String(now.getSeconds()).padStart(2, '0')}`;
      const safeName = snapshotCameraKey(cameraName);
      const fullDir = `${snapshotDir}/${dateFolder}`;
      try { fileIo.mkdirSync(fullDir, true); } catch { /* may already exist */ }
      const snapshotPath = `${fullDir}/${safeName}_${timestamp}.png`;
      console.info(`NvrViewModel saveSnapshot: saving to '${snapshotPath}'`);

      const imagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/png', quality: 90 };
      const file = await fileIo.open(snapshotPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      await imagePacker.packToFile(pixelMap, file.fd, packOpts);
      imagePacker.release();
      pixelMap.release();
      await fileIo.close(file);
      console.info(`NvrViewModel saveSnapshot: DONE, path='${snapshotPath}'`);
      safeShowToast(rstr(this.context, 'toast_snapshot_saved'));
      await this.reloadSnapshots();
      return true;
    } catch (e) {
      console.error(`NvrViewModel saveSnapshot FAILED: ${(e as Error).message}, stack=${(e as Error).stack}`);
      try { pixelMap.release(); } catch { /* ignore */ }
      safeShowToast(rstr(this.context, 'toast_snapshot_save_failed'));
      return false;
    }
  }

  /* Recording */
  async toggleRecording(): Promise<void> {
    if (!this.uiState.playback.playingCameraId) {
      safeShowToast(rstr(this.context, 'toast_no_playback'));
      return;
    }
    if (this.uiState.playback.isRecording) {
      this.uiState.playback.isRecording = false;
      safeShowToast(rstr(this.context, 'toast_stop_recording'));
    } else {
      this.uiState.playback.isRecording = true;
      safeShowToast(rstr(this.context, 'toast_start_recording'));
    }
  }

  /* Device Management */
  async loadSelectedDeviceToForm(device: CameraDevice | null): Promise<void> {
    const formValue = device
      ? await buildDeviceManageFormValue(device, this.prefs)
      : emptyDeviceManageFormValue();
    this.uiState.deviceForm.selectedDeviceId = formValue.selectedDeviceId;
    this.uiState.deviceForm.manageName = formValue.manageName;
    this.uiState.deviceForm.manageVendor = formValue.manageVendor;
    this.uiState.deviceForm.manageProfile = formValue.manageProfile;
    this.uiState.deviceForm.manageStreamScheme = formValue.manageStreamScheme;
    this.uiState.deviceForm.manageStreamPath = formValue.manageStreamPath;
    this.uiState.deviceForm.manageHost = formValue.manageHost;
    this.uiState.deviceForm.managePort = formValue.managePort;
    this.uiState.deviceForm.manageLoginEnabled = formValue.manageLoginEnabled;
    this.uiState.deviceForm.manageUsername = formValue.manageUsername;
    this.uiState.deviceForm.managePassword = formValue.managePassword;
    this.uiState.deviceForm.managePasswordVisible = formValue.managePasswordVisible;
    this.uiState.deviceForm.forceHttpSoftwareDecode = formValue.forceHttpSoftwareDecode;
  }

  openAddLanding(): void {
    this.uiState.selectedTab = 5;
    this.uiState.deviceForm.verificationResult = null;
    this.uiState.deviceForm.deviceFlowStep = DeviceFlowStep.Landing;
    this.uiState.deviceForm.selectedDeviceId = null;
  }

  async openEditForm(device: CameraDevice | null): Promise<void> {
    await this.loadSelectedDeviceToForm(device);
    this.uiState.selectedTab = 5;
    this.uiState.deviceForm.verificationResult = null;
    this.uiState.deviceForm.deviceFlowStep = DeviceFlowStep.Form;
  }

  async duplicateCamera(device: CameraDevice): Promise<void> {
    const copied = createCameraDevice(
      generateUUID(),
      `${device.name} ${rstr(this.context, 'camera_copy_suffix')}`,
      device.rtspUrl,
      device.isRecording,
      device.isConnected,
      device.group ?? '',
      device.sortOrder ?? 0,
    );
    const ok = await this.dbHelper.addCamera(copied);
    if (ok) {
      await copyCameraPreferences(
        this.prefs, device.id, copied.id,
        this.uiState.deviceForm.manageVendor,
        this.uiState.deviceForm.manageProfile,
        this.uiState.deviceForm.manageLoginEnabled,
        this.uiState.deviceForm.manageUsername,
        this.uiState.deviceForm.managePassword,
      );
      await this.reloadCameras();
      const idx = this.cameras.findIndex(c => c.id === copied.id);
      if (idx >= 0) {
      this.uiState.selectedCameraIndex = idx;
      }
    }
    safeShowToast(ok ? rstr(this.context, 'toast_camera_copied') : rstr(this.context, 'toast_copy_failed'));
  }

  async deleteCamera(device: CameraDevice): Promise<void> {
    const isPlayingCurrent = this.uiState.playback.playingCameraId === device.id;
    if (isPlayingCurrent) {
      await this.clearPlaybackState();
      this.uiState.playback.lastRequestedPlaybackCameraId = null;
      this.uiState.playback.isPlaybackFullscreen = false;
    }
    const ok = await this.dbHelper.deleteCamera(device.id);
    if (ok) {
      await clearCameraPreferences(this.prefs, device.id);
      const coverPath = await this.prefs.getString(`camera_cover_${device.id}`, '');
      if (coverPath !== '') {
        try { this.storageManager.deleteFile(coverPath); } catch { /* ignore */ }
        await this.prefs.remove(`camera_cover_${device.id}`);
      }
      await this.reloadCameras();
    }
    safeShowToast(ok ? rstr(this.context, 'toast_camera_deleted') : rstr(this.context, 'toast_camera_delete_failed'));
    const next = this.cameras.find(c => c.id !== device.id);
    await this.loadSelectedDeviceToForm(next ?? null);
  }

  /* Simple state setters */
  onSelectedTabChange(tab: number): void {
    this.uiState.selectedTab = tab;
  }

  onLongPressedCameraIdChange(id: string | null): void {
    this.uiState.longPressedCameraId = id;
  }

  onSelectedCameraIndexChange(index: number): void {
    this.uiState.selectedCameraIndex = index;
  }

  onGridColumnsChange(cols: number): void {
    this.uiState.gridColumns = cols;
    this.prefs.putNumber('grid_columns', cols);
  }

  onPlaybackFullscreenChange(fullscreen: boolean): void {
    this.uiState.playback.isPlaybackFullscreen = fullscreen;
  }

  onVideoLayoutRefChange(surfaceId: string | null): void {
    this.streamManager.setSurfaceId(surfaceId);
  }

  onCurrentPlayerPlay(): void {
    this.streamManager.play();
  }

  onCurrentPlayerPause(): void {
    this.streamManager.pause();
  }

  onCurrentPlayerSetVolume(volume: number): void {
    this.streamManager.setVolume(volume);
  }

  onLastNonZeroVolumeChange(volume: number): void {
    this.uiState.playback.lastNonZeroVolume = volume;
  }

  /* Device form fields */
  onManageNameChange(v: string): void {
    this.uiState.deviceForm.manageName = v;
  }
  onManageVendorChange(v: string): void {
    this.uiState.deviceForm.manageVendor = v;
  }
  onManageStreamSchemeChange(v: string): void {
    this.uiState.deviceForm.manageStreamScheme = v;
  }
  onManageHostChange(v: string): void {
    this.uiState.deviceForm.manageHost = v;
  }
  onManagePortChange(v: string): void {
    this.uiState.deviceForm.managePort = v;
  }
  onManageStreamPathChange(v: string): void {
    this.uiState.deviceForm.manageStreamPath = v;
  }
  onManageLoginEnabledChange(v: boolean): void {
    this.uiState.deviceForm.manageLoginEnabled = v;
  }
  onManageUsernameChange(v: string): void {
    this.uiState.deviceForm.manageUsername = v;
  }
  onManagePasswordChange(v: string): void {
    this.uiState.deviceForm.managePassword = v;
  }
  onManagePasswordVisibleChange(v: boolean): void {
    this.uiState.deviceForm.managePasswordVisible = v;
  }
  onForceHttpSoftwareDecodeChange(v: boolean): void {
    this.uiState.deviceForm.forceHttpSoftwareDecode = v;
  }
  onVerificationResultChange(v: VerificationPreview | null): void {
    this.uiState.deviceForm.verificationResult = v;
  }
  onDeviceFlowStepChange(v: DeviceFlowStep): void {
    this.uiState.deviceForm.deviceFlowStep = v;
  }

  private async ensureDefaultStorageMarker(dirPath: string): Promise<void> {
    try {
      const segments = dirPath.split('/').filter(s => s.length > 0);
      let current = '';
      for (const seg of segments) {
        current = `${current}/${seg}`;
        try {
          fileIo.accessSync(current);
        } catch {
          fileIo.mkdirSync(current, true);
        }
      }
      const markerPath = `${dirPath}/录像存放目录.txt`;
      try {
        fileIo.accessSync(markerPath);
      } catch {
        const file = await fileIo.open(markerPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        await fileIo.close(file);
        console.info(`ensureDefaultStorageMarker: created '${markerPath}'`);
      }
    } catch (e) {
      console.error(`ensureDefaultStorageMarker failed: ${(e as Error).message}`);
    }
  }

  private resolveStorageRoot(): string {
    const p = this.uiState.settings.storagePathInput.trim();
    return p && p.startsWith('/') ? p : this.context.filesDir;
  }

  /* Settings fields */
  async onStoragePathChange(v: string): Promise<void> {
    this.uiState.settings.storagePathInput = v;
    await this.prefs.putString('storage_path', v.trim());
  }
  async onRecordingQualityChange(v: string): Promise<void> {
    this.uiState.settings.recordingQualityInput = v;
    await this.prefs.putString('recording_quality', v.trim());
  }
  async onRecordingDurationChange(v: string): Promise<void> {
    this.uiState.settings.recordingDurationInput = v;
    await this.prefs.putString('recording_duration', v.trim());
  }
  async onRtmpUrlChange(v: string): Promise<void> {
    this.uiState.settings.rtmpUrlInput = v;
    await this.prefs.putString('rtmp_push_url', v.trim());
  }
  async onRtmpStreamKeyChange(v: string): Promise<void> {
    this.uiState.settings.rtmpStreamKeyInput = v;
    await this.prefs.putString('rtmp_push_stream_key', v.trim());
  }
  async onRtmpUsernameChange(v: string): Promise<void> {
    this.uiState.settings.rtmpUsernameInput = v;
    await this.prefs.putString('rtmp_push_username', v.trim());
  }
  async onRtmpPasswordChange(v: string): Promise<void> {
    this.uiState.settings.rtmpPasswordInput = v;
    await this.prefs.putString('rtmp_push_password', v);
  }
  async onRtmpAudioEnabledChange(v: boolean): Promise<void> {
    this.uiState.settings.rtmpAudioEnabled = v;
    await this.prefs.putBoolean('rtmp_push_audio_enabled', v);
  }
  async onRtmpAutoStreamChange(v: boolean): Promise<void> {
    this.uiState.settings.rtmpAutoStreamEnabled = v;
    await this.prefs.putBoolean('rtmp_auto_stream', v);
  }

  async onBgPlaybackChange(v: boolean): Promise<void> {
    this.uiState.settings.bgPlaybackEnabled = v;
    await this.prefs.putBoolean('allow_background_playback', v);
  }
  async onAppearanceThemeModeChange(v: string): Promise<void> {
    this.uiState.settings.appearanceThemeMode = v;
    await this.prefs.putString('appearance_theme_mode', v);
    AppearanceThemeState.update(v);
    try {
      const appContext = this.context.getApplicationContext();
      if (v === 'system') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } else if (v === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      }
    } catch (e) {
      console.warn(`NvrViewModel onAppearanceThemeModeChange: setColorMode failed: ${(e as Error).message}`);
    }
  }

  /* Dialogs */
  onCurrentRecordingDialogChange(file: RecordingFile | null): void {
    this.uiState.currentRecordingDialog = file;
  }
  onPendingDeleteSnapshotChange(file: RecordingFile | null): void {
    this.uiState.pendingDeleteSnapshot = file;
  }

  /* Save verified device */
  async saveVerifiedDevice(): Promise<boolean> {
    const result = this.uiState.deviceForm.verificationResult;
    if (!result) return false;
    const editingDeviceId = this.uiState.deviceForm.selectedDeviceId;
    const targetDevice = createCameraDevice(
      editingDeviceId ?? generateUUID(),
      this.uiState.deviceForm.manageName.trim() || result.name,
      result.primaryUrl,
    );
    const success = editingDeviceId
      ? (await this.dbHelper.updateCamera(targetDevice)) > 0
      : await this.dbHelper.addCamera(targetDevice);

    if (success) {
      await this.prefs.putString(`camera_vendor_${targetDevice.id}`,
        this.uiState.deviceForm.manageVendor.trim() || 'IPCams');
      await this.prefs.putString(`camera_profile_${targetDevice.id}`,
        this.uiState.deviceForm.manageProfile.trim());
      await this.prefs.putBoolean(`camera_login_enabled_${targetDevice.id}`,
        this.uiState.deviceForm.manageLoginEnabled);
      await this.prefs.putString(`camera_username_${targetDevice.id}`,
        this.uiState.deviceForm.manageUsername.trim());
      await this.prefs.putString(`camera_password_${targetDevice.id}`,
        this.uiState.deviceForm.managePassword);
      await this.prefs.putBoolean(`camera_force_http_software_decode_${targetDevice.id}`,
        this.uiState.deviceForm.forceHttpSoftwareDecode);

      await this.reloadCameras();
      await this.loadSelectedDeviceToForm(targetDevice);
      const idx = this.cameras.findIndex(c => c.id === targetDevice.id);
      this.uiState.selectedCameraIndex = idx >= 0 ? idx : 0;
      this.uiState.selectedTab = 0;
      this.uiState.deviceForm.deviceFlowStep = DeviceFlowStep.Landing;
      this.uiState.deviceForm.verificationResult = null;
    }
    safeShowToast(success ? rstr(this.context, 'toast_save_success')
      : (editingDeviceId ? rstr(this.context, 'toast_update_failed') : rstr(this.context, 'toast_save_failed')));
    return success;
  }

  /* Submit form -> verification */
  submitFormToVerification(): void {
    const d = this.uiState.deviceForm;
    const name = d.manageName.trim() || 'IPCams';
    const host = d.manageHost.trim();
    const port = d.managePort.trim();
    const path = d.manageStreamPath.trim() || 'stream1';
    const selectedScheme = playbackStreamTypeFromScheme(d.manageStreamScheme) ?? PlaybackStreamType.RTSP;

    if (host === '') {
      safeShowToast(rstr(this.context, 'toast_fill_host'));
      return;
    }
    if (port !== '' && !/^\d+$/.test(port)) {
      safeShowToast(rstr(this.context, 'toast_port_invalid'));
      return;
    }

    const playbackUrl = buildPlaybackUrl(
      selectedScheme, host, port || defaultPlaybackPort(selectedScheme), path,
      d.manageLoginEnabled, d.manageUsername, d.managePassword,
    );

    this.onManageNameChange(name);
    const preview: VerificationPreview = {
      name,
      primaryUrl: playbackUrl,
      streamScheme: selectedScheme as string,
      host,
      port: port || defaultPlaybackPort(selectedScheme),
      resolution: '2560x1440',
      codec: 'hevc',
      streamPath: path,
    };
    this.onVerificationResultChange(preview);
    this.onDeviceFlowStepChange(DeviceFlowStep.Verifying);
  }

  async clearRecordings(): Promise<void> {
    const allFiles = this.storageManager.getAllRecordings();
    let deleted = 0;
    for (const file of allFiles) {
      if (this.storageManager.deleteFile(file.filePath)) deleted++;
    }
    safeShowToast(rstrNum(this.context, 'toast_recordings_cleared', deleted, allFiles.length));
    await this.reloadRecordings();
  }

  async shutdown(): Promise<void> {
    await this.clearPlaybackState();
    await this.streamManager.shutdown();
  }

  /* App Lock */
  async verifyPin(pin: string): Promise<boolean> {
    const storedPin = await this.prefs.getString('app_lock_pin', '');
    if (storedPin === pin) {
      this.uiState.isAppLocked = false;
      return true;
    }
    return false;
  }

  async setAppLock(enabled: boolean, pin: string = ''): Promise<void> {
    this.uiState.appLockEnabled = enabled;
    await this.prefs.putBoolean('app_lock_enabled', enabled);
    if (enabled && pin !== '') {
      await this.prefs.putString('app_lock_pin', pin);
    }
  }

  lockApp(): void {
    if (this.uiState.appLockEnabled) {
      this.uiState.isAppLocked = true;
    }
  }

  /* Share snapshot */
  async shareSnapshot(filePath: string): Promise<void> {
    try {
      const context = this.context as common.UIAbilityContext;
      const fileUri = `file://${filePath}`;
      const want: Want = {
        action: 'ohos.want.action.sendData',
        type: 'image/*',
        uri: fileUri,
      };
      context.startAbility(want);
    } catch (e) {
      safeShowToast(rstr(this.context, 'toast_share_failed'));
    }
  }
}
