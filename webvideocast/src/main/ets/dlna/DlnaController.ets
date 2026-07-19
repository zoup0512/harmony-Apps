/**
 * DlnaController.ets - DLNA/UPnP 控制器
 *
 * 职责：
 * 1. 拉取并解析 SSDP LOCATION 指向的设备描述 XML，构造 CastDevice；
 * 2. 通过 SOAP 调用 AVTransport 服务实现 SetAVTransportURI / Play /
 *    Pause / Stop / Seek / GetPositionInfo；
 * 3. 通过 RenderingControl 服务实现音量控制。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CastDevice, MediaItem } from '../model/Models';

const TAG = 'DlnaController';
const AVT_SERVICE = 'urn:schemas-upnp-org:service:AVTransport:1';
const RC_SERVICE = 'urn:schemas-upnp-org:service:RenderingControl:1';

export class DlnaController {
  /**
   * 拉取 LOCATION 描述文档并解析为 CastDevice。
   * 解析失败（非 MediaRenderer 等）返回 null。
   */
  static async describeDevice(location: string): Promise<CastDevice | null> {
    const xml = await DlnaController.httpGet(location);
    if (xml === '') {
      return null;
    }
    const device = new CastDevice();
    device.location = location;
    device.udn = DlnaController.tagText(xml, 'UDN');
    device.friendlyName = DlnaController.tagText(xml, 'friendlyName');
    device.manufacturer = DlnaController.tagText(xml, 'manufacturer');
    device.modelName = DlnaController.tagText(xml, 'modelName');

    const base = DlnaController.baseOf(location, DlnaController.tagText(xml, 'URLBase'));
    device.avTransportControlUrl = DlnaController.controlUrlOf(xml, AVT_SERVICE, base);
    device.renderingControlUrl = DlnaController.controlUrlOf(xml, RC_SERVICE, base);

    if (device.avTransportControlUrl === '' || device.friendlyName === '') {
      return null; // 不是可投屏的渲染设备
    }
    return device;
  }

  /** 投送媒体并开始播放 */
  static async cast(device: CastDevice, media: MediaItem): Promise<boolean> {
    const metadata = DlnaController.buildDidlLite(media);
    const okSet = await DlnaController.soap(device.avTransportControlUrl, AVT_SERVICE, 'SetAVTransportURI',
      `<InstanceID>0</InstanceID>` +
      `<CurrentURI>${DlnaController.xmlEscape(media.url)}</CurrentURI>` +
      `<CurrentURIMetaData>${DlnaController.xmlEscape(metadata)}</CurrentURIMetaData>`);
    if (!okSet) {
      return false;
    }
    return DlnaController.play(device);
  }

  static async play(device: CastDevice): Promise<boolean> {
    return DlnaController.soap(device.avTransportControlUrl, AVT_SERVICE, 'Play',
      '<InstanceID>0</InstanceID><Speed>1</Speed>');
  }

  static async pause(device: CastDevice): Promise<boolean> {
    return DlnaController.soap(device.avTransportControlUrl, AVT_SERVICE, 'Pause',
      '<InstanceID>0</InstanceID>');
  }

  static async stop(device: CastDevice): Promise<boolean> {
    return DlnaController.soap(device.avTransportControlUrl, AVT_SERVICE, 'Stop',
      '<InstanceID>0</InstanceID>');
  }

  /** target 形如 "00:01:30" */
  static async seek(device: CastDevice, target: string): Promise<boolean> {
    return DlnaController.soap(device.avTransportControlUrl, AVT_SERVICE, 'Seek',
      `<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>${target}</Target>`);
  }

  /** 返回 [positionSec, durationSec]；失败返回 [-1, -1] */
  static async getPosition(device: CastDevice): Promise<number[]> {
    const body = await DlnaController.soapRaw(device.avTransportControlUrl, AVT_SERVICE, 'GetPositionInfo',
      '<InstanceID>0</InstanceID>');
    if (body === '') {
      return [-1, -1];
    }
    const rel = DlnaController.tagText(body, 'RelTime');
    const dur = DlnaController.tagText(body, 'TrackDuration');
    return [DlnaController.hmsToSec(rel), DlnaController.hmsToSec(dur)];
  }

  /** 0 - 100 */
  static async setVolume(device: CastDevice, volume: number): Promise<boolean> {
    if (device.renderingControlUrl === '') {
      return false;
    }
    const v = Math.max(0, Math.min(100, Math.round(volume)));
    return DlnaController.soap(device.renderingControlUrl, RC_SERVICE, 'SetVolume',
      `<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>${v}</DesiredVolume>`);
  }

  // ---------------- 内部工具 ----------------

  private static async soap(controlUrl: string, service: string, action: string, args: string): Promise<boolean> {
    return (await DlnaController.soapRaw(controlUrl, service, action, args)) !== '';
  }

  private static async soapRaw(controlUrl: string, service: string, action: string, args: string): Promise<string> {
    const envelope =
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ' +
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">' +
      `<s:Body><u:${action} xmlns:u="${service}">${args}</u:${action}></s:Body>` +
      '</s:Envelope>';
    const req = http.createHttp();
    try {
      const resp = await req.request(controlUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPAction': `"${service}#${action}"`
        },
        extraData: envelope,
        connectTimeout: 5000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode === 200) {
        return resp.result as string;
      }
      hilog.warn(0x0001, TAG, '%{public}s failed, code=%{public}d', action, resp.responseCode);
      return '';
    } catch (e) {
      hilog.error(0x0001, TAG, '%{public}s error: %{public}s', action, JSON.stringify(e));
      return '';
    } finally {
      req.destroy();
    }
  }

  private static async httpGet(url: string): Promise<string> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      });
      return resp.responseCode === 200 ? resp.result as string : '';
    } catch (e) {
      hilog.error(0x0001, TAG, 'GET %{public}s error', url);
      return '';
    } finally {
      req.destroy();
    }
  }

  /** 从 XML 中提取首个 <tag>...</tag> 文本（轻量解析，避免引入完整 XML 解析器） */
  private static tagText(xml: string, tag: string): string {
    const open = `<${tag}>`;
    const close = `</${tag}>`;
    const i = xml.indexOf(open);
    if (i < 0) {
      return '';
    }
    const j = xml.indexOf(close, i + open.length);
    return j < 0 ? '' : xml.substring(i + open.length, j).trim();
  }

  /** 在设备描述里找到指定 service 的 controlURL 并转绝对地址 */
  private static controlUrlOf(xml: string, serviceType: string, base: string): string {
    const idx = xml.indexOf(serviceType);
    if (idx < 0) {
      return '';
    }
    const seg = xml.substring(idx, Math.min(xml.length, idx + 1200));
    const rel = DlnaController.tagText(seg, 'controlURL');
    if (rel === '') {
      return '';
    }
    if (rel.startsWith('http')) {
      return rel;
    }
    return rel.startsWith('/') ? base + rel : base + '/' + rel;
  }

  /** 计算 http://host:port 形式的基地址 */
  private static baseOf(location: string, urlBase: string): string {
    const src = urlBase !== '' ? urlBase : location;
    const m = src.match(/^(https?:\/\/[^\/]+)/);
    return m !== null ? m[1] : '';
  }

  private static buildDidlLite(media: MediaItem): string {
    const title = DlnaController.xmlEscape(media.title !== '' ? media.title : 'Web Video Cast');
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" ' +
      'xmlns:dc="http://purl.org/dc/elements/1.1/" ' +
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">' +
      '<item id="0" parentID="-1" restricted="1">' +
      `<dc:title>${title}</dc:title>` +
      '<upnp:class>object.item.videoItem</upnp:class>' +
      `<res protocolInfo="http-get:*:${media.mimeType}:*">${DlnaController.xmlEscape(media.url)}</res>` +
      '</item></DIDL-Lite>';
  }

  private static xmlEscape(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  private static hmsToSec(hms: string): number {
    if (hms === '' || hms === 'NOT_IMPLEMENTED') {
      return -1;
    }
    const parts = hms.split(':');
    if (parts.length !== 3) {
      return -1;
    }
    return Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Math.floor(Number(parts[2]));
  }
}
