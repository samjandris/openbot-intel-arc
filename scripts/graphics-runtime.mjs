// Linux server extension. No listening debug port, profile import, or sandbox changes.
import { BrowserWindow, WebContentsView } from 'electron';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

export function configureOpenBotServerGraphics(app, options, mode) {
  if (!options.server || process.env.OPENBOT_SERVER_GPU !== '1') return;
  if (mode.hardwareAcceleration) {
    app.commandLine.appendSwitch('use-gl', 'angle');
    app.commandLine.appendSwitch('use-angle', 'vulkan');
    // Keep Chromium's compositor, driver workarounds and Vulkan blocklist policy.
  }
  void app.whenReady().then(async () => {
    const directory = await mkdtemp('/tmp/openbot-graphics-');
    const report = { mode, uid: process.getuid(), electron: process.versions.electron, directory };
    try {
      await delay(1500);
      report.features = app.getGPUFeatureStatus();
      const info = await app.getGPUInfo('complete');
      report.devices = info.gpuDevice;
      report.attributes = info.auxAttributes;
      if (process.env.OPENBOT_GPU_SELF_TEST === '1') report.browser = await browserCheck(directory);
      report.status = mode.hardwareAcceleration ? 'reported' : 'software-fallback';
      if (report.browser) {
        const intel = report.devices?.some(device => device.vendorId === 0x8086 && device.deviceId === 0x56a5);
        if (!intel || !/Intel/i.test(report.browser.renderer) || /SwiftShader|llvmpipe|lavapipe/i.test(report.browser.renderer)) {
          throw new Error('The browser did not use the Intel Arc A380 renderer');
        }
        if (report.features.gpu_compositing !== 'enabled' || report.features.webgl !== 'enabled') {
          throw new Error('GPU compositing or WebGL is not hardware enabled');
        }
        report.status = 'pass';
      }
    } catch (error) {
      report.status = 'fail';
      report.error = String(error?.message || error).slice(0, 300);
    }
    await writeFile(join(directory, 'report.json'), JSON.stringify(report, null, 2), { mode: 0o600 });
    console.log('OPENBOT_GRAPHICS ' + JSON.stringify({ directory, status: report.status }));
  }).catch(error => console.error('OPENBOT_GRAPHICS_REPORT_ERROR', String(error?.message || error).slice(0, 200)));
}

async function browserCheck(directory) {
  const fixture = `<!doctype html><style>body{margin:0;background:#102030}canvas{display:block}input,button{position:absolute;top:280px;height:40px}input{left:10px;width:200px}button{left:240px;width:100px}</style><canvas width="256" height="256"></canvas><input id="text"><button id="go">Next</button><script>
    const gl=document.querySelector('canvas').getContext('webgl',{preserveDrawingBuffer:true});
    const ext=gl&&gl.getExtension('WEBGL_debug_renderer_info');
    window.testRenderer=gl&&ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'';
    window.testFrames=0;
    function draw(){if(gl){gl.clearColor(0,1,0,1);gl.clear(gl.COLOR_BUFFER_BIT);}window.testFrames++;requestAnimationFrame(draw);}draw();
    document.querySelector('#go').onclick=()=>location.href='/second?value='+encodeURIComponent(document.querySelector('#text').value);
  </script>`;
  const server = createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.end(request.url.startsWith('/second?') ? '<!doctype html><title>second</title><p id="result">navigation passed</p>' : fixture);
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  let window;
  let view;
  let frames = 0;
  let navigation;
  try {
    window = new BrowserWindow({ width: 640, height: 480, show: false, webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false } });
    view = new WebContentsView({ webPreferences: {
      sandbox: true, contextIsolation: true, nodeIntegration: false, webSecurity: true,
      backgroundThrottling: false, partition: 'openbot-gpu-test-' + Date.now(),
    } });
    window.contentView.addChildView(view);
    view.setBounds({ x: 0, y: 0, width: 640, height: 480 });
    window.showInactive();
    const contents = view.webContents;
    contents.debugger.attach('1.3');
    contents.debugger.on('message', (_event, method, params) => {
      if (method === 'Page.screencastFrame') {
        if (params.data?.length > 100) frames++;
        void contents.debugger.sendCommand('Page.screencastFrameAck', { sessionId: params.sessionId }).catch(() => {});
      }
    });
    await contents.loadURL('http://127.0.0.1:' + server.address().port + '/first');
    await contents.debugger.sendCommand('Page.startScreencast', { format: 'jpeg', quality: 80, everyNthFrame: 1 });
    await delay(2500);
    const renderer = await contents.executeJavaScript('window.testRenderer');
    const animationFrames = await contents.executeJavaScript('window.testFrames');
    const shot = await contents.capturePage();
    const bitmap = shot.toBitmap();
    const size = shot.getSize();
    const at = (64 * size.width + 64) * 4;
    const pixel = Array.from(bitmap.subarray(at, at + 4));
    await writeFile(join(directory, 'browser.png'), shot.toPNG(), { mode: 0o600 });
    if (pixel[1] < 200 || pixel[0] > 40 || pixel[2] > 40 || animationFrames < 10 || frames < 1) {
      throw new Error('WebGL screenshot or live JPEG capture failed');
    }
    async function click(x, y) {
      await contents.debugger.sendCommand('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
      await contents.debugger.sendCommand('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    }
    await click(80, 300);
    await contents.debugger.sendCommand('Input.insertText', { text: 'a380-check' });
    const typed = await contents.executeJavaScript('document.querySelector("#text").value');
    if (typed !== 'a380-check') throw new Error('Browser text input failed');
    const loaded = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Browser navigation timeout')), 8000);
      contents.once('did-finish-load', () => { clearTimeout(timeout); resolve(); });
    });
    await Promise.all([loaded, click(280, 300)]);
    navigation = new URL(contents.getURL());
    if (navigation.pathname !== '/second' || navigation.searchParams.get('value') !== 'a380-check') throw new Error('Browser navigation failed');
    await contents.debugger.sendCommand('Page.stopScreencast');
    const preferences = contents.getLastWebPreferences();
    if (!preferences.sandbox || !preferences.contextIsolation || preferences.nodeIntegration || !preferences.webSecurity) {
      throw new Error('Browser security preferences changed');
    }
    return { renderer, animationFrames, jpegFrames: frames, screenshotSize: size, greenPixel: pixel, input: true, navigation: true,
      sandbox: preferences.sandbox, contextIsolation: preferences.contextIsolation, nodeIntegration: preferences.nodeIntegration, webSecurity: preferences.webSecurity };
  } finally {
    if (view && !view.webContents.isDestroyed()) view.webContents.close();
    if (window && !window.isDestroyed()) window.destroy();
    await new Promise(resolve => server.close(resolve));
  }
}
