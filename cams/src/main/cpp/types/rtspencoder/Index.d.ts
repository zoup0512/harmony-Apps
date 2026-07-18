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
