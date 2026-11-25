# Runs ON THE HANDHELD (as root: it reads /proc/<pid>/task/<tid>/stack) while the game is open. Samples the kernel stack
# of every thread of the `eden` process every 10 ms and prints, per thread, the share of samples running and the most
# common places where it waits. Usage: sudo python3 stack_sampler.py <seconds>
import os,sys,time,collections,subprocess
pid=subprocess.check_output(['pgrep','-x','eden']).split()[0].decode()
dur=float(sys.argv[1]); c=collections.defaultdict(collections.Counter); n=0
skip=('entry_SYSCALL','do_syscall','x64_sys_call','__x64_sys','__se_sys','schedule','__schedule','io_schedule','ret_from','syscall_')
t0=time.time()
while time.time()-t0<dur:
    for tid in os.listdir(f'/proc/{pid}/task'):
        try:
            comm=open(f'/proc/{pid}/task/{tid}/comm').read().strip()
            st=open(f'/proc/{pid}/task/{tid}/stat').read().rsplit(')',1)[1].split()[0]
            if st=='R': c[comm]['<running>']+=1; continue
            fr=[l.split()[1].split('+')[0] for l in open(f'/proc/{pid}/task/{tid}/stack') if len(l.split())>1]
            fr=[f for f in fr if not f.startswith(skip)]
            c[comm][' < '.join(fr[:4])]+=1
        except Exception as e: pass
    n+=1; time.sleep(0.01)
print('samples',n)
for comm,cc in sorted(c.items(), key=lambda kv:-sum(v for k,v in kv[1].items() if k=='<running>')):
    tot=sum(cc.values()); run=cc['<running>']
    if run/tot<0.03 and 'XThread' not in comm and 'GPU' not in comm: continue
    print(f'== {comm} running {100*run/tot:.0f}%')
    for k,v in cc.most_common(5):
        if k!='<running>': print(f'   {100*v/tot:5.1f}%  {k[:170]}')
