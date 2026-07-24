import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'RtspServer';

interface RtspClient {
  connection: socket.TCPSocketConnection;
  session: string;
  clientPort: number;
  interleaved: boolean;
  interleavedChannel: number;
  audioInterleavedChannel: number;
  audioClientPort: number;
  audioUdpSocket: socket.UDPSocket | null;
  audioRemoteAddress: string;
  playing: boolean;
  sequence: number;
  audioSequence: number;
  cseq: string;
  udpSocket: socket.UDPSocket | null;
  remoteAddress: string;
  rtpServerPort: number;
}

interface SocketInfo {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

function arrayBufferToString(buf: ArrayBuffer): string {
  const view = new DataView(buf);
  let str = '';
  for (let i = 0; i < view.byteLength; i++) {
    str += String.fromCharCode(view.getUint8(i));
  }
  return str;
}

function stringToArrayBuffer(str: string): ArrayBuffer {
  const buf = new ArrayBuffer(str.length);
  const view = new DataView(buf);
  for (let i = 0; i < str.length; i++) {
    view.setUint8(i, str.charCodeAt(i));
  }
  return buf;
}

function generateSessionId(): string {
  return Math.floor(Math.random() * 1000000).toString().padStart(8, '0');
}

export class RtspServer {
  private tcpServer: socket.TCPSocketServer | null = null;
  private clients: Map<string, RtspClient> = new Map();
  private port: number;
  private sps: Uint8Array | null = null;
  private pps: Uint8Array | null = null;
  private onClientCountChange: ((count: number) => void) | null = null;
  private running: boolean = false;

  constructor(port: number) {
    this.port = port;
  }

  setOnClientCountChange(cb: (count: number) => void): void {
    this.onClientCountChange = cb;
  }

  setSpsPps(sps: Uint8Array, pps: Uint8Array): void {
    this.sps = new Uint8Array(sps);
    this.pps = new Uint8Array(pps);
  }

  setSps(sps: Uint8Array): void {
    this.sps = new Uint8Array(sps);
    console.info(`${TAG} SPS set, len=${sps.length}`);
  }

  setPps(pps: Uint8Array): void {
    this.pps = new Uint8Array(pps);
    console.info(`${TAG} PPS set, len=${pps.length}`);
  }

  async start(): Promise<void> {
    if (this.running) return;
    this.tcpServer = socket.constructTCPSocketServerInstance();
    const addr: socket.NetAddress = {
      address: '0.0.0.0',
      port: this.port,
      family: 1,
    };

    this.tcpServer.on('connect', (conn: socket.TCPSocketConnection) => {
      this.handleNewConnection(conn);
    });

    try {
      await this.tcpServer.listen(addr);
      this.running = true;
      console.info(`${TAG} listening on port ${this.port}`);
    } catch (e) {
      const err = e as Error;
      console.error(`${TAG} listen failed: ${err.message}`);
      throw new Error(err.message);
    }
  }

  async stop(): Promise<void> {
    this.running = false;
    this.clients.forEach((client: RtspClient) => {
      this.cleanupClientUdp(client);
      try {
        client.connection.off('message');
        client.connection.off('close');
        client.connection.close();
      } catch (e) {
        // ignore
      }
    });
    this.clients.clear();
    this.notifyClientCount();

    if (this.tcpServer) {
      try {
        this.tcpServer.off('connect');
        await this.tcpServer.close();
      } catch (e) {
        // ignore
      }
      this.tcpServer = null;
    }
    console.info(`${TAG} stopped`);
  }

  getClientCount(): number {
    return this.clients.size;
  }

  private notifyClientCount(): void {
    if (this.onClientCountChange) {
      this.onClientCountChange(this.clients.size);
    }
  }

