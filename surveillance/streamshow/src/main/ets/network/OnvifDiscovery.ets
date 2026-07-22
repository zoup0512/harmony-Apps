/**
 * OnvifDiscovery.ets - ONVIF WS-Discovery 设备发现
 *
 * 向组播 239.255.255.250:3702 发送 WS-Discovery Probe（SOAP over UDP），
 * 收集 ProbeMatch 响应中的 XAddrs（设备服务地址）与 Scopes（名称/型号），
 * 得到局域网内的 ONVIF 摄像头列表。
 */
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OnvifDevice } from '../model/Models';

const TAG = 'OnvifDiscovery';
const WS_ADDR = '239.255.255.250';
const WS_PORT = 3702;

export type OnvifListener = (dev: OnvifDevice) => void;

export class OnvifDiscovery {
  private udp: socket.UDPSocket | null = null;
  private seen: Set<string> = new Set<string>();
  private searching: boolean = false;

  /** 发起一轮发现，durationMs 后自动停止 */
  async search(listener: OnvifListener, durationMs: number = 5000): Promise<void> {
    if (this.searching) {
      return;
    }
    this.searching = true;
    this.seen.clear();

    const udp = socket.constructUDPSocketInstance();
    this.udp = udp;
    udp.on('message', (value: socket.SocketMessageInfo) => {
      const text = OnvifDiscovery.decode(value.message);
      const dev = OnvifDiscovery.parseProbeMatch(text);
      if (dev !== null && !this.seen.has(dev.xAddr)) {
        this.seen.add(dev.xAddr);
        hilog.info(0x0001, TAG, 'found: %{public}s', dev.xAddr);
        listener(dev);
      }
    });

    try {
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 } as socket.NetAddress);
      const probe = OnvifDiscovery.buildProbe(util.generateRandomUUID());
      const opts: socket.UDPSendOptions = {
        data: probe,
        address: { address: WS_ADDR, port: WS_PORT, family: 1 } as socket.NetAddress
      };
      for (let i = 0; i < 3; i++) {
        await udp.send(opts);
        await OnvifDiscovery.sleep(300);
      }
      await OnvifDiscovery.sleep(durationMs);
    } catch (e) {
      hilog.error(0x0001, TAG, 'search error: %{public}s', JSON.stringify(e));
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

  /** WS-Discovery Probe 报文（目标类型 NetworkVideoTransmitter） */
  private static buildProbe(uuid: string): string {
    return '<?xml version="1.0" encoding="UTF-8"?>' +
      '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" ' +
      'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" ' +
      'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" ' +
      'xmlns:dn="http://www.onvif.org/ver10/network/wsdl">' +
      '<e:Header>' +
      `<w:MessageID>uuid:${uuid}</w:MessageID>` +
      '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>' +
      '<w:Action e:mustUnderstand="true">' +
      'http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>' +
      '</e:Header>' +
      '<e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>' +
      '</e:Envelope>';
  }

  /** 解析 ProbeMatch：提取 XAddrs 与 Scopes 中的名称/硬件 */
  private static parseProbeMatch(xml: string): OnvifDevice | null {
    if (!xml.includes('ProbeMatch')) {
      return null;
    }
    const xaddrs = OnvifDiscovery.tagTextNs(xml, 'XAddrs');
    if (xaddrs === '') {
      return null;
    }
    const dev = new OnvifDevice();
    // XAddrs 可能有多个（空格分隔），取第一个 http 地址
    const parts = xaddrs.split(/\s+/);
    for (const p of parts) {
      if (p.startsWith('http')) {
        dev.xAddr = p;
        break;
      }
    }
    if (dev.xAddr === '') {
      return null;
    }
    const ipMatch = dev.xAddr.match(/^https?:\/\/([^\/:]+)/);
    dev.ip = ipMatch !== null ? ipMatch[1] : '';

    const scopes = OnvifDiscovery.tagTextNs(xml, 'Scopes');
    dev.name = OnvifDiscovery.scopeValue(scopes, 'name');
    dev.hardware = OnvifDiscovery.scopeValue(scopes, 'hardware');
    if (dev.name === '') {
      dev.name = dev.ip !== '' ? `摄像头 ${dev.ip}` : 'ONVIF 设备';
    }
    return dev;
  }

  /** 提取 onvif://www.onvif.org/<key>/<value> 形式的 scope 值 */
  private static scopeValue(scopes: string, key: string): string {
    const re = new RegExp(`onvif:\\/\\/www\\.onvif\\.org\\/${key}\\/([^\\s]+)`, 'i');
    const m = re.exec(scopes);
    if (m === null) {
      return '';
    }
    try {
      return decodeURIComponent(m[1]);
    } catch (e) {
      return m[1];
    }
  }

  /** 忽略命名空间前缀提取标签文本 */
  private static tagTextNs(xml: string, tag: string): string {
    const re = new RegExp(`<[a-zA-Z0-9]*:?${tag}[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?${tag}>`);
    const m = re.exec(xml);
    return m !== null ? m[1].trim() : '';
  }

  private static decode(buf: ArrayBuffer): string {
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }
}
