import { Hono } from 'jsr:@hono/hono'
import { crypto } from 'jsr:@std/crypto'
import { decodeHex } from 'jsr:@std/encoding/hex'
import { load } from 'jsr:@std/dotenv'
import { simpleGit } from 'https://esm.sh/simple-git@3.27.0'

const env = await load()

const buildScriptFrom = async (src: string, hash: string = '') => {
  const command = new Deno.Command('sh', {
    args: [
      '../build.sh',
      src,
      'innoextract-upx',
      hash,
    ],
  })
  const { code, stdout } = await command.output()
  if (code === 0) {
    return new TextDecoder().decode(stdout)
  }
  return `#!/bin/sh\nprintf "error building script from ${hash}\\n"`
}

const ac = new AbortController()
const app = new Hono()

app.get('/:commithash{[a-f\\d]{7,40}}', async (ctx) => {
  const commithash = ctx.req.param('commithash')
  try {
    const srcFile = await simpleGit().show(`${commithash}:src.sh`)
    const gittag = await simpleGit().tag(['--points-at', commithash])
    let forcedVersion = gittag.trim()
    if (!forcedVersion) forcedVersion = commithash.substring(0, 7)
    const script = await buildScriptFrom(srcFile, forcedVersion)
    return ctx.text(script)
  } catch (err) {
    //
  }
  return ctx.text(commithash, 404)
})

// latest commit is always built in repo root
app.get('/latest', async (ctx) => {
  return ctx.text(await Deno.readTextFile('../zoom-platform.sh'))
})

// hook to kill server, should only trigger on push or release
// when the server restarts the latest changes will get pulled
app.post('/gh-hook', async (ctx) => {
  const rawBody = await ctx.req.raw.text()
  const sigHeader = ctx.req.header('X-Hub-Signature-256')
  if (!rawBody || !sigHeader) return ctx.body(null, 401)

  const parts = sigHeader.split('=')
  const sigHex = parts[1]

  try {
    const te = new TextEncoder()
    const key = await crypto.subtle.importKey(
      'raw',
      te.encode(env['GH_HOOK_SECRET']),
      { name: 'HMAC', hash: { name: 'SHA-256' } },
      false,
      ['sign', 'verify'],
    )
    const data = te.encode(rawBody)
    const verified = await crypto.subtle.verify(
      'HMAC',
      key,
      decodeHex(sigHex),
      data,
    )
    if (!verified) {
      return ctx.status(401)
    }
  } catch (error) {
    return ctx.status(401)
  }

  setTimeout(() => {
    ac.abort()
  }, 1000)

  return ctx.text('bye', 200)
})

const server = Deno.serve({
  port: 23412,
  hostname: '0.0.0.0',
  signal: ac.signal,
}, app.fetch)

server.finished.then(() => {
  console.log('server is kill')
})
