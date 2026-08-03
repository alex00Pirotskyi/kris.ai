#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,os,pathlib,platform,shutil,subprocess,sys,tempfile,time

def run(command,*,cwd=None,input_text=None,timeout=30):
 p=subprocess.run(command,cwd=cwd,input=input_text,text=True,capture_output=True,timeout=timeout)
 return {'command':command,'returnCode':p.returncode,'stdout':p.stdout[-4000:],'stderr':p.stderr[-4000:]}

def package_fixture(root:pathlib.Path):
 npm=shutil.which('npm')
 if not npm:return {'status':'blocked','reason':'npm_unavailable','assertions':[]}
 fixture=root/'evals/fixtures/p2/npm-local-package';fixture.mkdir(parents=True,exist_ok=True)
 (fixture/'package.json').write_text('{"name":"kristin-p2-local-fixture","version":"1.0.0"}\n')
 steps=[]
 with tempfile.TemporaryDirectory(prefix='p2-npm-fixture-') as temp_value:
  temp=pathlib.Path(temp_value)
  (temp/'package.json').write_text('{"name":"kristin-p2-host-smoke","version":"1.0.0","private":true}\n')
  dry_run=run([npm,'install','--dry-run','--ignore-scripts','--no-audit','--no-fund','--package-lock=false',str(fixture)],cwd=temp)
  steps.append(dry_run)
  install=run([npm,'install','--ignore-scripts','--no-audit','--no-fund','--package-lock=false',str(fixture)],cwd=temp)
  steps.append(install)
  installed=temp/'node_modules/kristin-p2-local-fixture/package.json'
  installed_ok=install['returnCode']==0 and installed.is_file()
  uninstall=run([npm,'uninstall','--ignore-scripts','--no-audit','--no-fund','--package-lock=false','kristin-p2-local-fixture'],cwd=temp)
  steps.append(uninstall)
  removed_ok=uninstall['returnCode']==0 and not installed.exists()
  node=shutil.which('node')
  provenance=run([node,'--version']) if node else {'command':['node','--version'],'returnCode':127,'stdout':'','stderr':'node unavailable'}
  steps.append(provenance)
 passed=dry_run['returnCode']==0 and installed_ok and removed_ok and provenance['returnCode']==0
 return {'status':'passed' if passed else 'blocked','reason':None if passed else 'controlled_package_fixture_failed','assertions':['controlled local package dry-run','controlled local package install/remove','SDK executable provenance'],'steps':steps,'installed':installed_ok,'removed':removed_ok}

def service_application_fixture():
 system=platform.system()
 checks=[]
 if system=='Windows':checks.append(run(['sc.exe','query','EventLog']))
 elif system=='Darwin':checks.append(run(['/bin/launchctl','print','system']))
 elif system=='Linux':
  if shutil.which('systemctl'):checks.append(run(['systemctl','list-units','--type=service','--no-pager'],timeout=20))
  if shutil.which('service'):checks.append(run(['service','--status-all'],timeout=20))
 child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'])
 alive=child.poll() is None;child.terminate()
 try:child.wait(timeout=5)
 except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
 app_ok=alive and child.returncode is not None
 service_ok=any(row['returnCode']==0 for row in checks)
 return {'status':'passed' if service_ok and app_ok else 'blocked','reason':None if service_ok and app_ok else 'native_service_fixture_unavailable','assertions':['native service status query','application process open/close identity fixture'],'steps':checks+[{'applicationFixture':{'started':alive,'terminated':app_ok,'exitCode':child.returncode}}]}

