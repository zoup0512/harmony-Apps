export enum BrowseSourceKind {
  LOCAL_FILE = 'LOCAL_FILE',
  NETWORK_URL = 'NETWORK_URL',
}

export interface BrowseFavorite {
  id: string;
  title: string;
  url: string;
  source: BrowseSourceKind;
  addedAtMs: number;
}

export interface BrowseNetworkSource {
  id: string;
  title: string;
  url: string;
  username: string;
  password: string;
  addedAtMs: number;
}

export interface BrowseLocalVideo {
  id: number;
  displayName: string;
  absolutePath: string;
  sizeBytes: number;
  durationMs: number;
  mimeType: string;
  folder: string;
}

export enum DeviceType {
  SMB = 'SMB',
  UPNP_MEDIA_SERVER = 'UPNP_MEDIA_SERVER',
  DLNA = 'DLNA',
  RTSP_CAMERA = 'RTSP_CAMERA',
}

export interface DiscoveredDevice {
  id: string;
  name: string;
  url: string;
  host: string;
  port: number;
  type: DeviceType;
  description: string;
}
