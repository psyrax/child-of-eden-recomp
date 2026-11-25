# Prints the XEX2 header fields and the optional-header table of a .xex. Usage: python3 -I xexinfo.py <default.xex>
import struct,sys
d=open(sys.argv[1],'rb').read()
print(d[:4], 'module_flags=%08x'%struct.unpack('>I',d[4:8])[0],'pe_off=0x%x'%struct.unpack('>I',d[8:12])[0],'sec_off=0x%x'%struct.unpack('>I',d[16:20])[0],'nopt=',struct.unpack('>I',d[20:24])[0])
n=struct.unpack('>I',d[20:24])[0]
for i in range(n):
    k,v=struct.unpack('>II',d[24+8*i:32+8*i]); print('opt %08x = %08x'%(k,v))
