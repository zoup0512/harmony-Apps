import { CameraDevice } from '../model/CameraDevice';
import { PrefStore } from '../utils/PrefStore';

export enum PlaybackStreamType {
  RTSP = 'rtsp',
  RTMP = 'rtmp',
  HTTP = 'http',
  HTTPS = 'https',
}

export enum DeviceFlowStep {
  Landing = 'Landing',
  Form = 'Form',
  Verifying = 'Verifying',
  VendorPicker = 'VendorPicker',
}

export interface VerificationPreview {
  name: string;
  primaryUrl: string;
  streamScheme: string;
  host: string;
  port: string;
  resolution: string;
  codec: string;
  streamPath: string;
}

export interface RtspParsed {
  host: string;
  port: string;
  username: string;
  password: string;
  path: string;
}

export function playbackStreamTypeFromScheme(scheme: string): PlaybackStreamType | null {
  const lower = scheme.toLowerCase();
  switch (lower) {
    case 'rtsp': return PlaybackStreamType.RTSP;
    case 'rtmp': return PlaybackStreamType.RTMP;
    case 'http': return PlaybackStreamType.HTTP;
    case 'https': return PlaybackStreamType.HTTPS;
    default: return null;
  }
}

export function playbackStreamTypeFromUrl(url: string): PlaybackStreamType | null {
  try {
    const scheme = url.split('://')[0] ?? '';
    return playbackStreamTypeFromScheme(scheme);
  } catch {
    return null;
  }
}

export function defaultPlaybackPort(streamType: PlaybackStreamType | null): string {
  switch (streamType) {
    case PlaybackStreamType.RTSP: return '554';
    case PlaybackStreamType.RTMP: return '1935';
    case PlaybackStreamType.HTTP: return '80';
    case PlaybackStreamType.HTTPS: return '443';
    default: return '554';
  }
}

export function parsePlaybackUrl(playbackUrl: string): RtspParsed {
  try {
    const schemeIdx = playbackUrl.indexOf('://');
    if (schemeIdx < 0) return { host: '', port: '', username: '', password: '', path: 'stream1' };
    const afterScheme = playbackUrl.substring(schemeIdx + 3);
    const authority = afterScheme.split('/')[0] ?? '';
    const pathPart = afterScheme.substring(authority.length).replace(/^\//, '');
    const userInfo = authority.includes('@') ? authority.split('@')[0] ?? '' : '';
    const hostPort = authority.includes('@') ? authority.split('@')[1] ?? '' : authority;
    const host = hostPort.split(':')[0] ?? '';
    const port = hostPort.includes(':') ? hostPort.split(':')[1] ?? '' : '';
    const username = userInfo.includes(':') ? userInfo.split(':')[0] ?? '' : userInfo;
    const password = userInfo.includes(':') ? userInfo.split(':')[1] ?? '' : '';
    return { host, port, username, password, path: pathPart || 'stream1' };
  } catch {
    return { host: '', port: '', username: '', password: '', path: 'stream1' };
  }
}

export function normalizeNetworkHost(host: string): string {
  const trimmed = host.trim().replace(/^\/+|\/+$/g, '');
  if (trimmed === '') return '';
  const withoutScheme = trimmed.includes('://') ? trimmed.split('://')[1] ?? trimmed : trimmed;
  const authority = withoutScheme.split('/')[0] ?? withoutScheme;
  const withoutUserInfo = authority.includes('@') ? authority.split('@')[1] ?? authority : authority;
  const candidate = withoutUserInfo.split(':')[0]?.replace(/\.$/, '') ?? '';
  return candidate;
}

export function buildPlaybackUrl(
  streamType: PlaybackStreamType,
  host: string,
  port: string,
  path: string,
  loginEnabled: boolean,
  username: string,
  password: string,
): string {
  const authPart = loginEnabled && username !== ''
    ? (password !== '' ? `${username}:${password}@` : `${username}@`)
    : '';
  const normalizedHost = normalizeNetworkHost(host);
  const hostPart = port !== '' ? `${normalizedHost}:${port}` : normalizedHost;
  return `${streamType}://${authPart}${hostPart}/${path}`;
}

export function sanitizePlaybackUrl(playbackUrl: string): string {
  return playbackUrl.replace(/(:\/\/)([^:/@]+)(?::([^@/]*))?@/, (match: string, scheme: string, user: string, pass: string) => {
    const maskedUser = user && user !== '' ? '***' : '';
    const maskedPass = pass && pass !== '' ? ':***' : '';
    return `${scheme}${maskedUser}${maskedPass}@`;
  });
}

export function sanitizeRtspUrl(rtspUrl: string): string {
  return sanitizePlaybackUrl(rtspUrl);
}

export function cameraBadge(camera: CameraDevice, vendor: string): string {
  if (vendor && vendor.trim() !== '') return vendor.trim();
  return camera.rtspUrl.toLowerCase().includes('rtsp') ? 'RTSP' : 'CAM';
}

export function snapshotCameraKey(cameraName: string): string {
  return cameraName.replace(/[^a-zA-Z0-9\u4e00-\u9fa5_-]/g, '_');
}

export async function enrichCameraRtspUrl(
  camera: CameraDevice,
  prefs: PrefStore,
  fallbackUsername: string = '',
  fallbackPassword: string = '',
  fallbackLoginEnabled: boolean | null = null,
): Promise<CameraDevice> {
  const streamType = playbackStreamTypeFromUrl(camera.rtspUrl);
  if (!streamType) return camera;
  if (streamType !== PlaybackStreamType.RTSP && streamType !== PlaybackStreamType.RTMP) return camera;

  const parsed = parsePlaybackUrl(camera.rtspUrl);
  if (parsed.username !== '') return camera;

  const loginEnabled = fallbackLoginEnabled ?? await prefs.getBoolean(`camera_login_enabled_${camera.id}`, false);
  const username = (await prefs.getString(`camera_username_${camera.id}`, '')).trim() || fallbackUsername.trim();
  const password = await prefs.getString(`camera_password_${camera.id}`, '') || fallbackPassword;

  if (!loginEnabled || username === '') return camera;
  if (parsed.host === '') return camera;

  const enrichedUrl = buildPlaybackUrl(
    streamType, parsed.host, parsed.port,
    parsed.path || 'stream1', true, username, password,
  );
  const enriched: CameraDevice = {
    id: camera.id,
    name: camera.name,
    rtspUrl: enrichedUrl,
    isRecording: camera.isRecording,
    isConnected: camera.isConnected,
    group: camera.group,
    sortOrder: camera.sortOrder,
    lastSeen: camera.lastSeen,
    connectionQuality: camera.connectionQuality,
  };
  return enriched;
}

export interface DeviceManageFormValue {
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
}

export function emptyDeviceManageFormValue(): DeviceManageFormValue {
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
  };
}

