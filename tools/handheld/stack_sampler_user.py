# Runs ON THE HANDHELD while the game is open. Samples the user-space stacks (eu-stack, from elfutils) of the
# "GPU Commands" and "Main XThread" threads of the `eden` process, and reports their CPU use, the frequency of the
# core they ran on and the most common stacks. Usage: python3 stack_sampler_user.py <n_samples>
import os,sys,time,collections,subprocess,re
pid=subprocess.check_output(['pgrep','-x','eden']).split()[0].decode()
tids={}
for tid in os.listdir(f'/proc/{pid}/task'):
    comm=open(f'/proc/{pid}/task/{tid}/comm').read().strip()
    if comm.startswith('GPU Commands') or comm.startswith('Main XThread'): tids[comm[:12]]=tid
def cpu_t(tid):
    f=open(f'/proc/{pid}/task/{tid}/stat').read().rsplit(')',1)[1].split()
    return (int(f[11])+int(f[12]))/100.0, int(f[36])
n=int(sys.argv[1]); top=collections.defaultdict(collections.Counter); fr=collections.defaultdict(list); cores=collections.defaultdict(collections.Counter)
t0=time.time(); c0={k:cpu_t(t)[0] for k,t in tids.items()}
for i in range(n):
    for k,tid in tids.items():
        cpu=cpu_t(tid)[1]; cores[k][cpu]+=1
        try: fr[k].append(int(open(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq').read())/1e6)
        except: pass
        try:
            o=subprocess.run(['eu-stack','-1','-p',tid,'-n','14'],capture_output=True,text=True,timeout=5).stdout
        except Exception as e: continue
        fs=[]
        for l in o.splitlines():
            m=re.match(r'#\d+\s+0x[0-9a-f]+\s*(.*)',l)
            if m: fs.append((m.group(1).strip() or '?')[:60])
        top[k][' < '.join(fs[:6])]+=1
    time.sleep(0.15)
dt=time.time()-t0
for k,tid in tids.items():
    print(f'== {k}: cpu {100*(cpu_t(tid)[0]-c0[k])/dt:.0f}% (slowed down by the sampling); mean frequency {sum(fr[k])/max(1,len(fr[k])):.2f} GHz min {min(fr[k]):.2f} max {max(fr[k]):.2f}; cores {dict(cores[k])}')
    for s,v in top[k].most_common(12): print(f'  {v:3d}  {s}')
