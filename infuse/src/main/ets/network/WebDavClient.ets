/**
 * WebDavClient.ets - WebDAV 客户端
 *
 * 仅实现媒体浏览所需的最小子集：
 *   PROPFIND (Depth: 1) 列目录 → DavEntry[]
 * 播放不下载文件，直接把带 Basic Auth 的文件 URL 交给 AVPlayer 流式播放。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DavEntry, WebDavSource, isVideoFile } from '../model/Models';

const TAG = 'WebDavClient';

export class WebDavClient {
  /** Basic 认证头值 */
  static authHeader(src: WebDavSource): string {
    if (src.username === '') {
      return '';
    }
    const bytes = new util.TextEncoder().encodeInto(`${src.username}:${src.password}`);
    return 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes);
  }

  /**
   * 列出 path（相对 baseUrl，'' 或 '/' 表示根）下的条目。
   * 仅返回子目录与视频文件；失败返回 null。
   */
  static async list(src: WebDavSource, path: string): Promise<DavEntry[] | null> {
    const url = WebDavClient.joinUrl(src.baseUrl, path);
    const req = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Depth': '1',
        'Content-Type': 'application/xml'
      };
      const auth = WebDavClient.authHeader(src);
      if (auth !== '') {
        headers['Authorization'] = auth;
      }
      const resp = await req.request(url, {
        method: 'PROPFIND' as http.RequestMethod,
        header: headers,
        extraData: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>' +
          '<d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>',
        connectTimeout: 8000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode !== 207 && resp.responseCode !== 200) {
        hilog.warn(0x0001, TAG, 'PROPFIND %{public}s -> %{public}d', url, resp.responseCode);
        return null;
      }
      return WebDavClient.parseMultiStatus(resp.result as string, src.baseUrl, path);
    } catch (e) {
      hilog.error(0x0001, TAG, 'PROPFIND error: %{public}s', JSON.stringify(e));
      return null;
    } finally {
      req.destroy();
    }
  }

  /** 拼出可直接播放的文件完整 URL */
  static fileUrl(src: WebDavSource, path: string): string {
    return WebDavClient.joinUrl(src.baseUrl, path);
  }

  // ---------------- 内部 ----------------

  private static joinUrl(base: string, path: string): string {
    const b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    if (path === '' || path === '/') {
      return b + '/';
    }
    return path.startsWith('/') ? b + path : b + '/' + path;
  }

  /**
   * 解析 207 Multi-Status。用忽略命名空间前缀的正则逐 <response> 块提取
   * href / collection / getcontentlength。
   */
  private static parseMultiStatus(xml: string, baseUrl: string, requestPath: string): DavEntry[] {
    const entries: DavEntry[] = [];
    const basePrefix = WebDavClient.pathOfUrl(baseUrl).replace(/\/$/, '');

    const responseRe = new RegExp('<[a-zA-Z0-9]*:?response[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?response>', 'g');
    const hrefRe = new RegExp('<[a-zA-Z0-9]*:?href[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?href>');
    const lenRe = new RegExp('<[a-zA-Z0-9]*:?getcontentlength[^>]*>([\\s\\S]*?)</[a-zA-Z0-9]*:?getcontentlength>');

    const reqNorm = WebDavClient.normalizeDir(requestPath);
    let m: RegExpExecArray | null = responseRe.exec(xml);
    while (m !== null) {
      const block = m[1];
      const hrefM = hrefRe.exec(block);
      if (hrefM !== null) {
        const href = WebDavClient.decodeHref(hrefM[1].trim());
        let rel = WebDavClient.pathOfUrl(href);
        if (basePrefix !== '' && rel.startsWith(basePrefix)) {
          rel = rel.substring(basePrefix.length);
        }
        if (!rel.startsWith('/')) {
          rel = '/' + rel;
        }
        const isDir = block.toLowerCase().includes('collection');
        const relNorm = isDir ? WebDavClient.normalizeDir(rel) : rel;
        // 跳过请求目录自身
        if (!(isDir && relNorm === reqNorm)) {
          const name = WebDavClient.lastSegment(rel);
          if (name !== '' && !name.startsWith('.') && (isDir || isVideoFile(name))) {
            const entry = new DavEntry();
            entry.name = name;
            entry.path = relNorm;
            entry.isDir = isDir;
            const lenM = lenRe.exec(block);
            entry.sizeBytes = lenM !== null ? Number(lenM[1].trim()) : 0;
            entries.push(entry);
          }
        }
      }
      m = responseRe.exec(xml);
    }
    entries.sort((a: DavEntry, b: DavEntry) => {
      if (a.isDir !== b.isDir) {
        return a.isDir ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });
    return entries;
  }

  private static normalizeDir(p: string): string {
    let s = p === '' ? '/' : p;
    if (!s.startsWith('/')) {
      s = '/' + s;
    }
    if (!s.endsWith('/')) {
      s = s + '/';
    }
    return s;
  }

  private static pathOfUrl(url: string): string {
    const m = url.match(/^https?:\/\/[^\/]+(\/.*)?$/);
    if (m !== null) {
      return m[1] ?? '/';
    }
    return url; // 已是路径
  }

  private static lastSegment(path: string): string {
    const p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    const i = p.lastIndexOf('/');
    return i >= 0 ? p.substring(i + 1) : p;
  }

  private static decodeHref(href: string): string {
    try {
      return decodeURIComponent(href);
    } catch (e) {
      return href;
    }
  }
}
