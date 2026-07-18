import { socket, connection } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { PlaybackStreamType, parsePlaybackUrl, playbackStreamTypeFromUrl, defaultPlaybackPort } from './PlaybackModels';
import { CameraDevice } from '../model/CameraDevice';
import { rstr, rstrNum } from './I18nUtils';

const TAG = 'CameraHealthChecker';
const DEFAULT_TIMEOUT_MS = 3000;
const DEFAULT_PORT = 554;

export interface HealthCheckResult {
  reachable: boolean;
  latencyMs: number;
  error?: string;
}

export async function checkCameraReachable(camera: CameraDevice, timeoutMs: number = DEFAULT_TIMEOUT_MS, context?: common.Context): Promise<HealthCheckResult> {
  if (!camera.rtspUrl || camera.rtspUrl.trim() === '') {
    return { reachable: false, latencyMs: 0, error: context ? rstr(context, 'health_url_empty') : 'URL is empty' };
  }

  const parsed = parsePlaybackUrl(camera.rtspUrl);
  const host = parsed.host;
  if (!host) {
    return { reachable: false, latencyMs: 0, error: context ? rstr(context, 'health_host_unresolved') : 'Cannot resolve host' };
  }

  const streamType = playbackStreamTypeFromUrl(camera.rtspUrl);
  const portStr = parsed.port || defaultPlaybackPort(streamType) || String(DEFAULT_PORT);
  const port = parseInt(portStr, 10);
  if (!port || port <= 0 || port > 65535) {
    return { reachable: false, latencyMs: 0, error: context ? rstr(context, 'health_port_invalid', portStr) : `Invalid port: ${portStr}` };
  }

  let resolvedIp = host;
  let addrFamily: number = 1;
  if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(host)) {
    try {
      const addresses = await connection.getAddressesByName(host);
      if (addresses && addresses.length > 0) {
        resolvedIp = addresses[0].address;
        addrFamily = addresses[0].family ?? 1;
      } else {
        return { reachable: false, latencyMs: 0, error: context ? rstr(context, 'health_dns_failed', host) : `DNS resolution failed: ${host}` };
      }
    } catch (e) {
      return { reachable: false, latencyMs: 0, error: context ? rstr(context, 'health_dns_error', (e as Error).message) : `DNS resolution error: ${(e as Error).message}` };
    }
  }

  const tcpSocket = socket.constructTCPSocketInstance();
  const startTime = Date.now();

  let connected = false;
  let timerId: number = -1;

  try {
    const bindAddr = addrFamily === 2 ? '::' : '0.0.0.0';
    await tcpSocket.bind({ address: bindAddr, port: 0, family: addrFamily });

    const connectPromise = tcpSocket.connect({
      address: { address: resolvedIp, port: port, family: addrFamily },
      timeout: timeoutMs,
    });

    const timeoutPromise = new Promise<void>((_, reject) => {
      timerId = setTimeout(() => {
        reject(new Error(context ? rstrNum(context, 'health_timeout', timeoutMs) : `Connection timeout (${timeoutMs}ms)`));
      }, timeoutMs + 500);
    });

    try {
      await Promise.race([connectPromise, timeoutPromise]);
      connected = true;
    } catch (e) {
      const err = e as Error;
      if (timerId !== -1) clearTimeout(timerId);

      try {
        const state = await tcpSocket.getState();
        if (state.isConnected) {
          connected = true;
        } else {
          return { reachable: false, latencyMs: Date.now() - startTime, error: err.message };
        }
      } catch {
        return { reachable: false, latencyMs: Date.now() - startTime, error: err.message };
      }
    }

    if (timerId !== -1) clearTimeout(timerId);

    if (connected) {
      const latency = Date.now() - startTime;
      return { reachable: true, latencyMs: latency };
    } else {
      return { reachable: false, latencyMs: Date.now() - startTime, error: context ? rstr(context, 'health_not_connected') : 'Connection not established' };
    }
  } finally {
    try {
      if (connected) {
        tcpSocket.close();
      } else {
        tcpSocket.close();
      }
    } catch {
      // ignore close errors
    }
  }
}

export async function checkCamerasHealth(cameras: CameraDevice[], timeoutMs: number = DEFAULT_TIMEOUT_MS, context?: common.Context): Promise<Map<string, HealthCheckResult>> {
  const results = new Map<string, HealthCheckResult>();
  const concurrency = 5;
  const batches: CameraDevice[][] = [];
  for (let i = 0; i < cameras.length; i += concurrency) {
    batches.push(cameras.slice(i, i + concurrency));
  }

  for (const batch of batches) {
    const promises = batch.map(async (camera) => {
      const result = await checkCameraReachable(camera, timeoutMs, context);
      results.set(camera.id, result);
      return result;
    });
    await Promise.all(promises);
  }

  return results;
}
