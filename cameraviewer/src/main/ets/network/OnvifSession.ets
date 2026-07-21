/**
 * OnvifSession.ets - ONVIF 会话客户端（本作核心新增：PTZ）
 *
 * 以"设备会话"为单位缓存 Media/PTZ 服务地址与 Profile token，避免每次
 * 操作都走三连查询：
 *   init(): GetCapabilities(All) → Media XAddr / PTZ XAddr（无 PTZ 段则无云台）
 *           GetProfiles → 首个 Profile token
 *   getStreamUri()   → RTSP 地址
 *   getSnapshotUri() → JPEG 快照地址（列表缩略图与 RTSP 通道截图的来源）
 *   PTZ：continuousMove / stopMove / gotoHome / getPresets / gotoPreset / setPreset
 *
 * 鉴权：WS-Security UsernameToken PasswordDigest
 *   Digest = Base64( SHA1( nonce + created + password ) )
 * SHA1 由 @kit.CryptoArchitectureKit 计算。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PtzPreset, PtzVector } from '../model/Models';

const TAG = 'OnvifSession';
const NS_MEDIA = 'http://www.onvif.org/ver10/media/wsdl';
const NS_PTZ = 'http://www.onvif.org/ver20/ptz/wsdl';
const NS_SCHEMA = 'http://www.onvif.org/ver10/schema';

export class OnvifSession {
  readonly deviceXAddr: string;
  private username: string;
  private password: string;

  private mediaXAddr: string = '';
  private ptzXAddr: string = '';
  private profileToken: string = '';
  private inited: boolean = false;

  constructor(deviceXAddr: string, username: string, password: string) {
    this.deviceXAddr = deviceXAddr;
    this.username = username;
    this.password = password;
  }

  /** 是否具备 PTZ 能力（init 后有效） */
  hasPtz(): boolean {
    return this.ptzXAddr !== '';
  }

  /**
   * 初始化会话：定位 Media/PTZ 服务并取首个 Profile token。
   * 成功返回 true。Media 定位失败时兜底固定路径，提高杂牌兼容率。
   */
  async init(): Promise<boolean> {
    if (this.inited) {
      return this.profileToken !== '';
    }
    const capBody = '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl">' +
      '<tds:Category>All</tds:Category></tds:GetCapabilities>';
    const capResp = await this.soap(this.deviceXAddr, capBody);
    this.mediaXAddr = OnvifSession.tagTextNs(OnvifSession.sectionNs(capResp, 'Media'), 'XAddr');
    this.ptzXAddr = OnvifSession.tagTextNs(OnvifSession.sectionNs(capResp, 'PTZ'), 'XAddr');
    if (this.mediaXAddr === '') {
      this.mediaXAddr = OnvifSession.replacePath(this.deviceXAddr, '/onvif/media_service');
    }

    const profBody = `<trt:GetProfiles xmlns:trt="${NS_MEDIA}"/>`;
    const profResp = await this.soap(this.mediaXAddr, profBody);
    this.profileToken = OnvifSession.firstProfileToken(profResp);
    this.inited = true;
    if (this.profileToken === '') {
      hilog.warn(0x0001, TAG, 'no profile token from %{public}s', this.mediaXAddr);
      return false;
    }
    return true;
  }

  /** 取 RTSP 流地址；失败返回 '' */
  async getStreamUri(): Promise<string> {
    if (!await this.init()) {
      return '';
    }
    const body = `<trt:GetStreamUri xmlns:trt="${NS_MEDIA}">` +
      '<trt:StreamSetup>' +
      `<tt:Stream xmlns:tt="${NS_SCHEMA}">RTP-Unicast</tt:Stream>` +
      `<tt:Transport xmlns:tt="${NS_SCHEMA}"><tt:Protocol>RTSP</tt:Protocol></tt:Transport>` +
      '</trt:StreamSetup>' +
      `<trt:ProfileToken>${this.profileToken}</trt:ProfileToken>` +
      '</trt:GetStreamUri>';
    const resp = await this.soap(this.mediaXAddr, body);
    return OnvifSession.tagTextNs(resp, 'Uri');
  }

  /** 取 JPEG 快照地址；失败返回 '' */
  async getSnapshotUri(): Promise<string> {
    if (!await this.init()) {
      return '';
    }
    const body = `<trt:GetSnapshotUri xmlns:trt="${NS_MEDIA}">` +
      `<trt:ProfileToken>${this.profileToken}</trt:ProfileToken>` +
      '</trt:GetSnapshotUri>';
    const resp = await this.soap(this.mediaXAddr, body);
    return OnvifSession.tagTextNs(resp, 'Uri');
  }

  // ---------------- PTZ ----------------

  /** 连续移动：v 的 x=pan、y=tilt、z=zoom（各 ∈ [-1,1]），按下开始 */
  async continuousMove(v: PtzVector): Promise<void> {
    if (!await this.init() || this.ptzXAddr === '') {
      return;
    }
    const body = `<tptz:ContinuousMove xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      '<tptz:Velocity>' +
      `<tt:PanTilt x="${v.x}" y="${v.y}" xmlns:tt="${NS_SCHEMA}"/>` +
      `<tt:Zoom x="${v.z}" xmlns:tt="${NS_SCHEMA}"/>` +
      '</tptz:Velocity>' +
      '</tptz:ContinuousMove>';
    await this.soap(this.ptzXAddr, body);
  }

  /** 停止移动：抬手调用 */
  async stopMove(): Promise<void> {
    if (!await this.init() || this.ptzXAddr === '') {
      return;
    }
    const body = `<tptz:Stop xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      '<tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>true</tptz:Zoom>' +
      '</tptz:Stop>';
    await this.soap(this.ptzXAddr, body);
  }

  /** 回 Home 位（设备须支持） */
  async gotoHome(): Promise<void> {
    if (!await this.init() || this.ptzXAddr === '') {
      return;
    }
    const body = `<tptz:GotoHomePosition xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      '</tptz:GotoHomePosition>';
    await this.soap(this.ptzXAddr, body);
  }

  /** 预置位列表 */
  async getPresets(): Promise<PtzPreset[]> {
    if (!await this.init() || this.ptzXAddr === '') {
      return [];
    }
    const body = `<tptz:GetPresets xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      '</tptz:GetPresets>';
    const resp = await this.soap(this.ptzXAddr, body);
    return OnvifSession.parsePresets(resp);
  }

  /** 转到预置位 */
  async gotoPreset(token: string): Promise<void> {
    if (!await this.init() || this.ptzXAddr === '') {
      return;
    }
    const body = `<tptz:GotoPreset xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      `<tptz:PresetToken>${token}</tptz:PresetToken>` +
      '</tptz:GotoPreset>';
    await this.soap(this.ptzXAddr, body);
  }

  /** 把当前位置存为新预置位；返回设备分配的 token（失败 ''） */
  async setPreset(name: string): Promise<string> {
    if (!await this.init() || this.ptzXAddr === '') {
      return '';
    }
    const body = `<tptz:SetPreset xmlns:tptz="${NS_PTZ}">` +
      `<tptz:ProfileToken>${this.profileToken}</tptz:ProfileToken>` +
      `<tptz:PresetName>${OnvifSession.xmlEscape(name)}</tptz:PresetName>` +
      '</tptz:SetPreset>';
    const resp = await this.soap(this.ptzXAddr, body);
    return OnvifSession.tagTextNs(resp, 'PresetToken');
  }

  // ---------------- SOAP 基础 ----------------

  private async soap(url: string, body: string): Promise<string> {
    const header = this.username !== ''
      ? await OnvifSession.securityHeader(this.username, this.password) : '';
    const envelope =
      '<?xml version="1.0" encoding="UTF-8"?>' +
      '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">' +
      (header !== '' ? `<s:Header>${header}</s:Header>` : '') +
      `<s:Body>${body}</s:Body></s:Envelope>`;
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/soap+xml; charset=utf-8' },
        extraData: envelope,
        connectTimeout: 5000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode === 200) {
        return resp.result as string;
      }
      hilog.warn(0x0001, TAG, 'soap %{public}s -> %{public}d', url, resp.responseCode);
      return '';
    } catch (e) {
      hilog.error(0x0001, TAG, 'soap error: %{public}s', JSON.stringify(e));
      return '';
    } finally {
      req.destroy();
    }
  }

  private static async securityHeader(username: string, password: string): Promise<string> {
    const nonce = OnvifSession.randomBytes(16);
    const created = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const createdBytes = new util.TextEncoder().encodeInto(created);
    const passBytes = new util.TextEncoder().encodeInto(password);

    const all = new Uint8Array(nonce.length + createdBytes.length + passBytes.length);
    all.set(nonce, 0);
    all.set(createdBytes, nonce.length);
    all.set(passBytes, nonce.length + createdBytes.length);

    const digest = await OnvifSession.sha1(all);
    const b64 = new util.Base64Helper();
    const nonceB64 = b64.encodeToStringSync(nonce);
    const digestB64 = b64.encodeToStringSync(digest);

    return '<Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" s:mustUnderstand="true">' +
      '<UsernameToken>' +
      `<Username>${OnvifSession.xmlEscape(username)}</Username>` +
      '<Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">' +
      `${digestB64}</Password>` +
      '<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">' +
      `${nonceB64}</Nonce>` +
      `<Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">${created}</Created>` +
      '</UsernameToken></Security>';
  }

  private static async sha1(data: Uint8Array): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA1');
    await md.update({ data: data });
    const out = await md.digest();
    return out.data;
  }

  private static randomBytes(n: number): Uint8Array {
    const out = new Uint8Array(n);
    for (let i = 0; i < n; i++) {
      out[i] = Math.floor(Math.random() * 256);
    }
    return out;
  }

  // ---------------- 解析工具 ----------------

  /** 忽略命名空间前缀提取整段（如 <tt:Media>…</tt:Media>），用于分区解析 XAddr */
  private static sectionNs(xml: string, tag: string): string {
    if (xml === '') {
      return '';
    }
    const re = new RegExp(`<[a-zA-Z0-9]*:?${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</[a-zA-Z0-9]*:?${tag}>`);
    const m = re.exec(xml);
    return m !== null ? m[1] : '';
  }

  private static tagTextNs(xml: string, tag: string): string {
    if (xml === '') {
      return '';
    }
    const re = new RegExp(`<[a-zA-Z0-9]*:?${tag}[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?${tag}>`);
    const m = re.exec(xml);
    return m !== null ? m[1].trim() : '';
  }

  private static firstProfileToken(xml: string): string {
    const m = xml.match(/<[a-zA-Z0-9]*:?Profiles[^>]*\stoken="([^"]+)"/);
    return m !== null ? m[1] : '';
  }

  /** GetPresetsResponse：<tptz:Preset token="..."><tt:Name>…</tt:Name>… */
  private static parsePresets(xml: string): PtzPreset[] {
    const out: PtzPreset[] = [];
    if (xml === '') {
      return out;
    }
    const re = new RegExp('<[a-zA-Z0-9]*:?Preset\\s[^>]*token="([^"]+)"[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?Preset>', 'g');
    let m = re.exec(xml);
    while (m !== null) {
      const p = new PtzPreset();
      p.token = m[1];
      p.name = OnvifSession.tagTextNs(m[2], 'Name');
      if (p.name === '') {
        p.name = `预置位 ${out.length + 1}`;
      }
      out.push(p);
      m = re.exec(xml);
    }
    return out;
  }

  private static replacePath(url: string, path: string): string {
    const m = url.match(/^(https?:\/\/[^\/]+)/);
    return m !== null ? m[1] + path : url;
  }

  private static xmlEscape(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