  private handleNewConnection(conn: socket.TCPSocketConnection): void {
    const clientId = generateSessionId();
    const client: RtspClient = {
      connection: conn,
      session: clientId,
      clientPort: 0,
      interleaved: false,
      interleavedChannel: 0,
      audioInterleavedChannel: 2,
      audioClientPort: 0,
      audioUdpSocket: null,
      audioRemoteAddress: '',
      playing: false,
      sequence: 0,
      audioSequence: 0,
      cseq: '',
      udpSocket: null,
      remoteAddress: '',
      rtpServerPort: 0,
    };
    this.clients.set(clientId, client);
    this.notifyClientCount();

    conn.on('message', (info: SocketInfo) => {
      const request = arrayBufferToString(info.message);
      this.handleRtspRequest(clientId, request).catch((e: BusinessError) => {
        console.error(`${TAG} handleRtspRequest failed: ${e.message}`);
      });
    });

    conn.on('close', () => {
      this.cleanupClientUdp(this.clients.get(clientId));
      this.clients.delete(clientId);
      this.notifyClientCount();
      console.info(`${TAG} client ${clientId} disconnected`);
    });
  }

  private sendResponse(clientId: string, response: string): void {
    const client = this.clients.get(clientId);
    if (!client) return;
    const data = stringToArrayBuffer(response);
    client.connection.send({ data: data }).catch((e: BusinessError) => {
      console.error(`${TAG} send response failed: ${e.message}`);
    });
  }

  private async handleRtspRequest(clientId: string, request: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;

    const lines = request.split('\r\n');
    const firstLine = lines[0];
    const parts = firstLine.split(' ');
    const method = parts[0];
    const uri = parts.length > 1 ? parts[1] : '';

    let cseq = '';
    for (const line of lines) {
      const lower = line.toLowerCase();
      if (lower.startsWith('cseq:')) {
        cseq = line.substring(lower.indexOf(':') + 1).trim();
      }
    }
    client.cseq = cseq;

    console.info(`${TAG} ${method} ${uri} CSeq:${cseq}`);

    switch (method) {
      case 'OPTIONS':
        await this.handleOptions(clientId);
        break;
      case 'DESCRIBE':
        await this.handleDescribe(clientId, uri);
        break;
      case 'SETUP':
        await this.handleSetup(clientId, request);
        break;
      case 'PLAY':
        await this.handlePlay(clientId, uri);
        break;
      case 'TEARDOWN':
        await this.handleTeardown(clientId);
        break;
      default:
        this.sendResponse(clientId,
          `RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\n\r\n`);
        break;
    }
  }

  private async handleOptions(clientId: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;
    this.sendResponse(clientId,
      `RTSP/1.0 200 OK\r\n` +
      `CSeq: ${client.cseq}\r\n` +
      `Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n` +
      `\r\n`);
  }

  private async handleDescribe(clientId: string, uri: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;

    const sdp = this.buildSdp(uri);
    const sdpBytes = stringToArrayBuffer(sdp);

    this.sendResponse(clientId,
      `RTSP/1.0 200 OK\r\n` +
      `CSeq: ${client.cseq}\r\n` +
      `Content-Type: application/sdp\r\n` +
      `Content-Length: ${sdpBytes.byteLength}\r\n` +
      `\r\n` +
      sdp);
  }

