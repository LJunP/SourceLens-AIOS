import dgram from 'node:dgram'
import net from 'node:net'
import { canonicalJsonBytes } from '../lib/canonical-json.mjs'

function tcpBindProbe() {
  return new Promise(resolve => {
    const server = net.createServer()
    server.once('error', error => resolve({ probe: 'TCP_LOOPBACK_BIND', outcome: 'DENIED', error_code: error.code ?? 'UNKNOWN' }))
    server.listen({ host: '127.0.0.1', port: 0 }, () => server.close(() => resolve({ probe: 'TCP_LOOPBACK_BIND', outcome: 'ALLOWED', error_code: null })))
  })
}

function tcpConnectProbe() {
  return new Promise(resolve => {
    const socket = net.createConnection({ host: '127.0.0.1', port: 9 })
    const finish = result => {
      socket.destroy()
      resolve(result)
    }
    socket.once('connect', () => finish({ probe: 'TCP_LOOPBACK_CONNECT', outcome: 'ALLOWED', error_code: null }))
    socket.once('error', error => finish({ probe: 'TCP_LOOPBACK_CONNECT', outcome: error.code === 'EPERM' || error.code === 'EACCES' ? 'DENIED' : 'SOCKET_CAPABILITY_PRESENT', error_code: error.code ?? 'UNKNOWN' }))
  })
}

function udpBindProbe() {
  return new Promise(resolve => {
    const socket = dgram.createSocket('udp4')
    const finish = result => {
      try { socket.close() } catch {}
      resolve(result)
    }
    socket.once('error', error => finish({ probe: 'UDP_LOOPBACK_BIND', outcome: 'DENIED', error_code: error.code ?? 'UNKNOWN' }))
    socket.bind(0, '127.0.0.1', () => finish({ probe: 'UDP_LOOPBACK_BIND', outcome: 'ALLOWED', error_code: null }))
  })
}

const probes = []
for (const probe of [tcpBindProbe, tcpConnectProbe, udpBindProbe]) probes.push(await probe())
const deniedCodes = new Set(['EPERM', 'EACCES'])
const passed = probes.every(probe => probe.outcome === 'DENIED' && deniedCodes.has(probe.error_code))
process.stdout.write(canonicalJsonBytes({
  schema_version: 'p3-dtk-network-deny-preflight/v1',
  sandbox_profile: '(version 1) (allow default) (deny network*)',
  probes,
  verdict: passed ? 'PASS' : 'NON_PASS',
}))
if (!passed) process.exitCode = 1
