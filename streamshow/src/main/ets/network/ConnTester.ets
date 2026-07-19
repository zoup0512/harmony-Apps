/**
 * ConnTester.ets - 连接测试与延迟诊断
 *
 * rtsp:// 目标：TCP 连接到 host:port（默认 554），测量建连耗时；
 * http(s):// 目标：HTTP GET，测量耗时并返回状态码。
 */
import { socket } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { TestResult } from '../model/Models';

export class ConnTester {
  static async test(url: string, authHeader: string): Promise<TestResult> {
    const r = new TestResult();
    if (url.startsWith('rtsp://')) {
      return ConnTester.testTcp(url, r);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ConnTester.testHttp(url, authHeader, r);
    }
    r.detail = '仅支持 rtsp:// 或 http(s):// 地址';
    return r;
  }

  /** 解析 rtsp url 的 host:port 并做 TCP 建连测速 */
  private static async testTcp(url: string, r: TestResult): Promise<TestResult> {
    const m = url.match(/^rtsp:\/\/(?:[^@\/]+@)?([^\/:]+)(?::(\d+))?/);
    if (m === null) {
      r.detail = 'RTSP 地址格式无效';
      return r;
    }
    const host = m[1];
    const port = m[2] !== undefined ? Number(m[2]) : 554;
    const tcp = socket.constructTCPSocketInstance();
    const start = Date.now();
    try {
      await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 } as socket.NetAddress);
      await ConnTester.withTimeout(tcp.connect({
        address: { address: host, port: port, family: 1 } as socket.NetAddress,
        timeout: 5000
      }), 5000);
      r.connectMs = Date.now() - start;
      r.ok = true;
      r.detail = `TCP ${host}:${port} 可达，建连 ${r.connectMs} ms`
        + (r.connectMs < 50 ? '（同网段，极佳）' : (r.connectMs < 200 ? '（良好）' : '（偏慢，检查网络）'));
    } catch (e) {
      r.detail = `TCP ${host}:${port} 连接失败：检查 IP/端口/防火墙`;
    } finally {
      try {
        tcp.close();
      } catch (e) { /* ignore */
      }
    }
    return r;
  }

  private static async testHttp(url: string, authHeader: string, r: TestResult): Promise<TestResult> {
    const req = http.createHttp();
    const start = Date.now();
    try {
      const headers: Record<string, string> = { 'Range': 'bytes=0-0' };
      if (authHeader !== '') {
        headers['Authorization'] = authHeader;
      }
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 5000,
        readTimeout: 5000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      r.connectMs = Date.now() - start;
      r.httpCode = resp.responseCode;
      r.ok = resp.responseCode >= 200 && resp.responseCode < 400;
      r.detail = r.ok
        ? `HTTP ${resp.responseCode}，响应 ${r.connectMs} ms`
        : (resp.responseCode === 401 ? 'HTTP 401：账号或密码错误' : `HTTP ${resp.responseCode}`);
    } catch (e) {
      r.detail = '请求失败：检查地址与网络';
    } finally {
      req.destroy();
    }
    return r;
  }

  private static withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const t = setTimeout(() => {
        reject(new Error('timeout'));
      }, ms);
      p.then((v: T) => {
        clearTimeout(t);
        resolve(v);
      }).catch((e: Object) => {
        clearTimeout(t);
        reject(e);
      });
    });
  }
}
