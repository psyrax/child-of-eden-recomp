// Diagnostic: loads a XEX with XenonUtils (from XenonRecomp), lists its sections and named imports, and dumps the
// decrypted PE image. Build it against XenonRecomp's XenonUtils library (see containers/experiments/build_xenonrecomp.sh).
// Usage: xexdump <default.xex> [<out.pe> [<symbols.txt>]]
#include <cstdio>
#include <fstream>
#include <vector>
#include <image.h>
#include <file.h>
int main(int argc,char**argv){
  auto file=LoadFile(argv[1]);
  auto img=Image::ParseImage(file.data(),file.size());
  printf("base=0x%zx size=0x%x entry=0x%zx sections=%zu symbols=%zu\n",img.base,img.size,img.entry_point,img.sections.size(),img.symbols.size());
  for(auto&s:img.sections) printf("  %-8s base=0x%zx size=0x%x %s\n",s.name.c_str(),s.base,s.size,(s.flags&SectionFlags_Code)?"CODE":"data");
  if(argc>2){ std::ofstream o(argv[2],std::ios::binary); o.write((char*)img.data.get(),img.size); }
  if(argc>3){ std::ofstream o(argv[3]); for(auto&s:img.symbols) fprintf(stdout,""),o<<s.name<<" 0x"<<std::hex<<s.address<<"\n"; }
}
