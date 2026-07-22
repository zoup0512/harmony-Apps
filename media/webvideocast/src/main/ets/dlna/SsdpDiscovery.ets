/**
 * SsdpDiscovery.ets - SSDP 设备发现
 *
 * 通过 UDP 向组播地址 239.255.255.250:1900 发送 M-SEARCH 报文，
 * 收集响应中的 LOCATION 头，再由 DlnaController 拉取设备描述文档。
 */
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SsdpDiscovery';
const SSDP_ADDR = '239.255.255.250';
const SSDP_PORT = 1900;
const SEARCH_TARGET = 'urn:schemas-upnp-org:service:AVTransport:1';

export interface SsdpResult {
  location: string;
  usn: string;
  server: string;
}

export type SsdpListener = (result: SsdpResult) => void;

export class SsdpDiscovery {
  private udp: socket.UDPSocket | null = null;
  private listener: SsdpListener | null = null;
  private seenLocations: Set<string> = new Set<string>();
  private searching: boolean = false;

  onDeviceFound(listener: SsdpListener): void {
    this.listener = listener;
  }

  /**
   * 开始一轮搜索。durationMs 后自动停止。
   */
  async search(durationMs: number = 5000): Promise<void> {
    if (this.searching) {
      return;
    }
    this.searching = true;
    this.seenLocations.clear();

    const udp = socket.constructUDPSocketInstance();
    this.udp = udp;

    udp.on('message', (value: socket.SocketMessageInfo) => {
      const text = SsdpDiscovery.decode(value.message);
      const result = SsdpDiscovery.parseResponse(text);
      if (result !== null && !this.seenLocations.has(result.location)) {
        this.seenLocations.add(result.location);
        hilog.info(0x0001, TAG, 'SSDP found: %{public}s', result.location);
        if (this.listener) {
          this.listener(result);
        }
      }
    });

    try {
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 } as socket.NetAddress);
      const msearch =
        'M-SEARCH * HTTP/1.1\r\n' +
        `HOST: ${SSDP_ADDR}:${SSDP_PORT}\r\n` +
        'MAN: "ssdp:discover"\r\n' +
        'MX: 3\r\n' +
        `ST: ${SEARCH_TARGET}\r\n` +
        '\r\n';
      const sendOpts: socket.UDPSendOptions = {
        data: msearch,
        address: { address: SSDP_ADDR, port: SSDP_PORT, family: 1 } as socket.NetAddress
      };
      // 连发 3 次提高发现率（UDP 不可靠）
      for (let i = 0; i < 3; i++) {
        await udp.send(sendOpts);
        await SsdpDiscovery.sleep(300);
      }
      await SsdpDiscovery.sleep(durationMs);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0001, TAG, 'SSDP search error: %{public}s', JSON.stringify(err));
    } finally {
      this.stop();
    }
  }

  stop(): void {
    this.searching = false;
    if (this.udp !== null) {
      this.udp.off('message');
      this.udp.close();
      this.udp = null;
    }
  }

  private static decode(buf: ArrayBuffer): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buf));
  }

  /** 解析 "HTTP/1.1 200 OK" 形式的 SSDP 响应头 */
  private static parseResponse(text: string): SsdpResult | null {
    if (!text.startsWith('HTTP/1.1 200')) {
      return null;
    }
    let location = '';
    let usn = '';
    let server = '';
    const lines = text.split('\r\n');
    for (const line of lines) {
      const idx = line.indexOf(':');
      if (idx <= 0) {
        continue;
      }
      const key = line.substring(0, idx).trim().toUpperCase();
      const val = line.substring(idx + 1).trim();
      if (key === 'LOCATION') {
        location = val;
      } else if (key === 'USN') {
        usn = val;
      } else if (key === 'SERVER') {
        server = val;
      }
    }
    return location !== '' ? { location: location, usn: usn, server: server } : null;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }
}
