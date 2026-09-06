const assert = require('node:assert/strict')
const { setTimeout: sleep } = require('node:timers/promises')
const mineflayer = require('mineflayer')

const count = Number(process.argv[2])
const seconds = Number(process.argv[3] || 60)
const version = process.argv[4] || '26.2'
const qualify = process.argv.includes('--survival')
const lane = qualify ? 32 : 256
const customPackets = version === '26.2' ? require('./protocol26') : undefined
assert([1, 2, 4, 8].includes(count), 'Use 1, 2, 4 or 8 players')
assert(Number.isInteger(seconds) && seconds >= 10 && seconds <= 300)
assert(['26.2', '1.20.1'].includes(version), 'Use a measured server version')
const bots = []
const observations = []
let sampler
const log = (event, details = {}) => console.log(JSON.stringify({ time: new Date().toISOString(), event, ...details }))
const deadline = (promise, label, ms = 90000) => {
  let timer
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out`)), ms)
  })]).finally(() => clearTimeout(timer))
}

async function waitForColumn(bot, position) {
  const started = Date.now()
  await deadline((async () => {
    while (!bot.world.getColumnAt(position)) await sleep(100)
  })(), `chunk ${bot.username} at ${position}`, 60000)
  if (qualify || Date.now() - started > 100) log('chunk_wait', { username: bot.username, seconds: (Date.now() - started) / 1000, position })
}

async function connect(index) {
  const username = `Bench${String(index + 1).padStart(2, '0')}`
  const bot = mineflayer.createBot({ host: '127.0.0.1', port: 25565, username, auth: 'offline', version, customPackets })
  bots.push(bot)
  const record = { username, chunks: 0, attacks: 0, confirmed_hits: 0, hurt_events: 0, kills: 0 }
  observations.push(record)
  bot.on('chunkColumnLoad', () => record.chunks++)
  bot.on('entityHurt', entity => { if (entity.name === 'husk') record.hurt_events++ })
  bot._client.on('damage_event', packet => {
    if (packet.sourceCauseId - 1 === bot.entity?.id && bot.entities[packet.entityId]?.name === 'husk') record.confirmed_hits++
  })
  bot.on('entityDead', entity => { if (entity.name === 'husk') record.kills++ })
  bot.on('error', error => { log('bot_error', { username, error: String(error) }); process.exitCode = 1 })
  bot.on('kicked', reason => { log('bot_kicked', { username, reason }); process.exitCode = 1 })
  await deadline(new Promise(resolve => bot.once('spawn', resolve)), `spawn ${username}`)
  record.spawned_at = Date.now()
  await waitForColumn(bot, bot.entity.position)
  if (qualify) {
    bot.chat('/gamemode creative')
    await sleep(1000)
  }
  bot.creative.startFlying()
  bot.chat(`/tp @s ${index * lane} 300 0`)
  await sleep(1500)
  bot.creative.startFlying()
  await waitForColumn(bot, bot.entity.position)
  record.start_position = bot.entity.position.clone()
  log('spawn', { username, position: record.start_position })
  return bot
}

async function verifyPosition(bot, position, stage) {
  const started = Date.now()
  const marker = `E0_POS_${stage}_${bot.username}`
  let listener
  const response = new Promise(resolve => {
    listener = message => { if (message.includes(marker)) resolve() }
    bot.on('messagestr', listener)
  })
  bot.chat(`/execute positioned ${position.x} ${position.y} ${position.z} if entity @s[distance=..2] run say ${marker}`)
  try {
    await deadline(response, marker, 10000)
    log('server_position_verified', { username: bot.username, stage, position, seconds: (Date.now() - started) / 1000 })
  } finally {
    bot.off('messagestr', listener)
  }
}

async function explore(direction) {
  const starts = bots.map(bot => bot.entity.position.clone())
  const tasks = bots.map(async bot => {
    const destination = bot.entity.position.offset(0, 0, direction * seconds * 8)
    // Mineflayer stops sending movement when its current chunk is unloaded.
    while (bot.entity.position.distanceTo(destination) > 0.1) {
      const step = Math.min(16, bot.entity.position.distanceTo(destination))
      const waypoint = bot.entity.position.offset(0, 0, direction * step)
      await waitForColumn(bot, waypoint)
      await deadline(bot.creative.flyTo(waypoint), `flight ${bot.username}`, 15000)
    }
    await verifyPosition(bot, destination, direction > 0 ? 'out' : 'back')
  })
  await Promise.all(tasks)
  for (let index = 0; index < bots.length; index++) {
    const distance = bots[index].entity.position.distanceTo(starts[index])
    assert(distance >= seconds * 8 - 2, `Incomplete movement: ${distance}`)
    observations[index][direction > 0 ? 'explored_blocks' : 'revisited_blocks'] = distance
  }
}

async function combat(index) {
  const bot = bots[index]
  const x = index * lane
  bot.chat(`/fill ${x - 5} 199 ${qualify ? -20 : -5} ${x + 5} 199 ${qualify ? 20 : 5} minecraft:stone`)
  await sleep(300)
  bot.chat(`/tp @s ${x} 200 0`)
  await sleep(1000)
  bot.creative.stopFlying()
  bot.chat('/give @s minecraft:diamond_sword')
  await sleep(1000)
  const sword = bot.inventory.items().find(item => item.name === 'diamond_sword')
  assert(sword, `Missing sword for ${bot.username}`)
  await bot.equip(sword, 'hand')
  const end = Date.now() + seconds * 1000
  let lastSummon = 0
  while (Date.now() < end) {
    let target = bot.nearestEntity(entity => entity.name === 'husk' && entity.position.distanceTo(bot.entity.position) < 5)
    if (!target && Date.now() - lastSummon > 2000) {
      bot.chat(`/summon minecraft:husk ${x + 2} 200 0 {PersistenceRequired:1b}`)
      lastSummon = Date.now()
    } else if (target) {
      await bot.lookAt(target.position.offset(0, 1, 0))
      if (version === '26.2') {
        // Minecraft 26.2 moved attacks out of use_entity.
        bot._client.write('attack', { entityId: target.id })
        bot.swingArm()
      } else {
        bot.attack(target)
      }
      observations[index].attacks++
    }
    await sleep(700)
  }
  assert(observations[index].attacks >= 3, `No attacks from ${bot.username}`)
  assert(observations[index].confirmed_hits >= 1, `No player damage confirmed for ${bot.username}`)
}

async function verifyBlock(bot, target, material) {
  const started = Date.now()
  const marker = `FREE_BLOCK_${material}_${bot.username}`
  let listener
  const confirmed = new Promise(resolve => {
    listener = message => { if (message.includes(marker)) resolve() }
    bot.on('messagestr', listener)
  })
  bot.chat(`/execute if block ${target.x} ${target.y} ${target.z} minecraft:${material} run say ${marker}`)
  try {
    await deadline(confirmed, marker, 10000)
    log('server_block_verified', { username: bot.username, target, material, seconds: (Date.now() - started) / 1000 })
  } finally { bot.off('messagestr', listener) }
}

async function changeBlock(bot, target, material, action) {
  let listener
  const update = new Promise(resolve => {
    listener = packet => {
      if (packet.location.x === target.x && packet.location.y === target.y && packet.location.z === target.z &&
          packet.type === bot.registry.blocksByName[material].defaultState) resolve()
    }
    bot._client.on('block_change', listener)
  })
  try {
    await action()
    await deadline(update, `server block update ${material} ${bot.username}`, 10000)
    await verifyBlock(bot, target, material)
  } finally { bot._client.off('block_change', listener) }
}

async function survival(index) {
  const bot = bots[index]
  const x = index * lane
  bot.chat(`/tp @s ${x} 200 0`)
  bot.chat('/kill @e[type=minecraft:husk,distance=..8]')
  bot.chat('/gamemode survival')
  bot.chat('/give @s minecraft:iron_pickaxe')
  bot.chat('/give @s minecraft:stone 16')
  bot.chat(`/setblock ${x + 1} 200 0 minecraft:stone`)
  await sleep(1500)
  const origin = bot.entity.position.clone()
  const target = origin.floored().offset(1, 0, 0)
  const pickaxe = bot.inventory.items().find(item => item.name === 'iron_pickaxe')
  assert(pickaxe, `Missing pickaxe for ${bot.username}`)
  await bot.equip(pickaxe, 'hand')
  const started = Date.now()
  await changeBlock(bot, target, 'air', () => deadline(bot.dig(bot.blockAt(target)), `dig ${bot.username}`, 10000))
  const digSeconds = (Date.now() - started) / 1000
  const stone = bot.inventory.items().find(item => item.name === 'stone')
  assert(stone, `Missing stone for ${bot.username}`)
  await bot.equip(stone, 'hand')
  await changeBlock(bot, target, 'stone', () => deadline(bot.placeBlock(bot.blockAt(target.offset(0, -1, 0)),
    target.offset(0, 1, 0).minus(target)), `place ${bot.username}`, 10000))
  await bot.look(0, 0, true)
  bot.setControlState('forward', true)
  await sleep(3000)
  bot.clearControlStates()
  await sleep(500)
  const distance = Math.hypot(bot.entity.position.x - origin.x, bot.entity.position.z - origin.z)
  const vertical = bot.entity.position.y - origin.y
  assert(distance >= 3, `Incomplete Survival walk: ${distance}`)
  assert(Math.abs(vertical) <= 1 && bot.entity.onGround, `Survival walk left the ground: ${vertical}`)
  await verifyPosition(bot, bot.entity.position.clone(), 'survival')
  observations[index].survival = { walked_blocks: distance, vertical_change: vertical, dig_seconds: digSeconds, block_confirmed: true }
  log('survival_complete', { username: bot.username, ...observations[index].survival })
}

async function main() {
  log('connecting', { players: count, phase_seconds: seconds, version, survival: qualify, lane_blocks: lane })
  for (let index = 0; index < count; index++) await connect(index)
  sampler = setInterval(() => log('sample', { players: bots.map(bot => ({
    username: bot.username, position: bot.entity.position,
    bytes_read: bot._client.socket.bytesRead, bytes_written: bot._client.socket.bytesWritten
  })) }), 5000)
  log('phase', { name: 'new_chunks', players: count })
  await explore(1)
  log('phase', { name: 'existing_chunks', players: count })
  await explore(-1)
  log('phase', { name: 'combat', players: count })
  await Promise.all(bots.map((_, index) => combat(index)))
  if (qualify) {
    log('phase', { name: 'survival', players: count })
    await Promise.all(bots.map((_, index) => survival(index)))
  }
  for (let index = 0; index < count; index++) {
    observations[index].active_seconds = (Date.now() - observations[index].spawned_at) / 1000
    observations[index].bytes_read = bots[index]._client.socket.bytesRead
    observations[index].bytes_written = bots[index]._client.socket.bytesWritten
  }
  assert(!process.exitCode, 'Client errors occurred')
  log('complete', { players: count, observations })
}

main().catch(error => { log('failed', { error: String(error), observations }); process.exitCode = 1 })
  .finally(async () => {
    clearInterval(sampler)
    bots.forEach(bot => bot.quit())
    await sleep(1000)
    process.exit(process.exitCode || 0)
  })
