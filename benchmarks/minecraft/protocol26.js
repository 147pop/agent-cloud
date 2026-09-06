const assert = require('node:assert/strict')
const data = require('minecraft-data')('26.2')
const packet = structuredClone(data.protocol.play.toServer.types.packet)
const mappings = packet[1][0].type[1].mappings
assert.equal(mappings['0x41'], 'block_place', 'Recheck the pinned dependency before applying the 26.2 correction')
// ponytail: correct the pinned 26.2 registry; remove when the dependency matches the official server.
Object.assign(mappings, {
  '0x3e': 'spectator_action', '0x3f': 'arm_animation', '0x40': 'spectate',
  '0x41': 'test_instance_block_action', '0x42': 'block_place',
  '0x43': 'use_item', '0x44': 'custom_click_action'
})
packet[1][1].type[1].fields.spectate = 'packet_spectate'
const customPackets = { [data.version.majorVersion]: { play: { toServer: { types: {
  packet, packet_spectate: ['container', [{ name: 'target', type: 'UUID' }]]
} } } } }
module.exports = customPackets

if (require.main === module) {
  const serializer = require('minecraft-protocol').createSerializer({ state: 'play', version: '26.2', customPackets })
  const packets = [
    ['arm_animation', { hand: 0 }, 0x3f],
    ['spectate', { target: '00000000-0000-0000-0000-000000000001' }, 0x40],
    ['block_dig', { status: 0, location: { x: 1, y: 200, z: 0 }, face: 1, sequence: 0 }, 0x29],
    ['block_place', { hand: 0, location: { x: 1, y: 199, z: 0 }, direction: 1,
      cursorX: 0.5, cursorY: 1, cursorZ: 0.5, insideBlock: false, worldBorderHit: false, sequence: 0 }, 0x42]
  ]
  for (const [name, params, id] of packets) assert.equal(serializer.createPacketBuffer({ name, params })[0], id)
  console.log('Official 26.2 outgoing packet IDs verified')
}
