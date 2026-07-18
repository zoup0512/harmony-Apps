import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { DiscoveredDevice, DeviceType } from '../model/BrowseModels';
import { probeOnvifDevices, OnvifDevice } from './OnvifDiscovery';
import { rstr } from './I18nUtils';

export class NetworkDiscoveryService {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async discoverAll(): Promise<DiscoveredDevice[]> {
    const all: DiscoveredDevice[] = [];
    try {
      const onvifDevices = await probeOnvifDevices(4000);
      for (const dev of onvifDevices) {
        all.push({
          id: generateUUID(),
          name: this.getDisplayName(dev),
          url: dev.xaddr,
          host: dev.host,
          port: dev.port ? parseInt(dev.port) : 80,
          type: DeviceType.RTSP_CAMERA,
          description: rstr(this.context, 'onvif_device'),
        });
      }
    } catch {
      // ignore
    }
    return all;
  }

  private getDisplayName(dev: OnvifDevice): string {
    const nameScope = dev.scopes.find(s => s.includes('/name/'));
    if (nameScope) {
      const name = nameScope.split('/name/').pop();
      if (name) return decodeURIComponent(name);
    }
    const hardwareScope = dev.scopes.find(s => s.includes('/hardware/'));
    if (hardwareScope) {
      const hw = hardwareScope.split('/hardware/').pop();
      if (hw) return decodeURIComponent(hw);
    }
    return dev.host;
  }
}

function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}
