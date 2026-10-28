import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const policy = JSON.parse(readFileSync(process.argv[2], 'utf8'));
function mode({ optIn, disabled, crash, unfinished, server = true, platform = 'linux' } = {}) {
  let disabledCalls = 0;
  const context = {
    process: { platform, env: { OPENBOT_SERVER_GPU: optIn, OPENBOT_DISABLE_GPU: disabled }, versions: { chrome: '152.1' } },
    app: { disableHardwareAcceleration: () => disabledCalls++ },
    join: (...parts) => parts.join('/'), GPU_START_FILE: 'gpu-start.json', GPU_CRASH_FILE: 'gpu-crash.json',
    readGpuFailure: path => path.endsWith('gpu-crash.json') ? crash : unfinished,
    configureOpenBotServerGraphics: () => {},
  };
  const result = runInNewContext(policy.resolver + '\n' + policy.configure + '\nconfigureLinuxGpu({ userDataPath:"/fixture", ownsInstance:false, server:' + server + ' })', context);
  return { ...JSON.parse(JSON.stringify(result)), disabledCalls };
}
assert.deepEqual(mode(), { hardwareAcceleration: false, reason: 'server', disabledCalls: 1 });
assert.deepEqual(mode({ optIn: '0', disabled: '0' }), { hardwareAcceleration: false, reason: 'server', disabledCalls: 1 });
assert.deepEqual(mode({ optIn: '1' }), { hardwareAcceleration: true, reason: 'default', disabledCalls: 0 });
assert.deepEqual(mode({ optIn: '1', disabled: '1' }), { hardwareAcceleration: false, reason: 'environment-off', disabledCalls: 1 });
assert.deepEqual(mode({ optIn: '1', crash: { chromium: '152' } }), { hardwareAcceleration: false, reason: 'gpu-process-crash', disabledCalls: 1 });
assert.deepEqual(mode({ optIn: '1', unfinished: { chromium: '152' } }), { hardwareAcceleration: false, reason: 'unfinished-start', disabledCalls: 1 });
assert.equal(mode({ optIn: '1', crash: { chromium: '151' } }).hardwareAcceleration, true);
assert.equal(mode({ server: false }).hardwareAcceleration, true);
assert.equal(mode({ platform: 'darwin' }).reason, 'not-linux');
console.log('PASS: actual packaged GPU policy keeps opt-out, crash fallback and unfinished-start fallback.');
