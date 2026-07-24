export const createEncoder: (width: number, height: number, bitrate: number, framerate: number, callback: (frame: EncodedFrame) => void) => string;
export const startEncoder: () => void;
export const stopEncoder: () => void;
export const releaseEncoder: () => void;

export interface EncodedFrame {
  data: ArrayBuffer;
  pts: number;
  flags: number;
  isKeyFrame: boolean;
}

export const createAudioEncoder: (sampleRate: number, channelCount: number, bitrate: number, callback: (frame: AacFrame) => void) => string;
export const startAudioEncoder: () => void;
export const stopAudioEncoder: () => void;
export const releaseAudioEncoder: () => void;
export const setAudioEncoderMuted: (muted: boolean) => void;

export interface AacFrame {
  data: ArrayBuffer;
  pts: number;
  isConfig: boolean;
}