  private async handleSetup(clientId: string, request: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;

    // Determine which track this SETUP targets (track0=video, track1=audio).
    let isAudioTrack = false;
    const reqLine = request.split('\r\n')[0] || '';
    if (/track1/i.test(reqLine)) {
      isAudioTrack = true;
    } else if (/track0/i.test(reqLine)) {
      isAudioTrack = false;
    }

    let transport = '';
    let interleavedChannel = -1;
    for (const line of request.split('\r\n')) {
      const lower = line.toLowerCase();
      if (lower.startsWith('transport:')) {
        transport = line.substring(lower.indexOf(':') + 1).trim();
        const interleavedMatch = transport.match(/interleaved=(\d+)-(\d+)/i);
        if (interleavedMatch) {
          interleavedChannel = parseInt(interleavedMatch[1]);
          client.interleaved = true;
          if (isAudioTrack) {
            client.audioInterleavedChannel = interleavedChannel;
          } else {
            client.interleavedChannel = interleavedChannel;
            // Conventionally audio uses the next pair (2/3).
            client.audioInterleavedChannel = interleavedChannel + 2;
          }
        }
        const portMatch = transport.match(/client_port=(\d+)/i);
        if (portMatch) {
          if (isAudioTrack) {
            client.audioClientPort = parseInt(portMatch[1]);
          } else {
            client.clientPort = parseInt(portMatch[1]);
          }
        }
      }
    }

    let transportResponse: string;
    if (client.interleaved) {
      console.info(`${TAG} SETUP: TCP interleaved video=${client.interleavedChannel} audio=${client.audioInterleavedChannel}`);
      transportResponse = `Transport: RTP/AVP/TCP;unicast;interleaved=${interleavedChannel}-${interleavedChannel + 1}`;
    } else if (isAudioTrack) {
      console.info(`${TAG} SETUP: UDP audio clientPort=${client.audioClientPort}`);
      const rtpPort = this.port + 1 + (this.clients.size * 4) + 2;
      try {
        const remoteAddr = await client.connection.getRemoteAddress();
        client.audioRemoteAddress = client.audioRemoteAddress || remoteAddr.address;
      } catch (e) {
        console.error(`${TAG} failed to get remote address (audio): ${(e as Error).message}`);
      }
      try {
        const udp = socket.constructUDPSocketInstance();
        const udpAddr: socket.NetAddress = { address: '0.0.0.0', port: rtpPort, family: 1 };
        await udp.bind(udpAddr);
        udp.setExtraOptions({ receiveBufferSize: 1024, sendBufferSize: 1024 });
        client.audioUdpSocket = udp;
        console.info(`${TAG} UDP audio RTP socket bound to port ${rtpPort} for client ${clientId}`);
      } catch (e) {
        console.error(`${TAG} failed to bind audio UDP socket: ${(e as Error).message}`);
      }
      transportResponse = `Transport: RTP/AVP;unicast;client_port=${client.audioClientPort}-${client.audioClientPort + 1};server_port=${rtpPort}-${rtpPort + 1}`;
    } else {
      console.info(`${TAG} SETUP: UDP video clientPort=${client.clientPort}`);
      const rtpPort = this.port + 1 + (this.clients.size * 4);
      client.rtpServerPort = rtpPort;
      try {
        const remoteAddr = await client.connection.getRemoteAddress();
        client.remoteAddress = remoteAddr.address;
        client.audioRemoteAddress = remoteAddr.address;
      } catch (e) {
        console.error(`${TAG} failed to get remote address: ${(e as Error).message}`);
      }
      try {
        const udp = socket.constructUDPSocketInstance();
        const udpAddr: socket.NetAddress = { address: '0.0.0.0', port: rtpPort, family: 1 };
        await udp.bind(udpAddr);
        udp.setExtraOptions({ receiveBufferSize: 1024, sendBufferSize: 1024 });
        client.udpSocket = udp;
        console.info(`${TAG} UDP RTP socket bound to port ${rtpPort} for client ${clientId}`);
      } catch (e) {
        console.error(`${TAG} failed to bind UDP socket: ${(e as Error).message}`);
      }
      transportResponse = `Transport: RTP/AVP;unicast;client_port=${client.clientPort}-${client.clientPort + 1};server_port=${rtpPort}-${rtpPort + 1}`;
    }

    this.sendResponse(clientId,
      `RTSP/1.0 200 OK\r\n` +
      `CSeq: ${client.cseq}\r\n` +
      `Session: ${client.session};timeout=60\r\n` +
      `${transportResponse}\r\n` +
      `\r\n`);
  }

  private async handlePlay(clientId: string, uri: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;
    client.playing = true;
    client.sequence = 0;
    console.info(`${TAG} PLAY: interleaved=${client.interleaved}, udpSocket=${!!client.udpSocket}, clientPort=${client.clientPort}`);

    this.sendResponse(clientId,
      `RTSP/1.0 200 OK\r\n` +
      `CSeq: ${client.cseq}\r\n` +
      `Session: ${client.session}\r\n` +
      `Range: npt=0.000-\r\n` +
      `\r\n`);
  }