export async function buildDeviceManageFormValue(
  device: CameraDevice,
  prefs: PrefStore,
): Promise<DeviceManageFormValue> {
  const streamType = playbackStreamTypeFromUrl(device.rtspUrl) ?? PlaybackStreamType.RTSP;
  const parsed = parsePlaybackUrl(device.rtspUrl);
  const results = await Promise.all([
    prefs.getString(`camera_username_${device.id}`, ''),
    prefs.getString(`camera_vendor_${device.id}`, 'TP-Link'),
    prefs.getString(`camera_profile_${device.id}`, 'default'),
    prefs.getString(`camera_password_${device.id}`, ''),
    prefs.getBoolean(`camera_force_http_software_decode_${device.id}`, false),
  ]);
  const prefUsername = results[0] as string;
  const vendor = results[1] as string;
  const profile = results[2] as string;
  const password = results[3] as string;
  const forceHttpSoftwareDecode = results[4] as boolean;
  const username = parsed.username || prefUsername;
  const loginEnabled = await prefs.getBoolean(
    `camera_login_enabled_${device.id}`,
    parsed.username !== '' || prefUsername !== '',
  );
  return {
    selectedDeviceId: device.id,
    manageName: device.name,
    manageVendor: vendor,
    manageProfile: profile,
    manageStreamScheme: streamType === PlaybackStreamType.RTMP ? PlaybackStreamType.HTTP : streamType,
    manageStreamPath: parsed.path === '' ? 'stream1' : parsed.path,
    manageHost: parsed.host,
    managePort: parsed.port || defaultPlaybackPort(streamType),
    manageLoginEnabled: loginEnabled,
    manageUsername: username,
    managePassword: parsed.password || password,
    managePasswordVisible: false,
    forceHttpSoftwareDecode,
  };
}

export async function copyCameraPreferences(
  prefs: PrefStore,
  sourceCameraId: string,
  targetCameraId: string,
  fallbackVendor: string,
  fallbackProfile: string,
  fallbackLoginEnabled: boolean,
  fallbackUsername: string,
  fallbackPassword: string,
): Promise<void> {
  const sourceVendor = await prefs.getString(`camera_vendor_${sourceCameraId}`, fallbackVendor);
  const sourceProfile = await prefs.getString(`camera_profile_${sourceCameraId}`, fallbackProfile);
  const sourceLoginEnabled = await prefs.getBoolean(`camera_login_enabled_${sourceCameraId}`, fallbackLoginEnabled);
  const sourceUsername = await prefs.getString(`camera_username_${sourceCameraId}`, fallbackUsername);
  const sourcePassword = await prefs.getString(`camera_password_${sourceCameraId}`, fallbackPassword);
  const sourceForceHttp = await prefs.getBoolean(`camera_force_http_software_decode_${sourceCameraId}`, false);
  await prefs.putString(`camera_vendor_${targetCameraId}`, sourceVendor);
  await prefs.putString(`camera_profile_${targetCameraId}`, sourceProfile);
  await prefs.putBoolean(`camera_login_enabled_${targetCameraId}`, sourceLoginEnabled);
  await prefs.putString(`camera_username_${targetCameraId}`, sourceUsername);
  await prefs.putString(`camera_password_${targetCameraId}`, sourcePassword);
  await prefs.putBoolean(`camera_force_http_software_decode_${targetCameraId}`, sourceForceHttp);
}

export async function clearCameraPreferences(prefs: PrefStore, cameraId: string): Promise<void> {
  await prefs.remove(`camera_vendor_${cameraId}`);
  await prefs.remove(`camera_profile_${cameraId}`);
  await prefs.remove(`camera_login_enabled_${cameraId}`);
  await prefs.remove(`camera_username_${cameraId}`);
  await prefs.remove(`camera_password_${cameraId}`);
  await prefs.remove(`camera_force_http_software_decode_${cameraId}`);
}
