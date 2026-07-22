/**
 * NetworkUtil.ets - 网络工具
 * 通过 WiFi 信息拿到本机 IPv4，用于拼接局域网访问地址。
 */
import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NetworkUtil';

export class NetworkUtil {
  /** 返回点分十进制 IPv4；失败返回空串 */
  static getLocalIp(): string {
    try {
      if (!wifiManager.isConnected()) {
        return '';
      }
      const info = wifiManager.getIpInfo();
      return NetworkUtil.intToIp(info.ipAddress);
    } catch (e) {
      hilog.error(0x0001, TAG, 'getLocalIp error: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /** wifiManager 返回的 ipAddress 是 32 位整数（大端），转点分格式 */
  private static intToIp(ip: number): string {
    if (ip <= 0) {
      return '';
    }
    const b0 = (ip >> 24) & 0xff;
    const b1 = (ip >> 16) & 0xff;
    const b2 = (ip >> 8) & 0xff;
    const b3 = ip & 0xff;
    return `${b0}.${b1}.${b2}.${b3}`;
  }
}