  private async handleTeardown(clientId: string): Promise<void> {
    const client = this.clients.get(clientId);
    if (!client) return;
    client.playing = false;
    this.cleanupClientUdp(client);

    this.sendResponse(clientId,
      `RTSP/1.0 200 OK\r\n` +
      `CSeq: ${client.cseq}\r\n` +
      `Session: ${client.session}\r\n` +
      `\r\n`);
  }

  private buildSdp(uri: string): string {
    const spsBase64 = this.sps ? this.base64Encode(this.sps) : '';
    const ppsBase64 = this.pps ? this.base64Encode(this.pps) : '';
    console.info(`${TAG} buildSdp: sps=${this.sps ? this.sps.length + 'bytes' : 'null'}, pps=${this.pps ? this.pps.length + 'bytes' : 'null'}`);

    return (
      `v=0\r\n` +
      `o=- 0 0 IN IP4 0.0.0.0\r\n` +
      `s=HarmonyOS RTSP Server\r\n` +
      `c=IN IP4 0.0.0.0\r\n` +
      `t=0 0\r\n` +
      `a=control:${uri}\r\n` +
      `m=video 0 RTP/AVP 96\r\n` +
      `a=rtpmap:96 H264/90000\r\n` +
      `a=fmtp:96 packetization-mode=1;profile-level-id=42e01f;sprop-parameter-sets=${spsBase64},${ppsBase64}\r\n` +
      `a=control:track0\r\n` +
      `a=framerate:30\r\n` +
      `m=audio 0 RTP/AVP 97\r\n` +
      `a=rtpmap:97 mpeg4-generic/44100/2\r\n` +
      `a=fmtp:97 streamtype=5;profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3\r\n` +
      `a=control:track1\r\n`
    );
  }

  private base64Encode(data: Uint8Array): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const charsArr = chars.split('');
    let result = '';
    let i = 0;
    while (i < data.length) {
      const b1 = data[i++];
      const b2 = i < data.length ? data[i++] : -1;
      const b3 = i < data.length ? data[i++] : -1;

      result += charsArr[(b1 >> 2) & 0x3F];
      result += charsArr[((b1 & 0x03) << 4) | ((b2 >> 4) & 0x0F)];
      result += b2 === -1 ? '=' : charsArr[((b2 & 0x0F) << 2) | ((b3 >> 6) & 0x03)];
      result += b3 === -1 ? '=' : charsArr[b3 & 0x3F];
    }
    return result;
  }

  sendH264Data(nalu: Uint8Array, timestamp: number): void {
    this.clients.forEach((client: RtspClient) => {
      if (!client.playing) return;
      this.sendNaluToClient(client, nalu, timestamp);
    });
  }

  /**
   * Distribute an AAC frame to all playing clients (audio track, PT=97).
   * Only raw AAC frames (non-config) are sent via RTP; the AudioSpecificConfig is
   * already advertised through the SDP fmtp for mpeg4-generic.
   */
  sendAacData(aac: Uint8Array, timestamp: number, _isConfig: boolean): void {
    if (_isConfig) return;
    this.clients.forEach((client: RtspClient) => {
      if (!client.playing) return;
      this.sendAacToClient(client, aac, timestamp);
    });
  }

  broadcastNotification(eventType: string, data: string): void {
    const notification = `NOTIFY ${eventType} ${data}\r\n`;
    console.info(`${TAG} broadcastNotification: ${notification.trim()}`);
    this.clients.forEach((client: RtspClient) => {
      if (!client.playing) return;
      const buf = stringToArrayBuffer(notification);
      client.connection.send({ data: buf }).catch((e: BusinessError) => {
        console.error(`${TAG} broadcastNotification send failed: ${e.message}`);
      });
    });
  }

  private sendNaluToClient(client: RtspClient, nalu: Uint8Array, timestamp: number): void {
    if (client.interleaved) {
      this.sendInterleavedRtp(client, nalu, timestamp);
    } else if (client.udpSocket && client.clientPort > 0) {
      this.sendUdpRtp(client, nalu, timestamp);
    } else {
      console.warn(`${TAG} client ${client.session} has no transport, skipping NALU`);
    }
  }

