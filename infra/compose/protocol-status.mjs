#!/usr/bin/env node
// Minecraft Java status ping (handshake + status request) for journey
// verification. Prints one JSON line on success and exits 1 when the
// endpoint is unreachable. No dependencies; node >= 22.
import net from "node:net";
import { performance } from "node:perf_hooks";

const args = process.argv.slice(2);
const option = name => {
  const index = args.indexOf(`--${name}`);
  return index === -1 ? undefined : args[index + 1];
};
const host = option("host") ?? "127.0.0.1";
const port = Number(option("port") ?? 25565);
const timeoutMs = Number(option("timeout-ms") ?? 5000);
const protocolVersion = Number(option("protocol") ?? 776);

function writeVarInt(value) {
  const bytes = [];
  let current = value;
  do {
    let byte = current & 0x7f;
    current = Math.floor(current / 128);
    if (current > 0) byte |= 0x80;
    bytes.push(byte);
  } while (current > 0);
  return Buffer.from(bytes);
}

function writeString(value) {
  const bytes = Buffer.from(value, "utf8");
  return Buffer.concat([writeVarInt(bytes.length), bytes]);
}

function readVarInt(buffer, offset) {
  let value = 0;
  let multiplier = 1;
  let index = offset;
  while (index < buffer.length) {
    const byte = buffer[index++];
    value += (byte & 0x7f) * multiplier;
    multiplier *= 128;
    if ((byte & 0x80) === 0) return { value, offset: index };
    if (multiplier > 128 ** 5) throw new Error("varint too long");
  }
  return null;
}

function parseStatusReply(buffer) {
  const length = readVarInt(buffer, 0);
  if (length === null) return null;
  if (buffer.length < length.offset + length.value) return null;
  const body = buffer.subarray(length.offset, length.offset + length.value);
  const id = readVarInt(body, 0);
  if (id === null || id.value !== 0) throw new Error("unexpected packet id");
  const text = readVarInt(body, id.offset);
  if (text === null) throw new Error("truncated status reply");
  return JSON.parse(body.subarray(text.offset, text.offset + text.value).toString("utf8"));
}

try {
  const started = performance.now();
  const socket = net.connect({ host, port });
  socket.setTimeout(timeoutMs);

  const handshake = Buffer.concat([
    writeVarInt(0x00),
    writeVarInt(protocolVersion),
    writeString(host),
    Buffer.from([(port >> 8) & 0xff, port & 0xff]),
    writeVarInt(1)
  ]);
  const statusRequest = writeVarInt(0x00);
  socket.once("connect", () => {
    socket.write(Buffer.concat([writeVarInt(handshake.length), handshake]));
    socket.write(Buffer.concat([writeVarInt(statusRequest.length), statusRequest]));
  });

  const reply = await new Promise((resolve, reject) => {
    socket.once("error", reject);
    socket.once("timeout", () => { socket.destroy(); reject(new Error("timed out")); });
    let buffer = Buffer.alloc(0);
    socket.on("data", chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      try {
        const parsed = parseStatusReply(buffer);
        if (parsed !== null) { socket.end(); resolve(parsed); }
      } catch (error) {
        socket.destroy(); reject(error);
      }
    });
    socket.once("close", () => reject(new Error("connection closed before a status reply")));
  });

  socket.destroy();
  const latencyMs = Math.round(performance.now() - started);
  process.stdout.write(JSON.stringify({
    host,
    port,
    latency_ms: latencyMs,
    version: reply.version?.name,
    protocol: reply.version?.protocol,
    players_online: reply.players?.online,
    players_max: reply.players?.max
  }) + "\n");
} catch (error) {
  process.stderr.write(`status failed: ${error.code ?? error.message}\n`);
  process.exit(1);
}
