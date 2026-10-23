// Renders demo.html frame by frame, then builds assets/demo.mp4 (with sounds) and assets/demo.gif.
//   node tools/demo/render.mjs            (needs playwright + ffmpeg)
import { chromium } from 'playwright';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const FPS = 30;
const frames = fs.mkdtempSync(path.join(os.tmpdir(), 'ding-frames-'));
const waves = fs.readFileSync(path.join(here, 'waveforms.json'), 'utf8');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.addInitScript(`window.CAPTURE = true; window.WAVES = ${waves};`);
await page.goto('file://' + path.join(here, 'demo.html'));
await page.evaluate(() => document.fonts.ready);
const total = await page.evaluate(() => window.TOTAL);
const times = await page.evaluate(() => window.SOUND_TIMES);
const n = Math.round(total * FPS);
const canvas = await page.$('canvas');
for (let i = 0; i < n; i++) {
  await page.evaluate(t => window.render(t), i / FPS);
  await canvas.screenshot({ path: path.join(frames, `f${String(i).padStart(4, '0')}.png`) });
}
await browser.close();
console.log(`${n} frames, ${total.toFixed(1)}s`);

fs.mkdirSync(path.join(root, 'assets'), { recursive: true });
const files = { 'money': '01-money', 'battle': '02-battle', 'mic-drop': '03-mic-drop', 'ship-it': '04-ship-it', 'zen': '05-zen' };
const inputs = [], filters = [];
times.forEach((s, i) => {
  inputs.push('-i', path.join(root, 'sounds', files[s.id] + '.wav'));
  const ms = Math.round(s.t * 1000);
  filters.push(`[${i + 1}:a]adelay=${ms}|${ms},volume=1.6[a${i}]`);
});
filters.push(times.map((_, i) => `[a${i}]`).join('') + `amix=inputs=${times.length}:normalize=0,apad[aout]`);
const ff = (...args) => execFileSync('ffmpeg', ['-loglevel', 'error', '-y', ...args], { stdio: 'inherit' });

ff('-framerate', String(FPS), '-i', path.join(frames, 'f%04d.png'), ...inputs,
   '-filter_complex', filters.join(';'), '-map', '0:v', '-map', '[aout]',
   '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'slow',
   '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart',
   path.join(root, 'assets', 'demo.mp4'));

const pal = path.join(frames, 'pal.png');
ff('-framerate', String(FPS), '-i', path.join(frames, 'f%04d.png'),
   '-vf', 'fps=15,scale=720:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff', pal);
ff('-framerate', String(FPS), '-i', path.join(frames, 'f%04d.png'), '-i', pal,
   '-lavfi', 'fps=15,scale=720:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
   path.join(root, 'assets', 'demo.gif'));

fs.rmSync(frames, { recursive: true, force: true });
for (const f of ['demo.mp4', 'demo.gif']) console.log(f, Math.round(fs.statSync(path.join(root, 'assets', f)).size / 1024), 'KB');
