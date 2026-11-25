# Locates the compiler's register save/restore helpers (savegprlr/restgprlr, savefpr/restfpr, savevmx/restvmx) in .text of
# the decrypted PE and counts branch instructions (bctr, mtctr, bctrl, blr, bl). Usage: python3 -I find_helpers.py <default.pe>
import struct,sys,collections
d=open(sys.argv[1],'rb').read(); B=0x82000000
t0,tl=0x82920000-B,0x9eed9c
w=struct.unpack('>%dI'%(tl//4),d[t0:t0+tl])
def va(i): return 0x82920000+4*i
pats={'savegprlr_14':[0xF9C1FF68,0xF9E1FF70],'restgprlr_14':[0xE9C1FF68,0xE9E1FF70],
 'savefpr_14':[0xD9CCFF70,0xD9ECFF78],'restfpr_14':[0xC9CCFF70,0xC9ECFF78],
 'savevmx_14':[0x3960FEE0,0x7DCB61CE],'restvmx_14':[0x3960FEE0,0x7DCB60CE]}
for n,p in pats.items():
    hits=[hex(va(i)) for i in range(len(w)-len(p)) if list(w[i:i+len(p)])==p]
    print(n,hits[:4])
# vmx 64: li r11,-0x400 ; stvx128 / lvx128 ...
for i in range(len(w)-2):
    if w[i]==0x3960FC00: print('li r11,-0x400 @',hex(va(i)),hex(w[i+1]),hex(w[i+2]))
c=collections.Counter()
for i,x in enumerate(w):
    if x==0x4E800420: c['bctr']+=1
    if x==0x7C0903A6 or (x&0xFC1FFFFF)==0x7C0903A6: c['mtctr']+=1
    if x==0x4E800421: c['bctrl']+=1
    if x==0x4E800020: c['blr']+=1
    if (x&0xFC000003)==0x48000001: c['bl']+=1
print(dict(c),'instrs',len(w))
