// node render.mjs piece.html out.mp4 [fromSec toSec]   |   node render.mjs piece.html --stills 0.5 3 7
import puppeteer from 'puppeteer-core';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { pathToFileURL } from 'url';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const ffmpeg = require('ffmpeg-static');
const [page, out, ...rest] = process.argv.slice(2);
const exe = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(p => fs.existsSync(p));
const br = await puppeteer.launch({ executablePath: exe, headless: true, args: ['--allow-file-access-from-files'], protocolTimeout: 900000 });
const pg = await br.newPage();
pg.on('pageerror', e => { console.error('PAGE ERROR', e.message); process.exit(1); });
await pg.goto(pathToFileURL(path.resolve(page)).href + '?render=1');
await pg.waitForFunction('window.READY===true', { timeout: 300000 });
const { FPS: fps, NF: nf } = await pg.evaluate(() => ({ FPS, NF }));
const grab = async f => Buffer.from((await pg.evaluate(f => { render(f); return document.querySelector('canvas').toDataURL('image/png'); }, f)).split(',')[1], 'base64');
if (out === '--stills') {
  fs.mkdirSync('stills', { recursive: true });
  for (const s of rest) fs.writeFileSync(`stills/s_${s}.png`, await grab(Math.round(+s * fps)));
} else {
  const [a, b] = rest.map(Number), f0 = a ? Math.round(a * fps) : 0, f1 = b ? Math.round(b * fps) : nf;
  const ff = spawn(ffmpeg, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-', '-c:v', 'libx264', '-crf', '16', '-pix_fmt', 'yuv420p', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = f0; f < f1; f++) {
    if (!ff.stdin.write(await grab(f))) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 60 === 0) console.log('frame', f);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
}
await br.close();
