import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

function minimalEnvironment() {
  const keys = ['PATH', 'Path', 'SystemRoot', 'WINDIR', 'HOME', 'USERPROFILE', 'TMP', 'TEMP', 'LANG', 'LC_ALL', 'DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XDG_RUNTIME_DIR'];
  return Object.fromEntries(keys.filter((key) => process.env[key] !== undefined).map((key) => [key, process.env[key]]));
}
async function exists(command) {
  const locator = process.platform === 'win32' ? 'where.exe' : '/usr/bin/which';
  try { await execFileAsync(locator, [command], { env: minimalEnvironment(), windowsHide: true }); return true; } catch { return false; }
}
function validateZones(value) {
  if (!Array.isArray(value) || value.length > 128) throw new Error('redaction_zones_invalid');
  return value.map((zone) => {
    const result = {};
    for (const key of ['x', 'y', 'width', 'height']) {
      const item = zone?.[key];
      if (!Number.isSafeInteger(item) || item < 0 || item > 100000) throw new Error('redaction_zone_invalid');
      result[key] = item;
    }
    if (result.width < 1 || result.height < 1) throw new Error('redaction_zone_empty');
    return result;
  });
}
async function collect(child, input = null, max = 32 * 1024 * 1024) {
  const out = []; const err = []; let bytes = 0;
  child.stdout.on('data', (chunk) => { bytes += chunk.length; if (bytes <= max) out.push(chunk); });
  child.stderr.on('data', (chunk) => { if (err.reduce((sum, value) => sum + value.length, 0) < 8192) err.push(chunk); });
  if (input == null) child.stdin.end(); else child.stdin.end(input);
  const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
  if (code !== 0 || bytes > max) throw new Error(`desktop_command_failed:${code}:${Buffer.concat(err).toString('utf8').slice(-1000)}`);
  return Buffer.concat(out);
}
async function clipboardRead() {
  let command;
  if (process.platform === 'win32') command = ['powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Get-Clipboard -Raw']];
  else if (process.platform === 'darwin') command = ['/usr/bin/pbpaste', []];
  else if (await exists('wl-paste')) command = ['wl-paste', ['--no-newline']];
  else if (await exists('xclip')) command = ['xclip', ['-selection', 'clipboard', '-out']];
  else if (await exists('xsel')) command = ['xsel', ['--clipboard', '--output']];
  else throw new Error('clipboard_reader_unavailable');
  const child = spawn(command[0], command[1], { stdio: ['ignore', 'pipe', 'pipe'], env: minimalEnvironment(), windowsHide: true });
  const text = (await collect(child)).toString('utf8');
  return { status: 'ok', output: { text }, postcondition: { observed: true, textSha256: crypto.createHash('sha256').update(text).digest('hex'), bytes: Buffer.byteLength(text) } };
}
async function clipboardWrite(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > 4 * 1024 * 1024) throw new Error('clipboard_text_invalid');
  let command;
  if (process.platform === 'win32') command = ['powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '$input | Out-String | Set-Clipboard']];
  else if (process.platform === 'darwin') command = ['/usr/bin/pbcopy', []];
  else if (await exists('wl-copy')) command = ['wl-copy', []];
  else if (await exists('xclip')) command = ['xclip', ['-selection', 'clipboard', '-in']];
  else if (await exists('xsel')) command = ['xsel', ['--clipboard', '--input']];
  else throw new Error('clipboard_writer_unavailable');
  const child = spawn(command[0], command[1], { stdio: ['pipe', 'pipe', 'pipe'], env: minimalEnvironment(), windowsHide: true });
  await collect(child, Buffer.from(text, 'utf8'));
  const verify = await clipboardRead();
  if (verify.postcondition.textSha256 !== crypto.createHash('sha256').update(text).digest('hex')) throw new Error('clipboard_write_postcondition_failed');
  return { status: 'ok', output: { writtenBytes: Buffer.byteLength(text) }, postcondition: { observed: true, textSha256: verify.postcondition.textSha256 } };
}
async function redactWithImageMagick(file, zones) {
  if (zones.length === 0) return true;
  const executable = await exists('magick') ? 'magick' : await exists('convert') ? 'convert' : null;
  if (!executable) throw new Error('redaction_backend_unavailable');
  const args = executable === 'magick' ? [file] : [file];
  for (const zone of zones) {
    args.push('-fill', 'black', '-draw', `rectangle ${zone.x},${zone.y} ${zone.x + zone.width - 1},${zone.y + zone.height - 1}`);
  }
  args.push(file);
  const result = await execFileAsync(executable, args, { env: minimalEnvironment(), timeout: 60_000, maxBuffer: 1024 * 1024, windowsHide: true });
  return result !== null;
}
async function captureWindows(file, zones) {
  const zoneJson = JSON.stringify(zones).replace(/'/g, "''");
  const script = [
    'Add-Type -AssemblyName System.Windows.Forms',
    'Add-Type -AssemblyName System.Drawing',
    '$bounds=[System.Windows.Forms.SystemInformation]::VirtualScreen',
    '$bmp=New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height',
    '$g=[System.Drawing.Graphics]::FromImage($bmp)',
    '$g.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bounds.Size)',
    `$zones=ConvertFrom-Json '${zoneJson}'`,
    'foreach($z in @($zones)){ $g.FillRectangle([System.Drawing.Brushes]::Black,[int]$z.x,[int]$z.y,[int]$z.width,[int]$z.height) }',
    `$bmp.Save('${file.replace(/'/g, "''")}',[System.Drawing.Imaging.ImageFormat]::Png)`,
    '$g.Dispose();$bmp.Dispose()',
  ].join(';');
  await execFileAsync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script], { env: minimalEnvironment(), timeout: 60_000, maxBuffer: 1024 * 1024, windowsHide: true });
  return zones.length > 0;
}
async function captureScreen(zonesValue) {
  const zones = validateZones(zonesValue ?? []);
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'kristin-screen-'));
  const file = path.join(directory, 'capture.png');
  let redacted = false;
  try {
    if (process.platform === 'win32') redacted = await captureWindows(file, zones);
    else if (process.platform === 'darwin') {
      await execFileAsync('/usr/sbin/screencapture', ['-x', '-t', 'png', file], { env: minimalEnvironment(), timeout: 60_000, windowsHide: true });
      redacted = await redactWithImageMagick(file, zones);
    } else if (await exists('grim')) {
      await execFileAsync('grim', [file], { env: minimalEnvironment(), timeout: 60_000, windowsHide: true });
      redacted = await redactWithImageMagick(file, zones);
    } else if (await exists('gnome-screenshot')) {
      await execFileAsync('gnome-screenshot', ['-f', file], { env: minimalEnvironment(), timeout: 60_000, windowsHide: true });
      redacted = await redactWithImageMagick(file, zones);
    } else if (await exists('import')) {
      await execFileAsync('import', ['-window', 'root', file], { env: minimalEnvironment(), timeout: 60_000, windowsHide: true });
      redacted = await redactWithImageMagick(file, zones);
    } else throw new Error('screen_capture_backend_unavailable');
    const bytes = await fs.readFile(file);
    if (bytes.length < 64 || bytes.length > 32 * 1024 * 1024) throw new Error('screen_capture_size_invalid');
    return { status: 'ok', output: { bytesBase64: bytes.toString('base64'), mediaType: 'image/png' }, postcondition: { observed: true, bytes: bytes.length, imageSha256: crypto.createHash('sha256').update(bytes).digest('hex'), redactionZoneCount: zones.length, redactionApplied: zones.length === 0 || redacted } };
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
}
async function activeWindow() {
  let title = ''; let processName = '';
  if (process.platform === 'win32') {
    const script = `Add-Type @'\nusing System;using System.Runtime.InteropServices;public class W{[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();[DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetWindowText(IntPtr h,System.Text.StringBuilder s,int n);[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);}\n'@;$h=[W]::GetForegroundWindow();$s=New-Object Text.StringBuilder 2048;[void][W]::GetWindowText($h,$s,$s.Capacity);$p=0;[void][W]::GetWindowThreadProcessId($h,[ref]$p);$n=(Get-Process -Id $p).ProcessName;@{title=$s.ToString();process=$n}|ConvertTo-Json -Compress`;
    const { stdout } = await execFileAsync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script], { env: minimalEnvironment(), timeout: 30_000, windowsHide: true });
    const value = JSON.parse(stdout); title = value.title || ''; processName = value.process || '';
  } else if (process.platform === 'darwin') {
    const { stdout } = await execFileAsync('/usr/bin/osascript', ['-e', 'tell application "System Events" to tell first application process whose frontmost is true to return {name, name of front window}'], { env: minimalEnvironment(), timeout: 30_000 });
    const parts = stdout.trim().split(', '); processName = parts.shift() || ''; title = parts.join(', ');
  } else {
    if (!(await exists('xdotool'))) throw new Error('active_window_backend_unavailable');
    const { stdout: id } = await execFileAsync('xdotool', ['getactivewindow'], { env: minimalEnvironment(), timeout: 30_000 });
    const { stdout: name } = await execFileAsync('xdotool', ['getwindowname', id.trim()], { env: minimalEnvironment(), timeout: 30_000 });
    title = name.trim(); processName = 'xdotool-observed';
  }
  return { status: 'ok', output: { title, processName }, postcondition: { observed: true, titleSha256: crypto.createHash('sha256').update(title).digest('hex'), processNameSha256: crypto.createHash('sha256').update(processName).digest('hex') } };
}

export async function invokeInteractiveDesktopAdapter(operation, payload = {}) {
  if (operation === 'clipboard.read') return clipboardRead();
  if (operation === 'clipboard.write') return clipboardWrite(payload.text);
  if (operation === 'screen.capture') return captureScreen(payload.redactionZones);
  if (operation === 'screen.activeWindowMetadata') return activeWindow();
  throw new Error('interactive_operation_unsupported');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.once('line', async (line) => {
    try {
      const request = JSON.parse(line);
      const result = await invokeInteractiveDesktopAdapter(request.operation, request.payload);
      process.stdout.write(`${JSON.stringify(result)}\n`);
    } catch (error) {
      process.stderr.write(`interactive_adapter_error:${String(error?.message ?? error).slice(0, 1000)}\n`);
      process.exitCode = 1;
    } finally {
      rl.close();
    }
  });
}
