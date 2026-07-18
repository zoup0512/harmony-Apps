import { CameraDevice } from '../model/CameraDevice';
import { RecordingFile } from '../model/RecordingFile';
import { DeviceFlowStep, VerificationPreview, PlaybackStreamType } from '../utils/PlaybackModels';

export interface NvrPlaybackState {
  playingCameraId: string | null;
  lastRequestedPlaybackCameraId: string | null;
  isPlaybackFullscreen: boolean;
  pendingPlaybackCamera: CameraDevice | null;
  pendingPlaybackRequestId: number;
  lastNonZeroVolume: number;
  isRecording: boolean;
  adHocPlaybackCamera: CameraDevice | null;
  tabBeforeFullscreen: number;
  isVideoReady: boolean;
}

export function defaultPlaybackState(): NvrPlaybackState {
  return {
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
  };
}

export interface NvrDeviceFormState {
  selectedDeviceId: string | null;
  manageName: string;
  manageVendor: string;
  manageProfile: string;
  manageStreamScheme: string;
  manageStreamPath: string;
  manageHost: string;
  managePort: string;
  manageLoginEnabled: boolean;
  manageUsername: string;
  managePassword: string;
  managePasswordVisible: boolean;
  forceHttpSoftwareDecode: boolean;
  deviceFlowStep: DeviceFlowStep;
  verificationResult: VerificationPreview | null;
}

export function defaultDeviceFormState(): NvrDeviceFormState {
  return {
    selectedDeviceId: null,
    manageName: '',
    manageVendor: '',
    manageProfile: '',
    manageStreamScheme: PlaybackStreamType.RTSP,
    manageStreamPath: 'stream1',
    manageHost: '',
    managePort: '',
    manageLoginEnabled: true,
    manageUsername: '',
    managePassword: '',
    managePasswordVisible: false,
    forceHttpSoftwareDecode: false,
    deviceFlowStep: DeviceFlowStep.Landing,
    verificationResult: null,
  };
}

export interface NvrSettingsState {
  storagePathInput: string;
  recordingQualityInput: string;
  recordingDurationInput: string;
  rtmpUrlInput: string;
  rtmpStreamKeyInput: string;
  rtmpUsernameInput: string;
  rtmpPasswordInput: string;
  rtmpAudioEnabled: boolean;
  rtmpAutoStreamEnabled: boolean;
  appearanceThemeMode: string;
  bgPlaybackEnabled: boolean;
}

export function defaultSettingsState(): NvrSettingsState {
  return {
    storagePathInput: '',
    recordingQualityInput: '1080p',
    recordingDurationInput: '30',
    rtmpUrlInput: 'rtmp://www.razor51.site/live/3/livestream',
    rtmpStreamKeyInput: 'secret=0f6c7ea45242453eaa843dacafc241a6',
    rtmpUsernameInput: '',
    rtmpPasswordInput: '',
    rtmpAudioEnabled: true,
    rtmpAutoStreamEnabled: false,
    appearanceThemeMode: 'light',
    bgPlaybackEnabled: false,
  };
}

export interface NvrUiState {
  selectedTab: number;
  selectedCameraIndex: number;
  longPressedCameraId: string | null;
  currentRecordingDialog: RecordingFile | null;
  pendingDeleteSnapshot: RecordingFile | null;
  playback: NvrPlaybackState;
  deviceForm: NvrDeviceFormState;
  settings: NvrSettingsState;
  searchQuery?: string;
  cameraFilter?: 'all' | 'online' | 'offline';
  appLockEnabled?: boolean;
  isAppLocked?: boolean;
  gridColumns?: number;
}

export function copyPlaybackState(src: NvrPlaybackState): NvrPlaybackState {
  return {
    playingCameraId: src.playingCameraId,
    lastRequestedPlaybackCameraId: src.lastRequestedPlaybackCameraId,
    isPlaybackFullscreen: src.isPlaybackFullscreen,
    pendingPlaybackCamera: src.pendingPlaybackCamera,
    pendingPlaybackRequestId: src.pendingPlaybackRequestId,
    lastNonZeroVolume: src.lastNonZeroVolume,
    isRecording: src.isRecording,
    adHocPlaybackCamera: src.adHocPlaybackCamera,
    tabBeforeFullscreen: src.tabBeforeFullscreen,
    isVideoReady: src.isVideoReady,
  };
}

export function copyDeviceFormState(src: NvrDeviceFormState): NvrDeviceFormState {
  return {
    selectedDeviceId: src.selectedDeviceId,
    manageName: src.manageName,
    manageVendor: src.manageVendor,
    manageProfile: src.manageProfile,
    manageStreamScheme: src.manageStreamScheme,
    manageStreamPath: src.manageStreamPath,
    manageHost: src.manageHost,
    managePort: src.managePort,
    manageLoginEnabled: src.manageLoginEnabled,
    manageUsername: src.manageUsername,
    managePassword: src.managePassword,
    managePasswordVisible: src.managePasswordVisible,
    forceHttpSoftwareDecode: src.forceHttpSoftwareDecode,
    deviceFlowStep: src.deviceFlowStep,
    verificationResult: src.verificationResult,
  };
}

export function copySettingsState(src: NvrSettingsState): NvrSettingsState {
  return {
    storagePathInput: src.storagePathInput,
    recordingQualityInput: src.recordingQualityInput,
    recordingDurationInput: src.recordingDurationInput,
    rtmpUrlInput: src.rtmpUrlInput,
    rtmpStreamKeyInput: src.rtmpStreamKeyInput,
    rtmpUsernameInput: src.rtmpUsernameInput,
    rtmpPasswordInput: src.rtmpPasswordInput,
    rtmpAudioEnabled: src.rtmpAudioEnabled,
    rtmpAutoStreamEnabled: src.rtmpAutoStreamEnabled,
    appearanceThemeMode: src.appearanceThemeMode,
    bgPlaybackEnabled: src.bgPlaybackEnabled,
  };
}

export function copyUiState(src: NvrUiState): NvrUiState {
  return {
    selectedTab: src.selectedTab,
    selectedCameraIndex: src.selectedCameraIndex,
    longPressedCameraId: src.longPressedCameraId,
    currentRecordingDialog: src.currentRecordingDialog,
    pendingDeleteSnapshot: src.pendingDeleteSnapshot,
    playback: copyPlaybackState(src.playback),
    deviceForm: copyDeviceFormState(src.deviceForm),
    settings: copySettingsState(src.settings),
    searchQuery: src.searchQuery,
    cameraFilter: src.cameraFilter,
    appLockEnabled: src.appLockEnabled,
    isAppLocked: src.isAppLocked,
    gridColumns: src.gridColumns,
  };
}

export function defaultUiState(): NvrUiState {
  return {
    selectedTab: 0,
    selectedCameraIndex: 0,
    longPressedCameraId: null,
    currentRecordingDialog: null,
    pendingDeleteSnapshot: null,
    playback: defaultPlaybackState(),
    deviceForm: defaultDeviceFormState(),
    settings: defaultSettingsState(),
    searchQuery: '',
    cameraFilter: 'all',
    appLockEnabled: false,
    isAppLocked: false,
    gridColumns: 1,
  };
}