def clipboard_screen_fixture():
 system=platform.system();steps=[];clipboard=False;screen=False;active_window=False
 try:
  if system=='Windows':
   clip=run(['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',"Set-Clipboard -Value 'kristin-p2-fixture'; if ((Get-Clipboard -Raw).Trim() -eq 'kristin-p2-fixture') { exit 0 } else { exit 1 }"])
   steps.append(clip);clipboard=clip['returnCode']==0
   shot=run(['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',"Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $i=New-Object Drawing.Bitmap $b.Width,$b.Height; $g=[Drawing.Graphics]::FromImage($i); $g.CopyFromScreen($b.Location,[Drawing.Point]::Empty,$b.Size); $p=[IO.Path]::GetTempFileName()+'.png'; $i.Save($p,[Drawing.Imaging.ImageFormat]::Png); if ((Get-Item $p).Length -gt 0) { Remove-Item $p; exit 0 } else { exit 1 }"])
   steps.append(shot);screen=shot['returnCode']==0
   active=run(['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',"Add-Type @'\nusing System; using System.Runtime.InteropServices; public static class K { [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow(); }\n'@; if ([K]::GetForegroundWindow() -ne [IntPtr]::Zero) { exit 0 } else { exit 1 }"])
   steps.append(active);active_window=active['returnCode']==0
  elif system=='Darwin':
   clip=run(['/bin/sh','-c',"printf 'kristin-p2-fixture' | pbcopy && test \"$(pbpaste)\" = 'kristin-p2-fixture'"])
   steps.append(clip);clipboard=clip['returnCode']==0
   with tempfile.NamedTemporaryFile(suffix='.png',delete=False) as handle:path=handle.name
   shot=run(['/usr/sbin/screencapture','-x',path]);steps.append(shot);screen=shot['returnCode']==0 and pathlib.Path(path).stat().st_size>0;pathlib.Path(path).unlink(missing_ok=True)
   active=run(['/usr/bin/osascript','-e','tell application "System Events" to get unix id of first application process whose frontmost is true'])
   steps.append(active);active_window=active['returnCode']==0 and active['stdout'].strip().isdigit()
  elif system=='Linux':
   if shutil.which('wl-copy') and shutil.which('wl-paste'):
    clip=run(['/bin/sh','-c',"printf 'kristin-p2-fixture' | wl-copy && test \"$(wl-paste --no-newline)\" = 'kristin-p2-fixture'"]);steps.append(clip);clipboard=clip['returnCode']==0
   elif shutil.which('xclip'):
    clip=run(['/bin/sh','-c',"printf 'kristin-p2-fixture' | xclip -selection clipboard && test \"$(xclip -selection clipboard -o)\" = 'kristin-p2-fixture'"]);steps.append(clip);clipboard=clip['returnCode']==0
   with tempfile.NamedTemporaryFile(suffix='.png',delete=False) as handle:path=handle.name
   if shutil.which('grim'):shot=run(['grim',path])
   elif shutil.which('gnome-screenshot'):shot=run(['gnome-screenshot','-f',path])
   elif shutil.which('import'):shot=run(['import','-window','root',path])
   else:shot={'command':['screen-capture'],'returnCode':127,'stdout':'','stderr':'no capture backend'}
   steps.append(shot);screen=shot['returnCode']==0 and pathlib.Path(path).stat().st_size>0;pathlib.Path(path).unlink(missing_ok=True)
   if shutil.which('xdotool'):
    active=run(['xdotool','getactivewindow']);steps.append(active);active_window=active['returnCode']==0 and active['stdout'].strip().isdigit()
   elif os.environ.get('WAYLAND_DISPLAY') and shutil.which('gdbus'):
    active={'command':['active-window-metadata'],'returnCode':3,'stdout':'','stderr':'no approved compositor adapter'};steps.append(active)
  passed=clipboard and screen and active_window
 except Exception as exc:steps.append({'exception':repr(exc)});passed=False
 return {'status':'passed' if passed else 'blocked','reason':None if passed else 'interactive_desktop_clipboard_screen_or_active_window_unavailable','assertions':['clipboard round trip without content logging','screen capture nonempty fixture without evidence payload','active-window identity available without title/content logging'] if passed else [],'steps':steps,'clipboard':clipboard,'screen':screen,'activeWindow':active_window}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--output',required=True);ns=ap.parse_args();root=pathlib.Path(ns.project).resolve()
 tasks={'P2-007':package_fixture(root),'P2-008':service_application_fixture(),'P2-009':clipboard_screen_fixture()}
 payload={'schemaVersion':'1.0.0','generatedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'platform':platform.system().lower(),'status':'passed' if all(row['status']=='passed' for row in tasks.values()) else 'blocked','taskAssertions':tasks}
 out=pathlib.Path(ns.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(payload,indent=2)+'\n');print(json.dumps(payload,indent=2));return 0 if payload['status']=='passed' else 3
if __name__=='__main__':raise SystemExit(main())
