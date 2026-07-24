import { bundleManager, common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { CameraDevice, cloneCameraDevice } from '../model/CameraDevice';
import { RecordingFile } from '../model/RecordingFile';
import { NvrViewModel } from '../viewmodel/NvrViewModel';
import { DeviceFlowStep, VerificationPreview, PlaybackStreamType, sanitizePlaybackUrl, buildPlaybackUrl, defaultPlaybackPort, playbackStreamTypeFromScheme, enrichCameraRtspUrl, cameraBadge, snapshotCameraKey } from '../utils/PlaybackModels';
import { NvrColors, getColors, AppearanceThemeState } from '../theme/NvrTheme';
import { NvrMainTopBar, NvrBottomBar, CameraHomeScreen, PlaybackFullscreenScreen, CameraActionOverlay } from '../components/NvrShellComponents';
import { DeviceManageTopBar, AddCameraLandingScreen, AddCameraFormScreen, AddCameraVerificationScreen, ManufacturerPickerScreen } from '../components/DeviceManageComponents';
import { BrowseScreen } from '../components/BrowseScreen';
import { ActivityStreamScreen, SnapshotScreen, SettingsHomeScreen } from '../components/NvrSecondaryScreens';
import { RecordingPreviewDialog, DeleteSnapshotConfirmDialog, ConfirmActionDialog, SetPinDialog, FeedbackDialog } from '../components/NvrDialogComponents';
import { NvrUiState, copyUiState } from '../viewmodel/NvrUiState';

function safeShowToast(message: string): void {
  try {
    promptAction.openToast({ message });
  } catch (e) {
    console.error(`showToast failed: ${(e as Error).message}`);
  }
}

@Entry
@Component
struct MainPage {
  private vm: NvrViewModel | null = null;
  @State uiState: NvrUiState = {
    selectedTab: 0,
    selectedCameraIndex: 0,
    longPressedCameraId: null,
    currentRecordingDialog: null,
    pendingDeleteSnapshot: null,
    playback: {
      playingCameraId: null,
      lastRequestedPlaybackCameraId: null,
      isPlaybackFullscreen: false,
      pendingPlaybackCamera: null,
      pendingPlaybackRequestId: 0,
      lastNonZeroVolume: 100,
      isRecording: false,
      adHocPlaybackCamera: null,
      tabBeforeFullscreen: 0,
      isVideoReady: false,
    },
    deviceForm: {
      selectedDeviceId: null,
      manageName: '',
      manageVendor: '',
      manageProfile: '',
      manageStreamScheme: 'rtsp',
      manageStreamPath: 'stream1',
      manageHost: '',
      managePort: '',
      manageLoginEnabled: true,
      manageUsername: '',
      managePassword: '',
      managePasswordVisible: false,
      forceHttpSoftwareDecode: false,
      deviceFlowStep: 'Landing' as DeviceFlowStep,
      verificationResult: null,
    },
    settings: {
      storagePathInput: '',
      recordingQualityInput: '1080p',
      recordingDurationInput: '30',
      rtmpUrlInput: '',
      rtmpStreamKeyInput: '',
      rtmpUsernameInput: '',
      rtmpPasswordInput: '',
      rtmpAudioEnabled: true,
      rtmpAutoStreamEnabled: false,
      appearanceThemeMode: 'light',
      bgPlaybackEnabled: false,
    },
  };
  @State cameras: CameraDevice[] = [];
  @State filteredCameras: CameraDevice[] = [];
  @State snapshots: RecordingFile[] = [];
  @State recordings: RecordingFile[] = [];
  @State colors: NvrColors = getColors('light', 'light');
  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentColorMode: number = 1;
  @State isVlcAvailable: boolean = true;
  @State playbackControlPlaying: boolean = false;
  @State controlsVisible: boolean = true;
  @State isVideoReady: boolean = false;
  @State videoWidth: number = 0;
  @State videoHeight: number = 0;
  @State surfaceId: string = '';
  @State isMuted: boolean = false;
  @State lastNonZeroVolume: number = 100;
  @State playbackInProgress: boolean = false;
  @State searchQuery: string = '';
  @State cameraFilter: string = 'all';
  @State isAppLocked: boolean = false;
  @State pinInput: string = '';
  @State isInitializing: boolean = true;
  @State activityFullscreen: boolean = false;
  @State showSetPinDialog: boolean = false;
  @State pendingClearRecordingsConfirm: boolean = false;
  @State showFeedbackDialog: boolean = false;
  private pollTimerId: number = -1;
  private controlsTimerId: number = -1;
  private videoPollTimerId: number = -1;
  private healthCheckTimerId: number = -1;
  private abilityContext: common.Context | null = null;
  private isPageHidden: boolean = false;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.Context;
    this.abilityContext = context;
    this.vm = new NvrViewModel(context);
    this.initVm();
  }

  aboutToDisappear(): void {
    if (this.pollTimerId !== -1) clearTimeout(this.pollTimerId);
    if (this.controlsTimerId !== -1) clearTimeout(this.controlsTimerId);
    if (this.videoPollTimerId !== -1) clearTimeout(this.videoPollTimerId);
    if (this.healthCheckTimerId !== -1) clearTimeout(this.healthCheckTimerId);
    if (this.vm) {
      this.vm.shutdown();
    }
  }

  onPageShow(): void {
    this.isPageHidden = false;
    if (this.vm && this.uiState.playback.isPlaybackFullscreen && !this.uiState.playback.playingCameraId) {
      const resumeId = this.uiState.playback.lastRequestedPlaybackCameraId;
      if (resumeId) {
        const cam = this.cameras.find(c => c.id === resumeId);
        if (cam) {
          console.info(`MainPage onPageShow: resuming playback after background, cameraId=${resumeId}`);
          this.vm.queuePendingPlaybackResume(cam);
          this.syncState();
        }
      }
    }
  }

  onPageHide(): void {
    this.isPageHidden = true;
    if (this.vm && this.uiState.playback.playingCameraId) {
      this.restoreOrientation();
      const cameraId = this.uiState.playback.playingCameraId;
      const allowed = this.uiState.settings.bgPlaybackEnabled;
      if (!allowed && this.isPageHidden) {
        this.vm!.saveExitCoverImage(cameraId ?? '').then(() => {
          if (this.isPageHidden) {
            this.vm!.clearPlaybackState().then(() => this.syncState());
          }
        });
      }
    }
    if (this.vm) {
      this.vm.lockApp();
      this.syncState();
    }
  }

  private async initVm(): Promise<void> {
    if (!this.vm) return;
    await this.vm.init();
    this.syncState();
    this.isInitializing = false;
    this.startPlaybackPolling();
    this.vm.checkCameraHealth().then(() => this.syncState());
    this.checkAndShowFeedback();
  }

  private async checkAndShowFeedback(): Promise<void> {
    if (!this.vm) return;
    // debug 构建下不弹"反馈评价"弹窗，避免干扰开发调试
    try {
      const appInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      ).appInfo;
      if (appInfo?.debug) return;
    } catch (e) {
      console.warn('checkAndShowFeedback: detect debug mode failed: ' + (e as Error).message);
    }
    const done = await this.vm.prefs.getBoolean('feedback_done', false);
    if (done) return;
    const count = await this.vm.prefs.getNumber('feedback_launch_count', 0) + 1;
    if (count >= 3) {
      await this.vm.prefs.putNumber('feedback_launch_count', 0);
      this.showFeedbackDialog = true;
    } else {
      await this.vm.prefs.putNumber('feedback_launch_count', count);
    }
  }

  private openAppMarket(): void {
    if (!this.abilityContext) return;
    try {
      const want: Want = {
        action: 'ohos.want.action.appdetail',
        uri: 'market://details?id=com.razor.cams',
      };
      (this.abilityContext as common.UIAbilityContext).startAbility(want).catch((e: Error) => {
        console.error('openAppMarket failed: ' + e.message);
      });
    } catch (e) {
      console.error('openAppMarket error: ' + (e as Error).message);
    }
  }

  private startPlaybackPolling(): void {
    if (this.pollTimerId !== -1) clearTimeout(this.pollTimerId);
    this.pollTimerId = setInterval(() => {
      this.pollPlaybackState();
    }, 250);
    // Health check every 30 seconds
    if (this.healthCheckTimerId !== -1) clearTimeout(this.healthCheckTimerId);
    this.healthCheckTimerId = setInterval(() => {
      if (this.vm) {
        this.vm.checkCameraHealth().then(() => this.syncState());
      }
    }, 30000);
  }

  private pollPlaybackState(): void {
    if (!this.vm) return;
    const p = this.uiState.playback;
    if (p.isPlaybackFullscreen && p.playingCameraId) {
      const playing = this.vm.streamManager.isPlaying();
      if (playing !== this.playbackControlPlaying) {
        this.playbackControlPlaying = playing;
      }
      const hasVideo = this.vm.streamManager.hasVideoOutputFlag();
      if (hasVideo && !this.isVideoReady) {
        this.isVideoReady = true;
      }
      const vw = this.vm.streamManager.getVideoWidth();
      const vh = this.vm.streamManager.getVideoHeight();
      if (vw !== this.videoWidth || vh !== this.videoHeight) {
        this.videoWidth = vw;
        this.videoHeight = vh;
      }
    } else {
      this.playbackControlPlaying = false;
      this.isVideoReady = false;
      this.videoWidth = 0;
      this.videoHeight = 0;
    }

    // Handle pending playback request
    const pendingCam = this.uiState.playback.pendingPlaybackCamera;
    const pendingReqId = this.uiState.playback.pendingPlaybackRequestId;
    if (pendingCam && pendingReqId > 0) {
      console.info(`MainPage pendingPlayback: camId=${pendingCam.id}, reqId=${pendingReqId}, surfaceId='${this.surfaceId}', selectedTab=${this.uiState.selectedTab}, url=${pendingCam.rtspUrl}`);
    }
    if (pendingCam && pendingReqId > 0 && this.surfaceId !== '' && this.uiState.selectedTab === 0 && !this.playbackInProgress) {
      console.info(`MainPage: triggering startPlayback, surfaceId=${this.surfaceId}`);
      this.playbackInProgress = true;
      this.vm.startPlayback(pendingCam).then(() => {
        this.playbackInProgress = false;
        this.playbackControlPlaying = this.vm?.streamManager.isPlaying() ?? false;
        this.syncState();
      }).catch(() => {
        this.playbackInProgress = false;
      });
    }

    // Auto-resume playback when returning to camera tab
    if (this.uiState.selectedTab === 0 && !p.playingCameraId && !p.pendingPlaybackCamera && !p.isPlaybackFullscreen) {
      const resumeId = p.lastRequestedPlaybackCameraId;
      if (resumeId) {
        const cam = this.cameras.find(c => c.id === resumeId);
        if (cam) {
          this.vm.queuePendingPlaybackResume(cam);
          this.syncState();
        }
      }
    }
  }

  private syncState(): void {
    if (!this.vm) return;
    this.uiState = copyUiState(this.vm.uiState);
    this.cameras = this.vm.cameras.map(cloneCameraDevice);
    this.filteredCameras = this.vm.filteredCameras.map(cloneCameraDevice);
    const coversCount = this.cameras.filter(c => c.coverImagePath).length;
    console.info(`MainPage syncState: cameras=${this.cameras.length}, camerasWithCover=${coversCount}`);
    for (const c of this.cameras) {
      if (c.coverImagePath) {
        console.info(`MainPage syncState: camera '${c.name}' (id='${c.id}') coverImagePath='${c.coverImagePath}'`);
      }
    }
    this.snapshots = [...this.vm.snapshots];
    this.recordings = [...this.vm.recordings];
    const themeMode = this.vm.uiState.settings.appearanceThemeMode;
    const systemColorMode: 'light' | 'dark' = this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'dark' : 'light';
    this.colors = getColors(themeMode, systemColorMode);
    this.searchQuery = this.vm.uiState.searchQuery ?? '';
    this.cameraFilter = this.vm.uiState.cameraFilter ?? 'all';
    this.isAppLocked = this.vm.uiState.isAppLocked ?? false;
  }

  onColorModeChange(): void {
    this.syncState();
  }

  private getSelectedCameraForGrid(): CameraDevice | null {
    return this.cameras[this.uiState.selectedCameraIndex] ?? null;
  }

  private getCameraInAction(): CameraDevice | null {
    return this.cameras.find(c => c.id === this.uiState.longPressedCameraId) ?? null;
  }

  private getFullscreenCamera(): CameraDevice | null {
    const targetId = this.uiState.playback.playingCameraId ?? this.uiState.playback.lastRequestedPlaybackCameraId;
    if (this.uiState.playback.adHocPlaybackCamera && this.uiState.playback.adHocPlaybackCamera.id === targetId) {
      return this.uiState.playback.adHocPlaybackCamera;
    }
    return this.cameras.find(c => c.id === targetId) ?? null;
  }

  build(): void {
    if (this.isAppLocked) {
      this.AppLockScreen()
    } else {
      Stack() {
      Column() {
        if (this.uiState.selectedTab === 5) {
          this.DeviceManageContent()
        } else if (this.uiState.selectedTab === 0 && this.uiState.playback.isPlaybackFullscreen) {
          this.PlaybackFullscreenContent()
        } else {
          Column() {
            if (!this.activityFullscreen) {
              this.MainTopBar()
            }
            if (this.isInitializing) {
              Column() {
                LoadingProgress()
                  .width(48)
                  .height(48)
                  .color(this.colors.primary)
                Text($r('app.string.loading_app'))
                  .fontSize(14)
                  .fontColor(this.colors.onSurfaceVariant)
                  .margin({ top: 12 })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              Scroll() {
                Column() {
                  if (this.uiState.selectedTab === 0) {
                    CameraHomeScreen({
                      cameras: this.filteredCameras,
                      snapshots: this.snapshots,
                      selectedCameraId: this.getSelectedCameraForGrid()?.id ?? '',
                      playingCameraId: this.uiState.playback.playingCameraId ?? '',
                      accentColor: this.colors.primary,
                      bgColor: this.colors.background,
                      surfaceColor: this.colors.surface,
                      surfaceVariantColor: this.colors.surfaceVariant,
                      onBackgroundColor: this.colors.onBackground,
                      onSurfaceVariantColor: this.colors.onSurfaceVariant,
                      onPrimaryColor: this.colors.onPrimary,
                      secondaryContainerColor: this.colors.secondaryContainer,
                      errorColor: this.colors.error,
                      searchQuery: this.searchQuery,
                      cameraFilter: this.cameraFilter,
                      onCameraClick: (device: CameraDevice) => this.onCameraClick(device),
                      onCameraLongPress: (device: CameraDevice) => this.onCameraLongPress(device),
                      onAddCamera: () => this.onAddCamera(),
                      onSearchChange: (q: string) => { this.vm?.setSearchQuery(q); this.syncState(); },
                      onFilterChange: (f: string) => { this.vm?.setCameraFilter(f as 'all' | 'online' | 'offline'); this.syncState(); },
                      gridColumns: this.uiState.gridColumns ?? 1,
                      onGridColumnsChange: (cols: number) => { this.vm?.onGridColumnsChange(cols); this.syncState(); },
                    })
                } else if (this.uiState.selectedTab === 1) {
                  BrowseScreen({
                    accentColor: this.colors.primary,
                    bgColor: this.colors.background,
                    surfaceColor: this.colors.surface,
                    surfaceVariantColor: this.colors.surfaceVariant,
                    onSurfaceColor: this.colors.onSurface,
                    onSurfaceVariantColor: this.colors.onSurfaceVariant,
                    onPrimaryColor: this.colors.onPrimary,
                    onPlayUrl: (title: string, url: string) => this.onPlayAdHocUrl(title, url),
                  })
                } else if (this.uiState.selectedTab === 2) {
                  ActivityStreamScreen({
                    recordings: this.recordings,
                    bgColor: this.colors.background,
                    surfaceColor: this.colors.surface,
                    onSurfaceColor: this.colors.onSurface,
                    onSurfaceVariantColor: this.colors.onSurfaceVariant,
                    accentColor: this.colors.primary,
                    onPrimaryColor: this.colors.onPrimary,
                    surfaceVariantColor: this.colors.surfaceVariant,
                    secondaryContainerColor: this.colors.secondaryContainer,
                    errorColor: this.colors.error,
                    outlineVariantColor: this.colors.outlineVariant,
                    rtmpUrlInput: this.uiState.settings.rtmpUrlInput,
                    rtmpStreamKeyInput: this.uiState.settings.rtmpStreamKeyInput,
                    rtmpUsernameInput: this.uiState.settings.rtmpUsernameInput,
                    rtmpPasswordInput: this.uiState.settings.rtmpPasswordInput,
                    onOpenRecording: (file: RecordingFile) => this.onOpenRecording(file),
                    onRefreshRecordings: () => this.onRefreshRecordings(),
                    onFullscreenChange: (isFullscreen: boolean) => { this.activityFullscreen = isFullscreen; },
                  })
                } else if (this.uiState.selectedTab === 3) {
                  SnapshotScreen({
                    snapshots: this.snapshots,
                    bgColor: this.colors.background,
                    surfaceColor: this.colors.surface,
                    onSurfaceColor: this.colors.onSurface,
                    onSurfaceVariantColor: this.colors.onSurfaceVariant,
                    accentColor: this.colors.primary,
                    onPrimaryColor: this.colors.onPrimary,
                    onOpenSnapshot: (file: RecordingFile) => this.onOpenRecording(file),
                    onDeleteSnapshot: (file: RecordingFile) => this.onDeleteSnapshot(file),
                    onShareSnapshot: (file: RecordingFile) => { this.vm?.shareSnapshot(file.filePath); },
                    onViewMore: () => this.onTabSelected(0),
                  })
                } else if (this.uiState.selectedTab === 4) {
                  SettingsHomeScreen({
                    storagePathInput: this.uiState.settings.storagePathInput,
                    recordingQualityInput: this.uiState.settings.recordingQualityInput,
                    recordingDurationInput: this.uiState.settings.recordingDurationInput,
                    appearanceThemeMode: this.uiState.settings.appearanceThemeMode,
                    rtmpUrlInput: this.uiState.settings.rtmpUrlInput,
                    rtmpStreamKeyInput: this.uiState.settings.rtmpStreamKeyInput,
                    rtmpUsernameInput: this.uiState.settings.rtmpUsernameInput,
                    rtmpPasswordInput: this.uiState.settings.rtmpPasswordInput,
                    rtmpAudioEnabled: this.uiState.settings.rtmpAudioEnabled,
                    rtmpAutoStreamEnabled: this.uiState.settings.rtmpAutoStreamEnabled,
                    bgPlaybackEnabled: this.uiState.settings.bgPlaybackEnabled,
                    bgColor: this.colors.background,
                    surfaceColor: this.colors.surface,
                    surfaceVariantColor: this.colors.surfaceVariant,
                    onSurfaceColor: this.colors.onSurface,
                    onSurfaceVariantColor: this.colors.onSurfaceVariant,
                    accentColor: this.colors.primary,
                    onPrimaryColor: this.colors.onPrimary,
                    outlineVariantColor: this.colors.outlineVariant,
                    onStoragePathChange: (v: string) => { this.vm?.onStoragePathChange(v); this.syncState(); },
                    onRecordingQualityChange: (v: string) => { this.vm?.onRecordingQualityChange(v); this.syncState(); },
                    onRecordingDurationChange: (v: string) => { this.vm?.onRecordingDurationChange(v); this.syncState(); },
                    onThemeModeChange: (v: string) => { this.vm?.onAppearanceThemeModeChange(v).then(() => this.syncState()); },
                    onRtmpUrlChange: (v: string) => { this.vm?.onRtmpUrlChange(v); this.syncState(); },
                    onRtmpStreamKeyChange: (v: string) => { this.vm?.onRtmpStreamKeyChange(v); this.syncState(); },
                    onRtmpUsernameChange: (v: string) => { this.vm?.onRtmpUsernameChange(v); this.syncState(); },
                    onRtmpPasswordChange: (v: string) => { this.vm?.onRtmpPasswordChange(v); this.syncState(); },
                    onRtmpAudioEnabledChange: (v: boolean) => { this.vm?.onRtmpAudioEnabledChange(v); this.syncState(); },
                    onRtmpAutoStreamChange: (v: boolean) => { this.vm?.onRtmpAutoStreamChange(v); this.syncState(); },
                    onBgPlaybackChange: (v: boolean) => { this.vm?.onBgPlaybackChange(v); this.syncState(); },
                    onClearRecordings: () => { this.pendingClearRecordingsConfirm = true; },
                    onManageRtmpSettings: () => safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_rtmp_configure_hint')),
                    appLockEnabled: this.uiState.appLockEnabled ?? false,
                    onAppLockChange: (enabled: boolean) => {
                      if (enabled) {
                        this.showSetPinDialog = true;
                      } else {
                        this.vm?.setAppLock(false).then(() => this.syncState());
                      }
                    },
                    onSelectStoragePath: () => {
                      const documentPicker = new picker.DocumentViewPicker();
                      const options = new picker.DocumentSelectOptions();
                      options.maxSelectNumber = 1;
                      documentPicker.select(options).then((uris: string[]) => {
                        if (uris && uris.length > 0) {
                          const uri = uris[0];
                          const pathPart = uri.replace(/^file:\/\//, '');
                          const slashIdx = pathPart.lastIndexOf('/');
                          if (slashIdx > 0) {
                            const dirPath = pathPart.substring(0, slashIdx);
                            this.vm?.onStoragePathChange(dirPath);
                            this.syncState();
                          }
                        }
                      }).catch((e: Error) => {
                        console.error(`StoragePathPicker: select failed: ${e.message}`);
                      });
                    },
                  })
                }
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .align(Alignment.Top)

            if (!this.activityFullscreen) {
              NvrBottomBar({
                selectedTab: this.uiState.selectedTab,
                accentColor: this.colors.primary,
                bgColor: this.colors.background,
                onSurfaceVariantColor: this.colors.onSurfaceVariant,
                onPrimaryColor: this.colors.onPrimary,
                onTabSelected: (index: number) => this.onTabSelected(index),
              })
            }
            }
          }
        }
      }
      .width('100%')
      .height('100%')

      if (this.getCameraInAction() !== null && this.uiState.selectedTab !== 5) {
        CameraActionOverlay({
          camera: this.getCameraInAction()!,
          badge: getContext(this).resourceManager.getStringByNameSync('badge_cam'),
          accentColor: this.colors.primary,
          surfaceColor: this.colors.surface,
          onSurfaceColor: this.colors.onSurface,
          outlineVariantColor: this.colors.outlineVariant,
          onDismiss: () => { this.vm?.onLongPressedCameraIdChange(null); this.syncState(); },
          onEdit: () => {
            const cam = this.getCameraInAction();
            this.vm?.onLongPressedCameraIdChange(null);
            if (cam) { this.vm?.openEditForm(cam).then(() => this.syncState()); }
            this.syncState();
          },
          onCopy: () => {
            const cam = this.getCameraInAction();
            this.vm?.onLongPressedCameraIdChange(null);
            if (cam) { this.vm?.duplicateCamera(cam).then(() => this.syncState()); }
            this.syncState();
          },
          onDelete: () => {
            const cam = this.getCameraInAction();
            this.vm?.onLongPressedCameraIdChange(null);
            if (cam) { this.vm?.deleteCamera(cam).then(() => this.syncState()); }
            this.syncState();
          },
        })
      }

      if (this.uiState.currentRecordingDialog) {
        Column() {
          RecordingPreviewDialog({
            dialogFile: this.uiState.currentRecordingDialog!,
            accentColor: this.colors.primary,
            onDismiss: () => { this.vm?.onCurrentRecordingDialogChange(null); this.syncState(); },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000000')
        .onClick(() => { this.vm?.onCurrentRecordingDialogChange(null); this.syncState(); })
      }

      if (this.uiState.pendingDeleteSnapshot) {
        Column() {
          DeleteSnapshotConfirmDialog({
            fileName: this.uiState.pendingDeleteSnapshot!.fileName,
            accentColor: this.colors.primary,
            errorColor: this.colors.error,
            onDismiss: () => { this.vm?.onPendingDeleteSnapshotChange(null); this.syncState(); },
            onConfirmDelete: () => {
              const file = this.uiState.pendingDeleteSnapshot;
              if (file && this.vm) {
                const deleted = this.vm.storageManager.deleteFile(file.filePath);
                this.vm.onPendingDeleteSnapshotChange(null);
                this.vm.reloadSnapshots().then(() => this.syncState());
                safeShowToast(deleted ? getContext(this).resourceManager.getStringByNameSync('toast_snapshot_deleted') : getContext(this).resourceManager.getStringByNameSync('toast_delete_failed'));
              }
              this.syncState();
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000000')
        .onClick(() => { this.vm?.onPendingDeleteSnapshotChange(null); this.syncState(); })
      }

      if (this.showSetPinDialog) {
        Column() {
          SetPinDialog({
            accentColor: this.colors.primary,
            errorColor: this.colors.error,
            onDismiss: () => { this.showSetPinDialog = false; },
            onConfirm: (pin: string) => {
              this.vm?.setAppLock(true, pin).then(() => {
                this.showSetPinDialog = false;
                safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_pin_set_success'));
                this.syncState();
              });
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000000')
        .onClick(() => { this.showSetPinDialog = false; })
      }

      if (this.pendingClearRecordingsConfirm) {
        Column() {
          ConfirmActionDialog({
            title: getContext(this).resourceManager.getStringByNameSync('dialog_clear_recordings_title'),
            message: getContext(this).resourceManager.getStringByNameSync('dialog_clear_recordings_message'),
            confirmLabel: getContext(this).resourceManager.getStringByNameSync('dialog_delete'),
            cancelLabel: getContext(this).resourceManager.getStringByNameSync('dialog_cancel'),
            accentColor: this.colors.primary,
            errorColor: this.colors.error,
            onDismiss: () => { this.pendingClearRecordingsConfirm = false; },
            onConfirmAction: () => {
              this.pendingClearRecordingsConfirm = false;
              this.vm?.clearRecordings().then(() => this.syncState());
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000000')
        .onClick(() => { this.pendingClearRecordingsConfirm = false; })
      }

      if (this.showFeedbackDialog) {
        Column() {
          FeedbackDialog({
            accentColor: this.colors.primary,
            onLater: () => { this.showFeedbackDialog = false; },
            onRate: () => {
              this.showFeedbackDialog = false;
              this.vm?.prefs.putBoolean('feedback_done', true);
              this.openAppMarket();
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
    }
  }

  @Builder
  AppLockScreen() {
    Column() {
      SymbolGlyph($r('sys.symbol.lock_fill'))
        .fontSize(48)
        .fontColor([this.colors.onBackground])
        .margin({ bottom: 20 })

      Text($r('app.string.enter_pin'))
        .fontSize(20)
        .fontColor(this.colors.onBackground)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 })

      TextInput({ text: this.pinInput, placeholder: 'PIN' })
        .fontSize(18)
        .fontColor(this.colors.onBackground)
        .backgroundColor(this.colors.surfaceVariant)
        .borderRadius(12)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .width('60%')
        .type(InputType.Password)
        .onChange((v: string) => { this.pinInput = v; })

      Text($r('app.string.action_unlock'))
        .fontSize(16)
        .fontColor(this.colors.onPrimary)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 32, right: 32, top: 14, bottom: 14 })
        .backgroundColor(this.colors.primary)
        .borderRadius(16)
        .margin({ top: 20 })
        .onClick(() => {
          if (this.vm) {
            this.vm.verifyPin(this.pinInput).then((ok: boolean) => {
              if (ok) {
                this.pinInput = '';
                this.syncState();
              } else {
                safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_pin_error'));
                this.pinInput = '';
              }
            });
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.colors.background)
  }

  @Builder
  MainTopBar() {
    NvrMainTopBar({
      selectedTab: this.uiState.selectedTab,
      accentColor: this.colors.primary,
      bgColor: this.colors.background,
      onBackgroundColor: this.colors.onBackground,
      onPrimaryColor: this.colors.onPrimary,
      onEditClick: () => {
        this.vm?.reloadCameras().then(() => {
          const cam = this.getSelectedCameraForGrid() ?? this.cameras[0] ?? null;
          this.vm?.openEditForm(cam).then(() => this.syncState());
        });
      },
      onMenuClick: () => {
        this.vm?.onSelectedTabChange(4);
        this.syncState();
      },
      onAddClick: () => this.onAddCamera(),
    })
  }

  @Builder
  DeviceManageContent() {
    Column() {
      DeviceManageTopBar({
        title: this.getDeviceManageTitle(),
        flowStep: this.uiState.deviceForm.deviceFlowStep,
        isEditingExistingCamera: this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.Form
          && this.uiState.deviceForm.selectedDeviceId !== null,
        accentColor: this.colors.primary,
        bgColor: this.colors.background,
        onSurfaceColor: this.colors.onSurface,
        onSurfaceVariantColor: this.colors.onSurfaceVariant,
        errorColor: this.colors.error,
        onCancel: () => {
          this.vm?.onSelectedTabChange(0);
          this.vm?.onLongPressedCameraIdChange(null);
          this.vm?.onVerificationResultChange(null);
          this.vm?.onDeviceFlowStepChange(DeviceFlowStep.Landing);
          this.syncState();
        },
        onBack: () => {
          if (this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.Verifying
            || this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.VendorPicker) {
            this.vm?.onDeviceFlowStepChange(DeviceFlowStep.Form);
          } else {
            this.vm?.onDeviceFlowStepChange(
              this.uiState.deviceForm.selectedDeviceId === null
                ? DeviceFlowStep.Landing : DeviceFlowStep.Form
            );
          }
          this.syncState();
        },
      })

      if (this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.Landing) {
        AddCameraLandingScreen({
          bgColor: this.colors.background,
          surfaceColor: this.colors.surface,
          onSurfaceColor: this.colors.onSurface,
          onSurfaceVariantColor: this.colors.onSurfaceVariant,
          accentColor: this.colors.primary,
          secondaryContainerColor: this.colors.secondaryContainer,
          onAddLocalCamera: () => {
            this.vm?.loadSelectedDeviceToForm(null).then(() => {
              this.vm?.onDeviceFlowStepChange(DeviceFlowStep.Form);
              this.syncState();
            });
          },
        })
      } else if (this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.VendorPicker) {
        ManufacturerPickerScreen({
          selectedVendor: this.uiState.deviceForm.manageVendor,
          bgColor: this.colors.background,
          surfaceColor: this.colors.surface,
          onSurfaceColor: this.colors.onSurface,
          onSurfaceVariantColor: this.colors.onSurfaceVariant,
          accentColor: this.colors.primary,
          outlineVariantColor: this.colors.outlineVariant,
          onSelectVendor: (v: string) => {
            this.vm?.onManageVendorChange(v);
            this.vm?.onDeviceFlowStepChange(DeviceFlowStep.Form);
            this.syncState();
          },
        })
      } else if (this.uiState.deviceForm.deviceFlowStep === DeviceFlowStep.Verifying) {
        AddCameraVerificationScreen({
          result: this.uiState.deviceForm.verificationResult,
          forceHttpSoftwareDecode: this.uiState.deviceForm.forceHttpSoftwareDecode,
          manageName: this.uiState.deviceForm.manageName,
          bgColor: this.colors.background,
          surfaceColor: this.colors.surface,
          onSurfaceColor: this.colors.onSurface,
          onSurfaceVariantColor: this.colors.onSurfaceVariant,
          placeholderColor: this.colors.placeholderColor,
          accentColor: this.colors.primary,
          onPrimaryColor: this.colors.onPrimary,
          primaryColor: this.colors.primary,
          onNameChange: (v: string) => { this.vm?.onManageNameChange(v); this.syncState(); },
          onSave: () => {
            this.vm?.saveVerifiedDevice().then(() => this.syncState());
          },
        })
      } else {
        AddCameraFormScreen({
          manageName: this.uiState.deviceForm.manageName,
          manageVendor: this.uiState.deviceForm.manageVendor,
          manageStreamScheme: this.uiState.deviceForm.manageStreamScheme,
          manageHost: this.uiState.deviceForm.manageHost,
          managePort: this.uiState.deviceForm.managePort,
          manageStreamPath: this.uiState.deviceForm.manageStreamPath,
          manageLoginEnabled: this.uiState.deviceForm.manageLoginEnabled,
          manageUsername: this.uiState.deviceForm.manageUsername,
          managePassword: this.uiState.deviceForm.managePassword,
          forceHttpSoftwareDecode: this.uiState.deviceForm.forceHttpSoftwareDecode,
          bgColor: this.colors.background,
          surfaceColor: this.colors.surface,
          onSurfaceColor: this.colors.onSurface,
          onSurfaceVariantColor: this.colors.onSurfaceVariant,
          placeholderColor: this.colors.placeholderColor,
          accentColor: this.colors.primary,
          onPrimaryColor: this.colors.onPrimary,
          outlineVariantColor: this.colors.outlineVariant,
          onManageNameChange: (v: string) => { this.vm?.onManageNameChange(v); this.syncState(); },
          onManageStreamSchemeChange: (v: string) => { this.vm?.onManageStreamSchemeChange(v); this.syncState(); },
          onManageHostChange: (v: string) => { this.vm?.onManageHostChange(v); this.syncState(); },
          onManagePortChange: (v: string) => { this.vm?.onManagePortChange(v); this.syncState(); },
          onManageStreamPathChange: (v: string) => { this.vm?.onManageStreamPathChange(v); this.syncState(); },
          onManageLoginEnabledChange: (v: boolean) => { this.vm?.onManageLoginEnabledChange(v); this.syncState(); },
          onManageUsernameChange: (v: string) => { this.vm?.onManageUsernameChange(v); this.syncState(); },
          onManagePasswordChange: (v: string) => { this.vm?.onManagePasswordChange(v); this.syncState(); },
          onForceHttpSoftwareDecodeChange: (v: boolean) => { this.vm?.onForceHttpSoftwareDecodeChange(v); this.syncState(); },
          onOpenVendorPicker: () => {
            this.vm?.onDeviceFlowStepChange(DeviceFlowStep.VendorPicker);
            this.syncState();
          },
          onSave: () => { this.vm?.submitFormToVerification(); this.syncState(); },
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }

  @Builder
  PlaybackFullscreenContent() {
    PlaybackFullscreenScreen({
      camera: this.getFullscreenCamera()!,
      badge: getContext(this).resourceManager.getStringByNameSync('badge_cam'),
      isPlaying: this.playbackControlPlaying,
      isMuted: this.isMuted,
      isVideoReady: this.isVideoReady,
      isRecording: this.uiState.playback.isRecording,
      videoWidth: this.videoWidth,
      videoHeight: this.videoHeight,
      accentColor: this.colors.primary,
      onPrimaryColor: this.colors.onPrimary,
      errorColor: this.colors.error,
      surfaceVariantColor: this.colors.surfaceVariant,
      surfaceId: this.surfaceId,
      onBindSurface: (id: string) => {
        this.surfaceId = id;
        this.vm?.onVideoLayoutRefChange(id);
        const cam = this.getFullscreenCamera();
        if (cam) {
          this.vm?.queuePlayback(cam);
          this.syncState();
        }
      },
      onBack: () => {
        const cameraId = this.uiState.playback.playingCameraId;
        const cam = this.getFullscreenCamera();
        const cameraName = cam?.name ?? cameraId ?? '';
        console.info(`MainPage onBack: BEGIN cameraId='${cameraId}', cameraName='${cameraName}', isVideoReady=${this.isVideoReady}, surfaceId='${this.surfaceId}'`);
        this.vm?.saveExitCoverImage(cameraId ?? '').then(() => {
          console.info(`MainPage onBack: saveExitCoverImage completed, now clearing playback...`);
          this.vm?.clearPlaybackState().then(() => {
            this.vm?.onPlaybackFullscreenChange(false);
            this.vm?.clearLastRequestedPlaybackCameraId();
            this.isVideoReady = false;
            this.playbackControlPlaying = false;
            this.playbackInProgress = false;
            this.restoreOrientation();
            const isAdHoc = this.uiState.playback.adHocPlaybackCamera != null;
            const tabBefore = this.uiState.playback.tabBeforeFullscreen;
            if (isAdHoc && tabBefore !== 0) {
              this.vm?.onSelectedTabChange(tabBefore);
            }
            console.info(`MainPage onBack: reloading cameras and syncing state...`);
            this.vm?.reloadCameras().then(() => {
              const covers = this.vm?.cameras.filter(c => c.coverImagePath).length ?? 0;
              console.info(`MainPage onBack: reloadCameras done, cameras with cover=${covers}/${this.vm?.cameras.length ?? 0}`);
              this.syncState();
            });
            this.syncState();
          });
        });
      },
      onTogglePlayPause: () => {
        if (this.playbackControlPlaying) {
          this.playbackControlPlaying = false;
          this.vm?.onCurrentPlayerPause();
        } else {
          this.playbackControlPlaying = true;
          this.vm?.onCurrentPlayerPlay();
        }
      },
      onMute: () => {
        if (this.isMuted) {
          this.isMuted = false;
          this.vm?.onCurrentPlayerSetVolume(this.lastNonZeroVolume);
          safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_sound_restored'));
        } else {
          this.isMuted = true;
          this.vm?.onCurrentPlayerSetVolume(0);
          safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_muted'));
        }
      },
      onSnapshot: () => {
        const cameraId = this.uiState.playback.playingCameraId;
        const cam = this.getFullscreenCamera();
        const cameraName = cam?.name ?? cameraId ?? '';
        if (!cameraId) {
          safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_no_camera_info'));
          return;
        }
        this.vm?.saveSnapshot(cameraId, cameraName).then(() => this.syncState());
      },
      onToggleRecord: () => { this.vm?.toggleRecording().then(() => this.syncState()); },
      onMore: () => { safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_feature_coming_soon')); },
      onSwipeLeft: () => this.switchCamera(1),
      onSwipeRight: () => this.switchCamera(-1),
    })
  }

  private getDeviceManageTitle(): string {
    switch (this.uiState.deviceForm.deviceFlowStep) {
      case DeviceFlowStep.Landing: return getContext(this).resourceManager.getStringByNameSync('device_manage_title_add');
      case DeviceFlowStep.Verifying: return getContext(this).resourceManager.getStringByNameSync('device_manage_title_verifying');
      case DeviceFlowStep.VendorPicker: return getContext(this).resourceManager.getStringByNameSync('select_manufacturer');
      case DeviceFlowStep.Form:
        return this.uiState.deviceForm.selectedDeviceId === null
          ? getContext(this).resourceManager.getStringByNameSync('device_manage_title_new')
          : (this.uiState.deviceForm.manageName || getContext(this).resourceManager.getStringByNameSync('device_manage_title_edit'));
      default: return '';
    }
  }

  private onTabSelected(index: number): void {
    this.vm?.onSelectedTabChange(index);
    this.vm?.onLongPressedCameraIdChange(null);
    if (index !== 2) {
      this.activityFullscreen = false;
    }
    if (index === 2 || index === 3) {
      this.vm?.reloadRecordings().then(() => {
        this.vm?.reloadSnapshots().then(() => this.syncState());
      });
    }
    if (index !== 0) {
      this.restoreOrientation();
      const cameraId = this.uiState.playback.playingCameraId;
      if (cameraId) {
        this.vm?.saveExitCoverImage(cameraId).then(() => {
          this.vm?.clearPlaybackState().then(() => {
            this.vm?.onPlaybackFullscreenChange(false);
            this.syncState();
          });
        });
      } else {
        this.vm?.clearPlaybackState().then(() => {
          this.vm?.onPlaybackFullscreenChange(false);
          this.syncState();
        });
      }
    }
    this.syncState();
  }

  private onAddCamera(): void {
    this.vm?.openAddLanding();
    this.syncState();
  }

  private async onCameraClick(device: CameraDevice): Promise<void> {
    if (!this.vm) return;
    const idx = this.cameras.findIndex(c => c.id === device.id);
    this.vm.onSelectedCameraIndexChange(idx >= 0 ? idx : 0);
    if (!this.isVlcAvailable) {
      safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_player_unavailable'));
      return;
    }
    const cameraToPlay = await enrichCameraRtspUrl(device, this.vm.prefs);
    this.vm.onPlaybackFullscreenChange(true);
    this.vm.queuePlayback(cameraToPlay);
    this.setLandscapeOrientation();
    this.syncState();
  }

  private onCameraLongPress(device: CameraDevice): void {
    if (!this.vm) return;
    const idx = this.cameras.findIndex(c => c.id === device.id);
    this.vm.onSelectedCameraIndexChange(idx >= 0 ? idx : 0);
    this.vm.onLongPressedCameraIdChange(device.id);
    this.syncState();
  }

  private onPlayAdHocUrl(title: string, url: string): void {
    this.vm?.playAdHocUrl(title, url).then(() => {
      this.setLandscapeOrientation();
      this.syncState();
    });
  }

  private onOpenRecording(file: RecordingFile): void {
    this.vm?.onCurrentRecordingDialogChange(file);
    this.syncState();
  }

  private onRefreshRecordings(): void {
    this.vm?.reloadRecordings().then(() => this.syncState());
  }

  private onDeleteSnapshot(file: RecordingFile): void {
    this.vm?.onPendingDeleteSnapshotChange(file);
    this.syncState();
  }

  private setLandscapeOrientation(): void {
    if (!this.abilityContext) return;
    try {
      window.getLastWindow(this.abilityContext).then((win: window.Window) => {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      });
    } catch (e) {
      console.error(`setLandscapeOrientation failed: ${(e as Error).message}`);
    }
  }

  private restoreOrientation(): void {
    if (!this.abilityContext) return;
    try {
      window.getLastWindow(this.abilityContext).then((win: window.Window) => {
        win.setPreferredOrientation(window.Orientation.AUTO_ROTATION);
      });
    } catch (e) {
      console.error(`restoreOrientation failed: ${(e as Error).message}`);
    }
  }

  private async switchCamera(direction: number): Promise<void> {
    if (!this.vm || this.cameras.length === 0) return;
    const currentIdx = this.cameras.findIndex(c => c.id === this.uiState.playback.playingCameraId);
    if (currentIdx < 0) return;
    let nextIdx = currentIdx + direction;
    if (nextIdx >= this.cameras.length) nextIdx = 0;
    if (nextIdx < 0) nextIdx = this.cameras.length - 1;
    const nextCamera = this.cameras[nextIdx];
    if (!nextCamera || nextCamera.rtspUrl === '') return;
    this.vm.onSelectedCameraIndexChange(nextIdx);
    const cameraToPlay = await enrichCameraRtspUrl(nextCamera, this.vm.prefs);
    const currentCameraId = this.uiState.playback.playingCameraId;
    this.vm.saveExitCoverImage(currentCameraId ?? '').then(() => {
      this.vm?.clearPlaybackState().then(() => {
        this.vm?.queuePlayback(cameraToPlay);
        this.isVideoReady = false;
        this.playbackControlPlaying = false;
        this.syncState();
      });
    });
  }

  private showPlaybackMoreMenu(): void {
    safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_feature_coming_soon'));
  }
}
