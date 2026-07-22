/**
 * OnvifClient.ets - ONVIF SOAP 客户端
 *
 * 面向"发现后取 RTSP 地址"的最小实现：
 *   1. GetCapabilities（设备服务）→ Media 服务地址
 *   2. GetProfiles（媒体服务）→ 首个 Profile token
 *   3. GetStreamUri → RTSP 地址
 * 鉴权采用 WS-Security UsernameToken PasswordDigest：
 *   Digest = Base64( SHA1( nonce + created + password ) )
 * 用 @kit.CryptoArchitectureKit 计算 SHA1。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'OnvifClient';

export class OnvifClient {
  /**
   * 一站式：从设备服务地址取首个 Profile 的 RTSP 流地址。
   * 失败返回 ''。用户名可为空（部分设备允许匿名）。
   */
  static async fetchStreamUri(deviceXAddr: string, username: string, password: string): Promise<string> {
    // 1. GetCapabilities → Media XAddr
    const capBody = '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl">' +
      '<tds:Category>Media</tds:Category></tds:GetCapabilities>';
    const capResp = await OnvifClient.soap(deviceXAddr, capBody, username, password);
    let mediaXAddr = OnvifClient.tagTextNs(capResp, 'XAddr');
    if (mediaXAddr === '') {
      // 兜底：多数设备的媒体服务在固定路径
      mediaXAddr = OnvifClient.replacePath(deviceXAddr, '/onvif/media_service');
    }

    // 2. GetProfiles → 首个 profile token
    const profBody = '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>';
    const profResp = await OnvifClient.soap(mediaXAddr, profBody, username, password);
    const token = OnvifClient.firstProfileToken(profResp);
    if (token === '') {
      hilog.warn(0x0001, TAG, 'no profile token');
      return '';
    }

    // 3. GetStreamUri
    const uriBody = '<trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl">' +
      '<trt:StreamSetup>' +
      '<tt:Stream xmlns:tt="http://www.onvif.org/ver10/schema">RTP-Unicast</tt:Stream>' +
      '<tt:Transport xmlns:tt="http://www.onvif.org/ver10/schema">' +
      '<tt:Protocol>RTSP</tt:Protocol></tt:Transport>' +
      '</trt:StreamSetup>' +
      `<trt:ProfileToken>${token}</trt:ProfileToken>` +
      '</trt:GetStreamUri>';
    const uriResp = await OnvifClient.soap(mediaXAddr, uriBody, username, password);
    const uri = OnvifClient.tagTextNs(uriResp, 'Uri');
    return uri;
  }

  // ---------------- SOAP 基础 ----------------

  private static async soap(url: string, body: string, username: string, password: string): Promise<string> {
    const header = username !== '' ? await OnvifClient.securityHeader(username, password) : '';
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

  /** WS-Security UsernameToken（PasswordDigest） */
  private static async securityHeader(username: string, password: string): Promise<string> {
    const nonce = OnvifClient.randomBytes(16);
    const created = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const createdBytes = new util.TextEncoder().encodeInto(created);
    const passBytes = new util.TextEncoder().encodeInto(password);

    const all = new Uint8Array(nonce.length + createdBytes.length + passBytes.length);
    all.set(nonce, 0);
    all.set(createdBytes, nonce.length);
    all.set(passBytes, nonce.length + createdBytes.length);

    const digest = await OnvifClient.sha1(all);
    const b64 = new util.Base64Helper();
    const nonceB64 = b64.encodeToStringSync(nonce);
    const digestB64 = b64.encodeToStringSync(digest);

    return '<Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" s:mustUnderstand="true">' +
      '<UsernameToken>' +
      `<Username>${OnvifClient.xmlEscape(username)}</Username>` +
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

  private static tagTextNs(xml: string, tag: string): string {
    if (xml === '') {
      return '';
    }
    const re = new RegExp(`<[a-zA-Z0-9]*:?${tag}[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?${tag}>`);
    const m = re.exec(xml);
    return m !== null ? m[1].trim() : '';
  }

  /** GetProfilesResponse 中首个 Profiles token 属性 */
  private static firstProfileToken(xml: string): string {
    const m = xml.match(/<[a-zA-Z0-9]*:?Profiles[^>]*\stoken="([^"]+)"/);
    return m !== null ? m[1] : '';
  }

  private static replacePath(url: string, path: string): string {
    const m = url.match(/^(https?:\/\/[^\/]+)/);
    return m !== null ? m[1] + path : url;
  }

  private static xmlEscape(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
