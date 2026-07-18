import { socket, connection } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { rstr } from './I18nUtils';

const TAG = 'RtmpPushManager';

export type RtmpPushStatus = 'idle' | 'connecting' | 'handshaking' | 'handshake_done' | 'connecting_app' | 'connected' | 'publishing' | 'error' | 'disconnected';

export interface RtmpPushConfig {
  host: string;
  port: number;
  app: string;
  streamKey: string;
  username: string;
  password: string;
}

export interface ParsedRtmpUrl {
  host: string;
  port: number;
  app: string;
}

export function parseRtmpUrl(url: string): ParsedRtmpUrl {
  const withoutScheme = url.replace(/^rtmp:\/\//i, '');
  const slashIdx = withoutScheme.indexOf('/');
  const hostPort = slashIdx >= 0 ? withoutScheme.substring(0, slashIdx) : withoutScheme;
  const app = slashIdx >= 0 ? withoutScheme.substring(slashIdx + 1) : 'live';
  const colonIdx = hostPort.indexOf(':');
  const host = colonIdx >= 0 ? hostPort.substring(0, colonIdx) : hostPort;
  const port = colonIdx >= 0 ? parseInt(hostPort.substring(colonIdx + 1)) : 1935;
  const result: ParsedRtmpUrl = {
    host: host,
    port: port,
    app: app || 'live',
  };
  return result;
}

function strToBytes(str: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    const c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F)); }
    else { bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)); }
  }
  return new Uint8Array(bytes);
}

function writeU16BE(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >> 8) & 0xFF; buf[offset + 1] = value & 0xFF;
}
function writeU32BE(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >> 24) & 0xFF; buf[offset + 1] = (value >> 16) & 0xFF; buf[offset + 2] = (value >> 8) & 0xFF; buf[offset + 3] = value & 0xFF;
}
function readU32BE(buf: Uint8Array, offset: number): number {
  return ((buf[offset] << 24) | (buf[offset + 1] << 16) | (buf[offset + 2] << 8) | buf[offset + 3]) >>> 0;
}
function readU16BE(buf: Uint8Array, offset: number): number {
  return ((buf[offset] << 8) | buf[offset + 1]) & 0xFFFF;
}

class Amf0Encoder {
  private bytes: number[] = [];

  writeString(str: string): void {
    this.bytes.push(0x02);
    const sb = strToBytes(str);
    this.bytes.push((sb.length >> 8) & 0xFF, sb.length & 0xFF);
    for (let i = 0; i < sb.length; i++) this.bytes.push(sb[i]);
  }

  writeNumber(num: number): void {
    this.bytes.push(0x00);
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    view.setFloat64(0, num, false);
    const arr = new Uint8Array(buf);
    for (let i = 0; i < 8; i++) this.bytes.push(arr[i]);
  }

  writeBoolean(val: boolean): void {
    this.bytes.push(0x01, val ? 0x01 : 0x00);
  }

  writeNull(): void {
    this.bytes.push(0x05);
  }

  writeObjectBegin(): void {
    this.bytes.push(0x03);
  }

  writeObjectEnd(): void {
    this.bytes.push(0x00, 0x00, 0x09);
  }

  writePropertyName(name: string): void {
    const sb = strToBytes(name);
    this.bytes.push((sb.length >> 8) & 0xFF, sb.length & 0xFF);
    for (let i = 0; i < sb.length; i++) this.bytes.push(sb[i]);
  }

  getBytes(): Uint8Array {
    return new Uint8Array(this.bytes);
  }
}

class Amf0Decoder {
  private data: Uint8Array;
  private offset: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  hasMore(): boolean {
    return this.offset < this.data.length;
  }

  readString(): string | null {
    if (this.offset >= this.data.length) return null;
    const type = this.data[this.offset++];
    if (type !== 0x02) { this.offset--; return null; }
    return this.readRawString();
  }