  private sendInterleavedRtp(client: RtspClient, nalu: Uint8Array, timestamp: number): void {
    const naluType = nalu.length > 0 ? nalu[0] & 0x1F : 0;
    const isKeyFrame = naluType === 5;

    if (isKeyFrame && this.sps && this.pps) {
      this.sendRtpPacket(client, this.sps, timestamp, false);
      this.sendRtpPacket(client, this.pps, timestamp, false);
    }

    const maxPayload = 1400;
    if (nalu.length <= maxPayload) {
      this.sendRtpPacket(client, nalu, timestamp, true);
    } else {
      this.sendFuA(client, nalu, timestamp, maxPayload);
    }
  }

  private sendUdpRtp(client: RtspClient, nalu: Uint8Array, timestamp: number): void {
    const naluType = nalu.length > 0 ? nalu[0] & 0x1F : 0;
    const isKeyFrame = naluType === 5;

    if (isKeyFrame && this.sps && this.pps) {
      this.sendUdpRtpPacket(client, this.sps, timestamp, false);
      this.sendUdpRtpPacket(client, this.pps, timestamp, false);
    }

    const maxPayload = 1400;
    if (nalu.length <= maxPayload) {
      this.sendUdpRtpPacket(client, nalu, timestamp, true);
    } else {
      this.sendFuAUdp(client, nalu, timestamp, maxPayload);
    }
  }

  private sendUdpRtpPacket(client: RtspClient, payload: Uint8Array, timestamp: number, marker: boolean): void {
    const rtpHeader = new Uint8Array(12);
    rtpHeader[0] = 0x80;
    rtpHeader[1] = 96 | (marker ? 0x80 : 0x00);
    rtpHeader[2] = (client.sequence >> 8) & 0xFF;
    rtpHeader[3] = client.sequence & 0xFF;
    const ts = Math.floor(timestamp / 1000000) * 90;
    rtpHeader[4] = (ts >> 24) & 0xFF;
    rtpHeader[5] = (ts >> 16) & 0xFF;
    rtpHeader[6] = (ts >> 8) & 0xFF;
    rtpHeader[7] = ts & 0xFF;
    rtpHeader[8] = 0;
    rtpHeader[9] = 0;
    rtpHeader[10] = 0;
    rtpHeader[11] = 1;
    client.sequence = (client.sequence + 1) & 0xFFFF;

    const packet = new Uint8Array(rtpHeader.length + payload.length);
    packet.set(rtpHeader, 0);
    packet.set(payload, rtpHeader.length);

    const buf = packet.buffer.slice(packet.byteOffset, packet.byteOffset + packet.byteLength);
    const dest: socket.NetAddress = { address: client.remoteAddress, port: client.clientPort, family: 1 };
    client.udpSocket?.send({ data: buf, address: dest }).catch((e: BusinessError) => {
      console.error(`${TAG} send UDP RTP failed: ${e.message}`);
    });
  }

  private sendFuAUdp(client: RtspClient, nalu: Uint8Array, timestamp: number, maxPayload: number): void {
    const naluHeader = nalu[0];
    const naluType = naluHeader & 0x1F;
    const nri = naluHeader & 0x60;
    const body = nalu.subarray(1);

    const fuHeaderSize = 2;
    const chunkSize = maxPayload - fuHeaderSize;
    let offset = 0;
    let isFirst = true;

    while (offset < body.length) {
      const remaining = body.length - offset;
      const isLast = remaining <= chunkSize;
      const size = Math.min(chunkSize, remaining);

      const fuIndicator = 28 | nri;
      let fuHeader = naluType;
      if (isFirst) fuHeader |= 0x80;
      if (isLast) fuHeader |= 0x40;

      const fragment = new Uint8Array(size + 2);
      fragment[0] = fuIndicator;
      fragment[1] = fuHeader;
      fragment.set(body.subarray(offset, offset + size), 2);

      this.sendUdpRtpPacket(client, fragment, timestamp, isLast);

      offset += size;
      isFirst = false;
    }
  }

