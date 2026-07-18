import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { rstr } from './I18nUtils';

const TAG = 'StreamConfig';

export interface RtmpDefaultConfig {
  url: string;
  streamKey: string;
  username: string;
  password: string;
  port: number;
}

export interface HlsDefaultConfig {
  name: string;
  url: string;
}

export interface StreamDefaultConfig {
  rtmp: RtmpDefaultConfig;
  hls: HlsDefaultConfig;
}

const DEFAULT_CONFIG: StreamDefaultConfig = {
  rtmp: {
    url: 'rtmp://www.razor51.site/live/3/livestream',
    streamKey: 'secret=0f6c7ea45242453eaa843dacafc241a6',
    username: '',
    password: '',
    port: 1935,
  },
  hls: {
    name: '',
    url: 'http://www.razor51.site:2022/live/1/livestream.m3u8',
  },
};

export async function loadStreamConfig(context: common.Context): Promise<StreamDefaultConfig> {
  try {
    const rm = context.resourceManager;
    const rawContent = await rm.getRawFileContent('stream_config.json');
    const decoder = util.TextDecoder.create('utf-8');
    const text = decoder.decodeToString(rawContent);
    const json = JSON.parse(text) as StreamDefaultConfig;
    console.info(`${TAG} loaded stream_config.json: rtmp.url=${json.rtmp.url}, hls.url=${json.hls.url}`);
    const result: StreamDefaultConfig = {
      rtmp: {
        url: json.rtmp.url || DEFAULT_CONFIG.rtmp.url,
        streamKey: json.rtmp.streamKey || DEFAULT_CONFIG.rtmp.streamKey,
        username: json.rtmp.username || DEFAULT_CONFIG.rtmp.username,
        password: json.rtmp.password || DEFAULT_CONFIG.rtmp.password,
        port: json.rtmp.port || DEFAULT_CONFIG.rtmp.port,
      },
      hls: {
        name: json.hls.name || rstr(context, 'default_hls_name'),
        url: json.hls.url || DEFAULT_CONFIG.hls.url,
      },
    };
    return result;
  } catch (e) {
    console.warn(`${TAG} failed to load stream_config.json, using built-in defaults: ${(e as Error).message}`);
    const fallback: StreamDefaultConfig = {
      rtmp: DEFAULT_CONFIG.rtmp,
      hls: {
        name: rstr(context, 'default_hls_name'),
        url: DEFAULT_CONFIG.hls.url,
      },
    };
    return fallback;
  }
}
