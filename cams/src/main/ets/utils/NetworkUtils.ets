import { connection } from '@kit.NetworkKit';

export const PHONE_RTSP_PORT = 8554;
export const PHONE_RTSP_PATH = 'live';

export function getLocalIpAddress(): string {
  try {
    const netHandle = connection.getDefaultNetSync();
    if (netHandle.netId === 0) {
      return '127.0.0.1';
    }
    const props = connection.getConnectionPropertiesSync(netHandle);
    if (props.linkAddresses && props.linkAddresses.length > 0) {
      for (const linkAddr of props.linkAddresses) {
        const ip = linkAddr.address?.address;
        if (ip && !ip.startsWith('127.')) {
          return ip;
        }
      }
    }
  } catch (e) {
    console.warn(`getLocalIpAddress failed: ${(e as Error).message}`);
  }
  return '127.0.0.1';
}

export function buildPhoneRtspAddress(): string {
  const host = getLocalIpAddress();
  return `rtsp://${host}:${PHONE_RTSP_PORT}/${PHONE_RTSP_PATH}`;
}