  private cleanupClientUdp(client: RtspClient | undefined): void {
    if (client && client.udpSocket) {
      try {
        client.udpSocket.close();
      } catch (e) {
        // ignore
      }
      client.udpSocket = null;
    }
    if (client && client.audioUdpSocket) {
      try {
        client.audioUdpSocket.close();
      } catch (e) {
        // ignore
      }
      client.audioUdpSocket = null;
    }
  }

  private sendRtpPacket(client: RtspClient, payload: Uint8Array, timestamp: number, marker: boolean): void {
    const rtpHeader = new Uint8Array(12);
    rtpHeader[0] = 0x80;
    rtpHeader[1] = 96 | (marker ? 0x80 : 0x00);
    rtpHeader[2] = (client.sequence >> 8) & 0xFF;
    rtpHeader[3] = client.sequence & 0xFF;
    const ts = Math.floor(timestamp / 1000000) * 90;
    rtpHeader[4] = (ts >> 24) & 0xFF;
    rtpHeader[5] = (ts >> 16) & 0xFF;
    rtpHeader[6] = (ts >> 8) & 0xFF;
    rtpHeader[7] = ts & 0xFF;
    rtpHeader[8] = 0;
    rtpHeader[9] = 0;
    rtpHeader[10] = 0;
    rtpHeader[11] = 1;
    client.sequence = (client.sequence + 1) & 0xFFFF;

    const interleavedHeader = new Uint8Array(4);
    interleavedHeader[0] = 0x24;
    interleavedHeader[1] = client.interleavedChannel;
    const rtpLen = rtpHeader.length + payload.length;
    interleavedHeader[2] = (rtpLen >> 8) & 0xFF;
    interleavedHeader[3] = rtpLen & 0xFF;

    const packet = new Uint8Array(interleavedHeader.length + rtpLen);
    packet.set(interleavedHeader, 0);
    packet.set(rtpHeader, interleavedHeader.length);
    packet.set(payload, interleavedHeader.length + rtpHeader.length);

    const buf = packet.buffer.slice(packet.byteOffset, packet.byteOffset + packet.byteLength);
    client.connection.send({ data: buf }).catch((e: BusinessError) => {
      console.error(`${TAG} send RTP failed: ${e.message}`);
    });
  }

  private sendFuA(client: RtspClient, nalu: Uint8Array, timestamp: number, maxPayload: number): void {
    const naluHeader = nalu[0];
    const naluType = naluHeader & 0x1F;
    const nri = naluHeader & 0x60;
    const body = nalu.subarray(1);

    const fuHeaderSize = 2;
    const chunkSize = maxPayload - fuHeaderSize;
    let offset = 0;
    let isFirst = true;

    while (offset < body.length) {
      const remaining = body.length - offset;
      const isLast = remaining <= chunkSize;
      const size = Math.min(chunkSize, remaining);

      const fuIndicator = 28 | nri;
      let fuHeader = naluType;
      if (isFirst) fuHeader |= 0x80;
      if (isLast) fuHeader |= 0x40;

      const fragment = new Uint8Array(size + 2);
      fragment[0] = fuIndicator;
      fragment[1] = fuHeader;
      fragment.set(body.subarray(offset, offset + size), 2);

      this.sendRtpPacket(client, fragment, timestamp, isLast);

      offset += size;
      isFirst = false;
    }
  }

  // ---- Audio (AAC, mpeg4-generic) RTP packaging ----

  private sendAacToClient(client: RtspClient, aac: Uint8Array, timestamp: number): void {
    if (client.interleaved) {
      this.sendAacInterleaved(client, aac, timestamp);
    } else if (client.audioUdpSocket && client.audioClientPort > 0) {
      this.sendAacUdp(client, aac, timestamp);
    }
  }

  // Build the mpeg4-generic RTP payload: AU-headers section + AAC access unit.
  // sizelength=13, indexlength=3, indexdeltalength=3 => each AU-header is 16 bits.
  private buildAacRtpPayload(aac: Uint8Array): Uint8Array {
    const auHeadersLength = 16; // bits (one 16-bit AU header)
    const headerSection = new Uint8Array(4); // 2 bytes length + 2 bytes AU header
    headerSection[0] = (auHeadersLength >> 8) & 0xFF;
    headerSection[1] = auHeadersLength & 0xFF;
    // AU-header: size (13 bits) | index (3 bits)
    const size = aac.length & 0x1FFF;
    headerSection[2] = (size >> 5) & 0xFF;
    headerSection[3] = (size << 3) & 0xFF; // index=0

    const payload = new Uint8Array(headerSection.length + aac.length);
    payload.set(headerSection, 0);
    payload.set(aac, headerSection.length);
    return payload;
  }