  private readRawString(): string {
    const len = readU16BE(this.data, this.offset);
    this.offset += 2;
    let str = '';
    for (let i = 0; i < len; i++) {
      str += String.fromCharCode(this.data[this.offset + i]);
    }
    this.offset += len;
    return str;
  }

  readNumber(): number | null {
    if (this.offset >= this.data.length) return null;
    const type = this.data[this.offset++];
    if (type !== 0x00) { this.offset--; return null; }
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    for (let i = 0; i < 8; i++) view.setUint8(i, this.data[this.offset + i]);
    this.offset += 8;
    return view.getFloat64(0, false);
  }

  readNull(): void {
    if (this.offset < this.data.length && this.data[this.offset] === 0x05) {
      this.offset++;
    }
  }

  skipValue(): void {
    if (this.offset >= this.data.length) return;
    const type = this.data[this.offset++];
    switch (type) {
      case 0x00: this.offset += 8; break;
      case 0x01: this.offset += 1; break;
      case 0x02: { const len = readU16BE(this.data, this.offset); this.offset += 2 + len; break; }
      case 0x03: this.skipObject(); break;
      case 0x05: break;
      case 0x08: this.offset += 4; this.skipObject(); break;
      case 0x0A: { const count = readU32BE(this.data, this.offset); this.offset += 4; for (let i = 0; i < count; i++) this.skipValue(); break; }
      default: break;
    }
  }

  private skipObject(): void {
    while (this.offset < this.data.length - 2) {
      if (this.data[this.offset] === 0x00 && this.data[this.offset + 1] === 0x00 && this.data[this.offset + 2] === 0x09) {
        this.offset += 3;
        return;
      }
      const nameLen = readU16BE(this.data, this.offset);
      this.offset += 2 + nameLen;
      this.skipValue();
    }
  }

  readObject(): Map<string, string> | null {
    if (this.offset >= this.data.length) return null;
    const type = this.data[this.offset++];
    if (type !== 0x03 && type !== 0x08) { this.offset--; return null; }
    if (type === 0x08) this.offset += 4;
    const result = new Map<string, string>();
    while (this.offset < this.data.length - 2) {
      if (this.data[this.offset] === 0x00 && this.data[this.offset + 1] === 0x00 && this.data[this.offset + 2] === 0x09) {
        this.offset += 3;
        return result;
      }
      const name = this.readRawString();
      const valType = this.data[this.offset];
      if (valType === 0x02) {
        this.offset++;
        const val = this.readRawString();
        result.set(name, val);
      } else if (valType === 0x00) {
        const val = this.readNumber();
        if (val !== null) {
          result.set(name, val.toString());
        }
      } else if (valType === 0x01) {
        this.offset++;
        const boolVal = this.data[this.offset];
        this.offset++;
        result.set(name, boolVal ? 'true' : 'false');
      } else {
        this.skipValue();
      }
    }
    return result;
  }
}

interface ChunkParseState {
  fmt: number;
  csid: number;
  timestamp: number;
  messageLength: number;
  messageType: number;
  messageStreamId: number;
  bytesRead: number;
  payload: Uint8Array;
  hasHeader: boolean;
}

interface SocketInfo {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

export class RtmpPushManager {
  private tcpSocket: socket.TCPSocket | null = null;
  private status: RtmpPushStatus = 'idle';
  private config: RtmpPushConfig | null = null;
  private context: common.Context;
  private chunkSize: number = 4096;
  private serverChunkSize: number = 4096;
  private transactionId: number = 1;
  private streamId: number = 0;
  private publishing: boolean = false;
  private receiveBuffer: Uint8Array = new Uint8Array(0);
  private handshakePhase: boolean = true;
  private handshakeBytesNeeded: number = 3073;
  private sps: Uint8Array | null = null;
  private pps: Uint8Array | null = null;
  private sequenceHeaderSent: boolean = false;
  private chunkStates: Map<number, ChunkParseState> = new Map();
  private onStatusChange: ((status: RtmpPushStatus, message?: string) => void) | null = null;
  private startPts: number = 0;
  private hasFirstTimestamp: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  setContext(context: common.Context): void {
    this.context = context;
  }

