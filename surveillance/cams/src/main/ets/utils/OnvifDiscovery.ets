import { socket } from '@kit.NetworkKit';

export interface OnvifDevice {
  xaddr: string;
  host: string;
  port: string;
  types: string[];
  scopes: string[];
}

interface ParsedUrl {
  host: string;
  port: string;
}

interface SendOptions {
  data: ArrayBuffer;
  address: NetAddress;
}

interface NetAddress {
  address: string;
  port: number;
}

const MULTICAST_ADDRESS = '239.255.255.250';
const MULTICAST_PORT = 3702;

export async function probeOnvifDevices(timeoutMs: number = 4000): Promise<OnvifDevice[]> {
  return new Promise((resolve) => {
    const results = new Map<string, OnvifDevice>();
    const messageId = generateUUID();
    const probeMessage = buildProbeMessage(messageId);

    try {
      const udpSocket = socket.constructUDPSocketInstance();
      udpSocket.bind({ address: '0.0.0.0', port: 0 }).then(() => {
        const data = stringToArrayBuffer(probeMessage);
        const target: NetAddress = { address: MULTICAST_ADDRESS, port: MULTICAST_PORT };
        const sendOpts: SendOptions = {
          data: data,
          address: target,
        };
        udpSocket.send(sendOpts).catch(() => {});

        const timer = setTimeout(() => {
          udpSocket.close();
          resolve(Array.from(results.values()));
        }, timeoutMs);

        udpSocket.on('message', (info: SocketMessageInfo) => {
          const response = arrayBufferToString(info.message);
          parseProbeMatches(response).forEach((device: OnvifDevice) => {
            if (!results.has(device.xaddr)) {
              results.set(device.xaddr, device);
            }
          });
        });
      }).catch(() => {
        resolve([]);
      });
    } catch {
      resolve([]);
    }
  });
}

function buildProbeMessage(messageId: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
            xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
            xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <e:Header>
    <w:MessageID>uuid:${messageId}</w:MessageID>
    <w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
  </e:Header>
  <e:Body>
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>`;
}

const xaddrRegex = /<[^>]*XAddrs[^>]*>([^<]+)<\/[^>]*XAddrs[^>]*>/i;
const typesRegex = /<[^>]*Types[^>]*>([^<]+)<\/[^>]*Types[^>]*>/i;
const scopesRegex = /<[^>]*Scopes[^>]*>([^<]+)<\/[^>]*Scopes[^>]*>/i;

function parseProbeMatches(response: string): OnvifDevice[] {
  const xaddrsMatch = xaddrRegex.exec(response);
  const xaddrs = xaddrsMatch?.[1]?.trim() ?? '';
  if (xaddrs === '') return [];
  const typesMatch = typesRegex.exec(response);
  const types = typesMatch?.[1]?.split(/\s+/).filter(s => s !== '') ?? [];
  const scopesMatch = scopesRegex.exec(response);
  const scopes = scopesMatch?.[1]?.split(/\s+/).filter(s => s !== '') ?? [];
  return xaddrs.split(/\s+/).filter((s: string) => s !== '').map((url: string) => {
    try {
      const parsed = parseUrl(url);
      const device: OnvifDevice = {
        xaddr: url,
        host: parsed.host,
        port: parsed.port,
        types,
        scopes,
      };
      return device;
    } catch {
      return null;
    }
  }).filter((d: OnvifDevice | null) => d !== null) as OnvifDevice[];
}

function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

function stringToArrayBuffer(str: string): ArrayBuffer {
  const buf = new ArrayBuffer(str.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < str.length; i++) {
    view[i] = str.charCodeAt(i) & 0xFF;
  }
  return buf;
}

function arrayBufferToString(buf: ArrayBuffer): string {
  const view = new Uint8Array(buf);
  let result = '';
  for (let i = 0; i < view.length; i++) {
    result += String.fromCharCode(view[i]);
  }
  return result;
}

interface SocketMessageInfo {
  message: ArrayBuffer;
  remoteInfo: SocketRemoteInfo;
}

interface SocketRemoteInfo {
  address: string;
  port: number;
}

function parseUrl(url: string): ParsedUrl {
  const schemeIdx = url.indexOf('://');
  if (schemeIdx < 0) throw new Error('invalid url');
  const rest = url.substring(schemeIdx + 3);
  const pathIdx = rest.indexOf('/');
  const hostPort = pathIdx >= 0 ? rest.substring(0, pathIdx) : rest;
  const colonIdx = hostPort.indexOf(':');
  if (colonIdx >= 0) {
    const result: ParsedUrl = { host: hostPort.substring(0, colonIdx), port: hostPort.substring(colonIdx + 1) };
    return result;
  }
  const result2: ParsedUrl = { host: hostPort, port: '' };
  return result2;
}