  private sendAacInterleaved(client: RtspClient, aac: Uint8Array, timestamp: number): void {
    const payload = this.buildAacRtpPayload(aac);
    const rtpHeader = new Uint8Array(12);
    rtpHeader[0] = 0x80;
    rtpHeader[1] = 97 | 0x80; // PT=97 + marker (set for AAC)
    rtpHeader[2] = (client.audioSequence >> 8) & 0xFF;
    rtpHeader[3] = client.audioSequence & 0xFF;
    // AAC RTP clock = sample rate (44100). pts from encoder is in microseconds.
    const ts = Math.floor(timestamp / 1000000 * 44100);
    rtpHeader[4] = (ts >> 24) & 0xFF;
    rtpHeader[5] = (ts >> 16) & 0xFF;
    rtpHeader[6] = (ts >> 8) & 0xFF;
    rtpHeader[7] = ts & 0xFF;
    rtpHeader[8] = 0;
    rtpHeader[9] = 0;
    rtpHeader[10] = 0;
    rtpHeader[11] = 2; // SSRC differs from video
    client.audioSequence = (client.audioSequence + 1) & 0xFFFF;

    const interleavedHeader = new Uint8Array(4);
    interleavedHeader[0] = 0x24;
    interleavedHeader[1] = client.audioInterleavedChannel;
    const rtpLen = rtpHeader.length + payload.length;
    interleavedHeader[2] = (rtpLen >> 8) & 0xFF;
    interleavedHeader[3] = rtpLen & 0xFF;

    const packet = new Uint8Array(interleavedHeader.length + rtpLen);
    packet.set(interleavedHeader, 0);
    packet.set(rtpHeader, interleavedHeader.length);
    packet.set(payload, interleavedHeader.length + rtpHeader.length);

    const buf = packet.buffer.slice(packet.byteOffset, packet.byteOffset + packet.byteLength);
    client.connection.send({ data: buf }).catch((e: BusinessError) => {
      console.error(`${TAG} send audio RTP failed: ${e.message}`);
    });
  }

  private sendAacUdp(client: RtspClient, aac: Uint8Array, timestamp: number): void {
    const payload = this.buildAacRtpPayload(aac);
    const rtpHeader = new Uint8Array(12);
    rtpHeader[0] = 0x80;
    rtpHeader[1] = 97 | 0x80;
    rtpHeader[2] = (client.audioSequence >> 8) & 0xFF;
    rtpHeader[3] = client.audioSequence & 0xFF;
    const ts = Math.floor(timestamp / 1000000 * 44100);
    rtpHeader[4] = (ts >> 24) & 0xFF;
    rtpHeader[5] = (ts >> 16) & 0xFF;
    rtpHeader[6] = (ts >> 8) & 0xFF;
    rtpHeader[7] = ts & 0xFF;
    rtpHeader[8] = 0;
    rtpHeader[9] = 0;
    rtpHeader[10] = 0;
    rtpHeader[11] = 2;
    client.audioSequence = (client.audioSequence + 1) & 0xFFFF;

    const packet = new Uint8Array(rtpHeader.length + payload.length);
    packet.set(rtpHeader, 0);
    packet.set(payload, rtpHeader.length);

    const buf = packet.buffer.slice(packet.byteOffset, packet.byteOffset + packet.byteLength);
    const dest: socket.NetAddress = { address: client.audioRemoteAddress, port: client.audioClientPort, family: 1 };
    client.audioUdpSocket?.send({ data: buf, address: dest }).catch((e: BusinessError) => {
      console.error(`${TAG} send audio UDP RTP failed: ${e.message}`);
    });
  }
}
