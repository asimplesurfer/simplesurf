// Mide los cuadros por segundo en el navegador en varias carreras seguidas,
// para detectar si el juego se pone más lento de una partida a la otra.
// No falla: solo imprime los números (en CI el navegador dibuja por software,
// así que importa la comparación entre carreras, no el valor absoluto).
//
// Uso: node tests/web_perf.mjs <url>
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://localhost:8000/index.html';
const browser = await chromium.launch({
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
page.on('console', (msg) => {
  if (msg.type() === 'error') console.log(`[navegador:error] ${msg.text()}`);
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function tap(key) {
  await page.keyboard.down(key);
  await sleep(60);
  await page.keyboard.up(key);
  await sleep(150);
}

async function fps(ms) {
  return page.evaluate(async (ms) => {
    let frames = 0;
    let worst = 0;
    let last = performance.now();
    const t0 = last;
    await new Promise((resolve) => {
      function frame(now) {
        frames++;
        worst = Math.max(worst, now - last);
        last = now;
        if (now - t0 < ms) requestAnimationFrame(frame);
        else resolve();
      }
      requestAnimationFrame(frame);
    });
    const heap = performance.memory ? performance.memory.usedJSHeapSize / 1048576 : 0;
    return { fps: (frames * 1000) / (performance.now() - t0), worst, heap };
  }, ms);
}

function report(label, r) {
  console.log(
    `${label}: ${r.fps.toFixed(1)} fps, peor cuadro ${r.worst.toFixed(0)} ms, memoria JS ${r.heap.toFixed(1)} MB`
  );
}

await page.goto(url);
await page.waitForSelector('canvas');
await sleep(12000);
await page.mouse.click(480, 270);
await sleep(2500);
report('menú', await fps(4000));

for (let race = 1; race <= 3; race++) {
  // Menú: ENTER (armar la partida) y ENTER (¡a surfear!).
  await tap('Enter');
  await sleep(600);
  await tap('Enter');
  await sleep(7000);
  report(`carrera ${race} (al empezar)`, await fps(6000));
  if (race === 1) {
    // Una carrera más larga: ¿se va poniendo lenta con el tiempo?
    await sleep(20000);
    report(`carrera ${race} (30 s después)`, await fps(6000));
  }
  await tap('Escape');
  await sleep(2500);
}
await browser.close();
