import subprocess,sys,time
child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])
print(child.pid,flush=True);time.sleep(30)
