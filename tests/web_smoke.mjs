// Prueba de humo en navegador: abre el build web en Chromium (sin pantalla),
// spamea Espacio, gira, y saca capturas. Falla si el navegador muestra errores
// (por ejemplo, un shader que no compila en WebGL).
//
// Uso: node tests/web_smoke.mjs <url> <carpeta_capturas>
import { chromium } from 'playwright';
import fs from 'node:fs';

const url = process.argv[2] ?? 'http://localhost:8000/index.html';
const outDir = process.argv[3] ?? 'screens';
const printBase64 = process.env.PRINT_SCREENSHOTS === '1';
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });

const problems = [];
page.on('console', (msg) => {
  const text = msg.text();
  console.log(`[navegador:${msg.type()}] ${text}`);
  if (msg.type() === 'error' || /SHADER ERROR|SCRIPT ERROR|ERROR:/.test(text)) {
    problems.push(text);
  }
});
page.on('pageerror', (err) => {
  console.log(`[navegador:excepción] ${err.message}`);
  problems.push(err.message);
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function shot(name) {
  const file = `${outDir}/${name}.jpg`;
  await page.screenshot({ path: file, type: 'jpeg', quality: 60 });
  console.log(`captura: ${file}`);
  if (printBase64) {
    console.log(`BEGIN_SCREENSHOT ${name}`);
    console.log(fs.readFileSync(file).toString('base64'));
    console.log(`END_SCREENSHOT ${name}`);
  }
}

async function mash(times, intervalMs) {
  for (let i = 0; i < times; i++) {
    await page.keyboard.down('Space');
    await sleep(30);
    await page.keyboard.up('Space');
    await sleep(intervalMs - 30);
  }
}

await page.goto(url);
await page.waitForSelector('canvas');
// Esperar a que cargue el motor y arranque la escena.
await sleep(12000);
await page.mouse.click(480, 270);
await shot('1_caido');

await mash(14, 100);
await shot('2_acostado');

await mash(25, 100);
await sleep(600);
await shot('3_parado');

await page.keyboard.down('KeyW');
await sleep(3000);
await shot('4_andando');
await page.keyboard.down('KeyE');
await sleep(800);
await shot('4b_turbo');
await page.keyboard.up('KeyE');

await page.keyboard.down('KeyD');
await sleep(500);
await shot('5_estela');
await page.keyboard.down('ShiftLeft');
await sleep(450);
await shot('6_derrape');
await page.keyboard.up('ShiftLeft');
await page.keyboard.up('KeyD');
await sleep(1500);

await page.keyboard.down('Space');
await sleep(350);
await shot('7_truco');
await page.keyboard.up('Space');
await sleep(2000);

await sleep(6000);
await shot('8_olas');
await page.keyboard.up('KeyW');

await browser.close();

if (problems.length > 0) {
  console.log(`\n${problems.length} error(es) en el navegador:`);
  for (const p of problems) console.log(` - ${p}`);
  process.exit(1);
}
console.log('\nNAVEGADOR OK');