  setOnStatusChange(cb: (status: RtmpPushStatus, message?: string) => void): void {
    this.onStatusChange = cb;
  }

  getStatus(): RtmpPushStatus {
    return this.status;
  }

  isPublishing(): boolean {
    return this.publishing;
  }

  private setStatus(status: RtmpPushStatus, message?: string): void {
    this.status = status;
    console.info(`${TAG} status: ${status}${message ? ' ' + message : ''}`);
    if (this.onStatusChange) {
      this.onStatusChange(status, message);
    }
  }

  async connect(config: RtmpPushConfig): Promise<void> {
    this.config = config;
    this.setStatus('connecting');
    this.resetState();

    try {
      this.tcpSocket = socket.constructTCPSocketInstance();
      this.tcpSocket.on('message', (info: SocketInfo) => {
        this.onSocketMessage(info.message);
      });
      this.tcpSocket.on('close', () => {
        console.info(`${TAG} socket closed`);
        if (this.status !== 'disconnected' && this.status !== 'idle') {
          this.setStatus('disconnected', rstr(this.context, 'rtmp_status_disconnected'));
        }
      });

      let ip = config.host;
      if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(ip)) {
        console.info(`${TAG} resolving hostname: ${config.host}`);
        const addresses = await connection.getAddressesByName(config.host);
        if (addresses && addresses.length > 0) {
          ip = addresses[0].address;
          console.info(`${TAG} resolved ${config.host} -> ${ip}`);
        } else {
          throw new Error(`DNS resolution failed for ${config.host}`);
        }
      }

      const localAddress: socket.NetAddress = {
        address: '0.0.0.0',
        port: 0,
        family: 1,
      };
      await this.tcpSocket.bind(localAddress);
      console.info(`${TAG} socket bound to local address`);

      const connectOptions: socket.TCPConnectOptions = {
        address: { address: ip, port: config.port, family: 1 },
      };

      let connected = false;

      this.tcpSocket.on('connect', () => {
        connected = true;
        console.info(`${TAG} TCP connect event received`);
      });

      try {
        await this.tcpSocket.connect(connectOptions);
        connected = true;
      } catch (e) {
        const err = e as Error;
        console.warn(`${TAG} connect promise rejected: ${err.message}, checking socket state...`);
        await new Promise<void>(resolve => setTimeout(resolve, 500));
        if (!connected) {
          try {
            const state = await this.tcpSocket.getState();
            console.info(`${TAG} socket state: isConnected=${state.isConnected}, isBound=${state.isBound}`);
            if (state.isConnected) {
              connected = true;
            }
          } catch (stateErr) {
            console.error(`${TAG} getState failed: ${(stateErr as Error).message}`);
          }
        }
        if (!connected) {
          const msg = err.message;
          if (msg.includes('115') || msg.includes('Operation in progress')) {
            throw new Error(rstr(this.context, 'rtmp_status_refused', config.host, String(config.port)));
          }
          throw err;
        }
      }

      console.info(`${TAG} TCP connected to ${config.host}:${config.port} (ip=${ip})`);
      this.setStatus('handshaking');
      await this.sendHandshake();
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} connect failed: ${err.message}`);
      this.setStatus('error', rstr(this.context, 'rtmp_status_connect_failed', err.message));
      throw err;
    }
  }

  private resetState(): void {
    this.receiveBuffer = new Uint8Array(0);
    this.handshakePhase = true;
    this.handshakeBytesNeeded = 3073;
    this.chunkStates.clear();
    this.transactionId = 1;
    this.streamId = 0;
    this.publishing = false;
    this.sps = null;
    this.pps = null;
    this.sequenceHeaderSent = false;
    this.hasFirstTimestamp = false;
  }

  private async sendHandshake(): Promise<void> {
    const c0c1 = new Uint8Array(1537);
    c0c1[0] = 0x03;
    const time = 0;
    writeU32BE(c0c1, 1, time);
    writeU32BE(c0c1, 5, 0);
    for (let i = 9; i < 1537; i++) {
      c0c1[i] = Math.floor(Math.random() * 256);
    }
    await this.sendData(c0c1.buffer.slice(c0c1.byteOffset, c0c1.byteOffset + c0c1.byteLength));
    console.info(`${TAG} sent C0+C1 (1537 bytes)`);
  }

  private async sendData(data: ArrayBuffer): Promise<void> {
    if (!this.tcpSocket) return;
    try {
      await this.tcpSocket.send({ data });
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} sendData failed: ${err.message}`);
    }
  }

  private async sendBytes(data: Uint8Array): Promise<void> {
    const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    await this.sendData(buf);
  }

  private onSocketMessage(data: ArrayBuffer): void {
    const incoming = new Uint8Array(data);
    const newBuf = new Uint8Array(this.receiveBuffer.length + incoming.length);
    newBuf.set(this.receiveBuffer, 0);
    newBuf.set(incoming, this.receiveBuffer.length);
    this.receiveBuffer = newBuf;

    if (this.handshakePhase) {
      this.processHandshake();
    } else {
      this.processChunks();
    }
  }

  private processHandshake(): void {
    if (this.receiveBuffer.length < this.handshakeBytesNeeded) return;

    const s0s1s2 = this.receiveBuffer.subarray(0, this.handshakeBytesNeeded);
    const s0 = s0s1s2[0];
    if (s0 !== 0x03) {
      console.error(`${TAG} invalid server version: ${s0}`);
      this.setStatus('error', rstr(this.context, 'rtmp_status_version_incompatible'));
      return;
    }

    const s1 = s0s1s2.subarray(1, 1537);
    const c2 = new Uint8Array(1536);
    c2.set(s1, 0);
    this.sendBytes(c2);

    this.receiveBuffer = this.receiveBuffer.subarray(this.handshakeBytesNeeded);
    this.handshakePhase = false;
    console.info(`${TAG} handshake complete, sent C2`);
    this.setStatus('handshake_done');

    this.sendInitialCommands().catch((e: Error) => {
      console.error(`${TAG} sendInitialCommands failed: ${e.message}`);
      this.setStatus('error', rstr(this.context, 'rtmp_status_init_failed', e.message));
    });
  }

  private async sendInitialCommands(): Promise<void> {
    await this.sendSetChunkSize(4096);
    await this.sendWindowAckSize(2500000);
    await this.sendConnect();
  }

  private async sendSetChunkSize(size: number): Promise<void> {
    const payload = new Uint8Array(4);
    writeU32BE(payload, 0, size);
    this.chunkSize = size;
    await this.sendChunkMessage(2, 1, 0, payload, 0);
    console.info(`${TAG} sent SetChunkSize: ${size}`);
  }

  private async sendWindowAckSize(size: number): Promise<void> {
    const payload = new Uint8Array(4);
    writeU32BE(payload, 0, size);
    await this.sendChunkMessage(2, 5, 0, payload, 0);
  }

  private async sendConnect(): Promise<void> {
    if (!this.config) return;
    const tcUrl = this.config.username !== ''
      ? `rtmp://${this.config.username}:${this.config.password}@${this.config.host}:${this.config.port}/${this.config.app}`
      : `rtmp://${this.config.host}:${this.config.port}/${this.config.app}`;

    const enc = new Amf0Encoder();
    enc.writeString('connect');
    enc.writeNumber(1);
    enc.writeObjectBegin();
    enc.writePropertyName('app'); enc.writeString(this.config.app);
    enc.writePropertyName('flashVer'); enc.writeString('FMLE/3.0 (compatible; FMSc/1.0)');
    enc.writePropertyName('tcUrl'); enc.writeString(tcUrl);
    enc.writePropertyName('fpad'); enc.writeBoolean(false);
    enc.writePropertyName('capabilities'); enc.writeNumber(15);
    enc.writePropertyName('audioCodecs'); enc.writeNumber(4071);
    enc.writePropertyName('videoCodecs'); enc.writeNumber(252);
    enc.writePropertyName('videoFunction'); enc.writeNumber(1);
    enc.writeObjectEnd();

    this.setStatus('connecting_app');
    await this.sendChunkMessage(3, 20, 0, enc.getBytes(), 0);
    console.info(`${TAG} sent connect command, tcUrl=${tcUrl}`);
  }

  private async sendCreateStream(): Promise<void> {
    this.transactionId++;
    const enc = new Amf0Encoder();
    enc.writeString('createStream');
    enc.writeNumber(this.transactionId);
    enc.writeNull();
    await this.sendChunkMessage(3, 20, 0, enc.getBytes(), 0);
    console.info(`${TAG} sent createStream, txnId=${this.transactionId}`);
  }

  private async sendPublish(): Promise<void> {
    if (!this.config) return;
    this.transactionId++;
    const enc = new Amf0Encoder();
    enc.writeString('publish');
    enc.writeNumber(this.transactionId);
    enc.writeNull();
    enc.writeString(this.config.streamKey);
    enc.writeString('live');
    await this.sendChunkMessage(3, 20, this.streamId, enc.getBytes(), 0);
    console.info(`${TAG} sent publish, streamKey=${this.config.streamKey}, streamId=${this.streamId}`);
  }

  private async sendChunkMessage(
    csid: number, msgType: number, msid: number, payload: Uint8Array, timestamp: number
  ): Promise<void> {
    const chunks: Uint8Array[] = [];
    let offset = 0;
    const totalLen = payload.length;
    const ts = timestamp & 0x7FFFFFFF;
    const useExtTs = ts >= 0xFFFFFF;

    while (offset < totalLen) {
      const remaining = totalLen - offset;
      const chunkLen = Math.min(remaining, this.chunkSize);
      const isFirst = offset === 0;

      const headerBytes: number[] = [];
      if (isFirst) {
        headerBytes.push((0 << 6) | (csid & 0x3F));
        if (useExtTs) {
          headerBytes.push(0xFF, 0xFF, 0xFF);
        } else {
          headerBytes.push((ts >> 16) & 0xFF, (ts >> 8) & 0xFF, ts & 0xFF);
        }
        headerBytes.push((totalLen >> 16) & 0xFF, (totalLen >> 8) & 0xFF, totalLen & 0xFF);
        headerBytes.push(msgType & 0xFF);
        const msidBuf = new Uint8Array(4);
        msidBuf[0] = msid & 0xFF;
        msidBuf[1] = (msid >> 8) & 0xFF;
        msidBuf[2] = (msid >> 16) & 0xFF;
        msidBuf[3] = (msid >> 24) & 0xFF;
        for (let i = 0; i < 4; i++) headerBytes.push(msidBuf[i]);
        if (useExtTs) {
          headerBytes.push((ts >> 24) & 0xFF, (ts >> 16) & 0xFF, (ts >> 8) & 0xFF, ts & 0xFF);
        }
      } else {
        headerBytes.push((3 << 6) | (csid & 0x3F));
        if (useExtTs) {
          headerBytes.push((ts >> 24) & 0xFF, (ts >> 16) & 0xFF, (ts >> 8) & 0xFF, ts & 0xFF);
        }
      }

      const chunk = new Uint8Array(headerBytes.length + chunkLen);
      chunk.set(new Uint8Array(headerBytes), 0);
      chunk.set(payload.subarray(offset, offset + chunkLen), headerBytes.length);
      chunks.push(chunk);
      offset += chunkLen;
    }

    const totalChunkLen = chunks.reduce((sum, c) => sum + c.length, 0);
    const result = new Uint8Array(totalChunkLen);
    let pos = 0;
    for (const c of chunks) {
      result.set(c, pos);
      pos += c.length;
    }
    await this.sendBytes(result);
  }

  private processChunks(): void {
    while (this.receiveBuffer.length > 0) {
      const consumed = this.tryParseChunk();
      if (consumed <= 0) break;
      this.receiveBuffer = this.receiveBuffer.subarray(consumed);
    }
  }

  private tryParseChunk(): number {
    const buf = this.receiveBuffer;
    if (buf.length < 1) return 0;

    let pos = 0;
    const firstByte = buf[pos++];
    const fmt = (firstByte >> 6) & 0x03;
    let csid = firstByte & 0x3F;

    if (csid === 0) {
      if (buf.length < 2) return 0;
      csid = buf[pos++] + 64;
    } else if (csid === 1) {
      if (buf.length < 3) return 0;
      csid = buf[pos++] + (buf[pos++] << 8) + 64;
    }

    let state = this.chunkStates.get(csid);
    if (!state) {
      state = {
        fmt: 0, csid, timestamp: 0, messageLength: 0, messageType: 0,
        messageStreamId: 0, bytesRead: 0, payload: new Uint8Array(0), hasHeader: false,
      };
      this.chunkStates.set(csid, state);
    }

    if (fmt === 0) {
      if (buf.length < pos + 11) return 0;
      state.timestamp = (buf[pos] << 16) | (buf[pos + 1] << 8) | buf[pos + 2];
      pos += 3;
      state.messageLength = (buf[pos] << 16) | (buf[pos + 1] << 8) | buf[pos + 2];
      pos += 3;
      state.messageType = buf[pos++];
      state.messageStreamId = buf[pos] | (buf[pos + 1] << 8) | (buf[pos + 2] << 16) | (buf[pos + 3] << 24);
      pos += 4;
      state.hasHeader = true;
      if (state.timestamp === 0xFFFFFF) {
        if (buf.length < pos + 4) return 0;
        state.timestamp = readU32BE(buf, pos);
        pos += 4;
      }
      state.payload = new Uint8Array(state.messageLength);
      state.bytesRead = 0;
    } else if (fmt === 1) {
      if (buf.length < pos + 7) return 0;
      const delta = (buf[pos] << 16) | (buf[pos + 1] << 8) | buf[pos + 2];
      pos += 3;
      state.messageLength = (buf[pos] << 16) | (buf[pos + 1] << 8) | buf[pos + 2];
      pos += 3;
      state.messageType = buf[pos++];
      state.timestamp += delta;
      state.hasHeader = true;
      if (delta === 0xFFFFFF) {
        if (buf.length < pos + 4) return 0;
        state.timestamp = readU32BE(buf, pos);
        pos += 4;
      }
      state.payload = new Uint8Array(state.messageLength);
      state.bytesRead = 0;
    } else if (fmt === 2) {
      if (buf.length < pos + 3) return 0;
      const delta = (buf[pos] << 16) | (buf[pos + 1] << 8) | buf[pos + 2];
      pos += 3;
      state.timestamp += delta;
      state.hasHeader = true;
      if (delta === 0xFFFFFF) {
        if (buf.length < pos + 4) return 0;
        state.timestamp = readU32BE(buf, pos);
        pos += 4;
      }
      state.payload = new Uint8Array(state.messageLength);
      state.bytesRead = 0;
    } else if (fmt === 3) {
      if (!state.hasHeader) return 0;
    }

    if (!state.hasHeader) return 0;

    const remaining = state.messageLength - state.bytesRead;
    const available = Math.min(remaining, this.serverChunkSize, buf.length - pos);
    if (available <= 0) return 0;
    if (buf.length < pos + available) return 0;

    state.payload.set(buf.subarray(pos, pos + available), state.bytesRead);
    state.bytesRead += available;
    pos += available;

    if (state.bytesRead >= state.messageLength) {
      const msgPayload = new Uint8Array(state.payload);
      const msgType = state.messageType;
      const msid = state.messageStreamId;
      const ts = state.timestamp;
      state.bytesRead = 0;
      state.hasHeader = false;
      this.handleMessage(msgType, msid, ts, msgPayload);
    }

    return pos;
  }

  private handleMessage(msgType: number, msid: number, timestamp: number, payload: Uint8Array): void {
    switch (msgType) {
      case 1:
        this.serverChunkSize = readU32BE(payload, 0);
        console.info(`${TAG} server SetChunkSize: ${this.serverChunkSize}`);
        break;
      case 5:
        console.info(`${TAG} server WindowAckSize: ${readU32BE(payload, 0)}`);
        break;
      case 6:
        console.info(`${TAG} server SetPeerBandwidth: ${readU32BE(payload, 0)}`);
        this.sendAcknowledgement(0).catch(() => {});
        break;
      case 20:
        this.handleCommandMessage(payload);
        break;
      default:
        break;
    }
  }

  private async sendAcknowledgement(sequence: number): Promise<void> {
    const payload = new Uint8Array(4);
    writeU32BE(payload, 0, sequence);
    await this.sendChunkMessage(2, 3, 0, payload, 0);
  }

  private handleCommandMessage(payload: Uint8Array): void {
    const decoder = new Amf0Decoder(payload);
    const cmdName = decoder.readString();
    if (!cmdName) return;

    console.info(`${TAG} command: ${cmdName}`);

    if (cmdName === '_result') {
      const txnId = decoder.readNumber();
      if (txnId === null) return;

      if (txnId === 1) {
        decoder.readNull();
        const props = decoder.readObject();
        if (props) {
          console.info(`${TAG} connect props: ${JSON.stringify(Array.from(props.entries()))}`);
        }
        const info = decoder.readObject();
        if (info) {
          const level = info.get('level');
          const code = info.get('code');
          console.info(`${TAG} connect result: level=${level}, code=${code}`);
          if (code === 'NetConnection.Connect.Success' || level === 'status') {
            this.setStatus('connected');
            this.sendCreateStream().catch((e: Error) => {
              console.error(`${TAG} sendCreateStream failed: ${e.message}`);
            });
          } else {
            this.setStatus('error', rstr(this.context, 'rtmp_status_rejected', code ?? level ?? 'unknown'));
          }
        } else if (props) {
          const level = props.get('level');
          const code = props.get('code');
          console.info(`${TAG} connect result from props: level=${level}, code=${code}`);
          if (code === 'NetConnection.Connect.Success' || level === 'status') {
            this.setStatus('connected');
            this.sendCreateStream().catch((e: Error) => {
              console.error(`${TAG} sendCreateStream failed: ${e.message}`);
            });
          } else {
            this.setStatus('error', rstr(this.context, 'rtmp_status_rejected', code ?? level ?? 'unknown'));
          }
        }
      } else if (txnId === 2) {
        decoder.readNull();
        const sid = decoder.readNumber();
        if (sid !== null) {
          this.streamId = Math.floor(sid);
          console.info(`${TAG} got streamId: ${this.streamId}`);
          this.sendPublish().catch((e: Error) => {
            console.error(`${TAG} sendPublish failed: ${e.message}`);
          });
        }
      }
    } else if (cmdName === 'onStatus') {
      decoder.readNumber();
      decoder.readNull();
      const info = decoder.readObject();
      if (info) {
        const code = info.get('code');
        console.info(`${TAG} onStatus: code=${code}`);
        if (code === 'NetStream.Publish.Start') {
          this.publishing = true;
          this.sequenceHeaderSent = false;
          this.setStatus('publishing', rstr(this.context, 'rtmp_status_publish_started'));
        } else if (code === 'NetStream.Publish.BadName') {
          this.setStatus('error', rstr(this.context, 'rtmp_status_name_in_use'));
        } else if (code === 'NetStream.Failed') {
          this.setStatus('error', rstr(this.context, 'rtmp_status_publish_failed'));
        }
      }
    }
  }

  setSps(sps: Uint8Array): void {
    this.sps = new Uint8Array(sps);
    console.info(`${TAG} SPS set, len=${sps.length}`);
  }

  setPps(pps: Uint8Array): void {
    this.pps = new Uint8Array(pps);
    console.info(`${TAG} PPS set, len=${pps.length}`);
  }

  sendH264Data(nalu: Uint8Array, pts: number): void {
    if (!this.publishing) return;

    const naluType = nalu.length > 0 ? nalu[0] & 0x1F : 0;

    if (naluType === 7) {
      this.sps = new Uint8Array(nalu);
      this.sendSequenceHeader();
      return;
    }

    if (naluType === 8) {
      this.pps = new Uint8Array(nalu);
      this.sendSequenceHeader();
      return;
    }

    if (naluType === 5 || naluType === 1) {
      if (!this.hasFirstTimestamp) {
        this.startPts = pts;
        this.hasFirstTimestamp = true;
      }
      const timestampMs = Math.floor((pts - this.startPts) / 1000000) & 0x7FFFFFFF;
      const isKeyFrame = naluType === 5;

      if (isKeyFrame) {
        this.sendSequenceHeader();
      }

      this.sendVideoNalu(nalu, timestampMs, isKeyFrame);
    }
  }

  private sendSequenceHeader(): void {
    if (!this.sps || !this.pps || !this.publishing) return;

    const sps = this.sps;
    const pps = this.pps;

    const configRecord = new Uint8Array(11 + sps.length + 2 + pps.length + 2);
    let pos = 0;
    configRecord[pos++] = 1;
    configRecord[pos++] = sps.length > 1 ? sps[1] : 0x42;
    configRecord[pos++] = sps.length > 2 ? sps[2] : 0x00;
    configRecord[pos++] = sps.length > 3 ? sps[3] : 0x1F;
    configRecord[pos++] = 0xFF;
    configRecord[pos++] = 0xE1;
    writeU16BE(configRecord, pos, sps.length);
    pos += 2;
    configRecord.set(sps, pos);
    pos += sps.length;
    configRecord[pos++] = 1;
    writeU16BE(configRecord, pos, pps.length);
    pos += 2;
    configRecord.set(pps, pos);

    const tagData = new Uint8Array(5 + configRecord.length);
    tagData[0] = 0x17;
    tagData[1] = 0x00;
    tagData[2] = 0x00;
    tagData[3] = 0x00;
    tagData[4] = 0x00;
    tagData.set(configRecord, 5);

    this.sendChunkMessage(4, 9, this.streamId, tagData, 0).catch((e: Error) => {
      console.error(`${TAG} sendSequenceHeader failed: ${e.message}`);
    });
    this.sequenceHeaderSent = true;
    console.info(`${TAG} sent AVC sequence header`);
  }

  private sendVideoNalu(nalu: Uint8Array, timestampMs: number, isKeyFrame: boolean): void {
    const naluLen = nalu.length;
    const tagData = new Uint8Array(5 + 4 + naluLen);
    tagData[0] = isKeyFrame ? 0x17 : 0x27;
    tagData[1] = 0x01;
    tagData[2] = 0x00;
    tagData[3] = 0x00;
    tagData[4] = 0x00;
    writeU32BE(tagData, 5, naluLen);
    tagData.set(nalu, 9);

    this.sendChunkMessage(4, 9, this.streamId, tagData, timestampMs).catch((e: Error) => {
      console.error(`${TAG} sendVideoNalu failed: ${e.message}`);
    });
  }

  async disconnect(): Promise<void> {
    this.publishing = false;
    this.setStatus('disconnected');

    if (this.tcpSocket) {
      try {
        this.tcpSocket.off('message');
        this.tcpSocket.off('close');
        await this.tcpSocket.close();
      } catch (e) {
        console.error(`${TAG} disconnect error: ${(e as Error).message}`);
      }
      this.tcpSocket = null;
    }
    this.resetState();
    console.info(`${TAG} disconnected`);
  }
}

