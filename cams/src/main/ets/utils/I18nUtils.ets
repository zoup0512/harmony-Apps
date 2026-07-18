import { common } from '@kit.AbilityKit';

export function rstr(context: common.Context, name: string, ...params: string[]): string {
  try {
    let value: string = context.resourceManager.getStringByNameSync(name);
    if (params.length > 0) {
      for (const p of params) {
        value = value.replace('%s', p);
      }
    }
    return value;
  } catch (e) {
    console.error(`rstr failed for '${name}': ${(e as Error).message}`);
    return name;
  }
}

export function rstrNum(context: common.Context, name: string, ...params: number[]): string {
  try {
    let value: string = context.resourceManager.getStringByNameSync(name);
    if (params.length > 0) {
      for (const p of params) {
        value = value.replace('%d', String(p));
      }
    }
    return value;
  } catch (e) {
    console.error(`rstrNum failed for '${name}': ${(e as Error).message}`);
    return name;
  }
}
