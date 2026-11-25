// eden - test hooks of the VR fork (stage 1). Goes in work/project/src/eden_hooks.cpp.
// Everything stays OFF unless the environment variables are set: without them the binary behaves like the normal one.
//
//   EDEN_VR_CAMLOG=<file>      logs the calls to sub_82FC09A8 (world, view, projection): one full frame every
//                              EDEN_VR_CAMLOG_EVERY frames (600 by default) and the running total per caller.
//   EDEN_VR_FAKEPAD=1          sets m_bFakeNatalPad (obj+80) = 1 on leaving the constructor sub_82D495F0.
//   EDEN_VR_SEP=<units>        eye separation in world units; alternates the eye every EDEN_VR_PERIOD frames (1).
//   EDEN_VR_SBS=1              squeezes each eye into its half of the screen (x' = x/2 ± w/2) to view it side by side.
//   EDEN_VR_LR=<hex,hex,...>   only touches the calls whose lr is in the list (empty = all the perspective ones).
//   EDEN_VR_ORTHO=1            with SBS, also squeezes the orthographic projections (interface).
// Stage 4, only with the OpenXR build (EDEN_VR_OPENXR=1):
//   EDEN_VR_HEAD=1             the scene camera follows the headset's head (rotation, position and projection of each
//                              eye) and that pair is delivered as a projection layer. In menus and tutorials the
//                              floating screen stays. EDEN_VR_HEAD=2: projection always (for tests).
//   EDEN_VR_SCALE=<u>          game units per meter (100 by default) for the position of the head and of the eyes.
//   EDEN_VR_HEAD_POS=0         does not move the camera with the head position (only rotation and eye separation).
//   EDEN_VR_CONTROLLERS=1      the hands of the synthetic skeleton come from the headset's controllers instead of the file.

#include "generated/default/eden_funcs.h"

#include <rex/ppc/hook.h>

#include <dlfcn.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <thread>
#include <vector>

namespace {

constexpr u32 kPtrRender = 0x83394224;  // *kPtrRender = render object; view at +128, projection at +256

struct VrOptions {
  FILE* log = nullptr;
  u32 every = 600;
  bool fakepad = false;
  float sep = 0.0f;
  u32 period = 1;
  bool sbs = false;
  bool ortho = false;
  std::vector<u32> lrs;
  bool camera = false;  // there is something to do in the camera hook
  int head = 0;
  float scale = 100.0f;
  bool head_pos = true;
  bool controllers = false;

  VrOptions() {
    if (const char* e = std::getenv("EDEN_VR_CAMLOG"); e && *e) log = std::fopen(e, "w");
    if (const char* e = std::getenv("EDEN_VR_CAMLOG_EVERY"); e && *e) every = std::max(1, std::atoi(e));
    if (const char* e = std::getenv("EDEN_VR_FAKEPAD"); e && *e == '1') fakepad = true;
    if (const char* e = std::getenv("EDEN_VR_SEP"); e && *e) sep = std::strtof(e, nullptr);
    if (const char* e = std::getenv("EDEN_VR_PERIOD"); e && *e) period = std::max(1, std::atoi(e));
    if (const char* e = std::getenv("EDEN_VR_SBS"); e && *e == '1') sbs = true;
    if (const char* e = std::getenv("EDEN_VR_ORTHO"); e && *e == '1') ortho = true;
    if (const char* e = std::getenv("EDEN_VR_LR"); e && *e) {
      char* end = nullptr;
      for (const char* p = e; *p;) {
        u32 v = static_cast<u32>(std::strtoul(p, &end, 16));
        if (end == p) break;
        lrs.push_back(v);
        p = (*end == ',') ? end + 1 : end;
      }
    }
    if (const char* e = std::getenv("EDEN_VR_HEAD"); e && *e) head = std::atoi(e);
    if (const char* e = std::getenv("EDEN_VR_SCALE"); e && *e) scale = std::strtof(e, nullptr);
    if (const char* e = std::getenv("EDEN_VR_HEAD_POS"); e && *e == '0') head_pos = false;
    if (const char* e = std::getenv("EDEN_VR_CONTROLLERS"); e && *e == '1') controllers = true;
    camera = log || sep != 0.0f || sbs || head || controllers;
    if (head || controllers)
      std::fprintf(stderr, "[vr] head=%d scale=%g head_pos=%d controllers=%d\n", head, scale, head_pos, controllers);
    if (camera || fakepad)
      std::fprintf(stderr, "[vr] log=%d every=%u fakepad=%d sep=%g period=%u sbs=%d ortho=%d lrs=%zu\n", log != nullptr,
                   every, fakepad, sep, period, sbs, ortho, lrs.size());
  }
};

VrOptions& Opt() {
  static VrOptions o;
  return o;
}

std::atomic<u32> g_frame{0};
std::mutex g_mutex;
std::map<u32, u32> g_by_lr;       // running total since the last summary
u32 g_call_in_frame = 0;
u32 g_frame_seen = 0;

float ReadF(const u8* p, int i) {
  u32 v;
  std::memcpy(&v, p + 4 * i, 4);
  v = __builtin_bswap32(v);
  float f;
  std::memcpy(&f, &v, 4);
  return f;
}

void WriteF(u8* p, int i, float f) {
  u32 v;
  std::memcpy(&v, &f, 4);
  v = __builtin_bswap32(v);
  std::memcpy(p + 4 * i, &v, 4);
}

// 'P' perspective with row vectors (m[11]=±1, m[15]=0), 'p' perspective with column vectors (m[14]=±1),
// 'O' orthographic (m[15]=1 and no perspective term), '?' anything else.
char Classify(const u8* m) {
  const float m11 = ReadF(m, 11), m14 = ReadF(m, 14), m15 = ReadF(m, 15), m3 = ReadF(m, 3), m7 = ReadF(m, 7);
  if (std::fabs(m15) < 1e-4f && std::fabs(std::fabs(m11) - 1.0f) < 1e-3f && std::fabs(m3) < 1e-4f && std::fabs(m7) < 1e-4f)
    return 'P';
  if (std::fabs(m15) < 1e-4f && std::fabs(std::fabs(m14) - 1.0f) < 1e-3f) return 'p';
  if (std::fabs(m15 - 1.0f) < 1e-4f && std::fabs(m11) < 1e-4f && std::fabs(m3) < 1e-4f && std::fabs(m7) < 1e-4f &&
      std::fabs(m14) <= 1.0001f)
    return 'O';
  return '?';
}

void Dump(FILE* f, const char* name, const u8* m) {
  std::fprintf(f, " %s=[", name);
  for (int i = 0; i < 16; ++i) std::fprintf(f, "%s%.5g", i ? " " : "", ReadF(m, i));
  std::fprintf(f, "]");
}

}  // namespace

// End of frame: the only function of the game that calls VdSwap.
namespace {
u32 StackFrame();
void DumpStack(const char* where, PPCContext& ctx, u8* base);
}  // namespace
// Stages 3 and 4: if the SDK was built with the headset output (REXGLUE_VR_OPENXR), it exports rex_vr_mark_eye2 and
// rex_vr_state. The structs are a copy of the ones in vulkan_openxr.cpp: change both.
extern "C" {
struct RexVrView {
  float pos[3];
  float quat[4];  // x y z w
  float fov[4];   // left, right, up, down (radians)
  int valid;
};
struct RexVrController {
  int active;
  float pos[3];
  float quat[4];
  float trigger;
  float grip;
};
struct RexVrState {
  int ready;
  RexVrView eye[2];
  RexVrController controller[2];  // 0 = left, 1 = right
  float quad_dist, quad_width;
};
}
namespace {
// The SDK's GPU library is loaded with dlopen (local) after startup: a weak symbol of the executable is never
// resolved against it (measured in run 261: in stage 3 the eye mark did not arrive and the eye was assigned
// by parity). Here the functions are looked up in the already loaded library, and only if the headset output was requested.
struct VrApi {
  void (*mark_eye2)(int, const RexVrView*) = nullptr;
  int (*state)(RexVrState*) = nullptr;
};
VrApi& Api() {
  static VrApi a;
  static bool resolved = false, requested = [] { const char* e = std::getenv("EDEN_VR_OPENXR"); return e && *e == '1'; }();
  static u32 attempts = 0;
  if (!requested || resolved || (attempts++ % 30) != 0) return a;
  if (void* h = dlopen("librexgpu-xenos-vulkan.so", RTLD_LAZY | RTLD_NOLOAD)) {
    a.mark_eye2 = reinterpret_cast<void (*)(int, const RexVrView*)>(dlsym(h, "rex_vr_mark_eye2"));
    a.state = reinterpret_cast<int (*)(RexVrState*)>(dlsym(h, "rex_vr_state"));
    resolved = true;
    std::fprintf(stderr, "[vr] link to the headset output: mark_eye2=%d state=%d%s\n", a.mark_eye2 != nullptr,
                 a.state != nullptr, a.state ? "" : " (this SDK build has no OpenXR: build with tools/build/build_xr.sh)");
  }
  return a;
}
// State of the frame in progress (touched by the camera hook and the end-of-frame hook, on the game's main thread).
struct VrFrame {
  u32 frame = ~0u;
  bool ready = false;       // there is a session and valid views
  RexVrState st{};
  bool proj = false;        // this pair is drawn with the headset view (projection layer)
  bool used_ok = false;     // this frame's scene camera used `used`
  RexVrView used{};
  bool menu = false;        // a menu or tutorial camera was seen in this frame
  u32 lr_menu = 0;          // why: the interface caller that was seen (1 = scene view not moving)
};
VrFrame g_vf;
std::atomic<bool> g_menu{true};  // the previous frame was a menu (or had no moving scene): floating screen
bool g_ref_ok = false;
float g_ref[3];                  // head position at the start: origin of the movement
constexpr u32 kLrScene = 0x829EDEBC;

void Rotation(const float q[4], float R[3][3]) {
  const float x = q[0], y = q[1], z = q[2], w = q[3];
  R[0][0] = 1 - 2 * (y * y + z * z), R[0][1] = 2 * (x * y - w * z), R[0][2] = 2 * (x * z + w * y);
  R[1][0] = 2 * (x * y + w * z), R[1][1] = 1 - 2 * (x * x + z * z), R[1][2] = 2 * (y * z - w * x);
  R[2][0] = 2 * (x * z - w * y), R[2][1] = 2 * (y * z + w * x), R[2][2] = 1 - 2 * (x * x + y * y);
}
// Prepares the frame state the first time it is called within the frame.
VrFrame& FrameVr(u32 frame, int eye) {
  VrFrame& c = g_vf;
  if (c.frame == frame) return c;
  const bool proj_before = c.proj;
  c.frame = frame;
  c.used_ok = false;
  c.menu = false;
  c.ready = Api().state && Api().state(&c.st) != 0;
  if (c.ready && !g_ref_ok) {
    for (int k = 0; k < 3; ++k) g_ref[k] = 0.5f * (c.st.eye[0].pos[k] + c.st.eye[1].pos[k]);
    g_ref_ok = true;
  }
  // The mode is decided on the left eye and holds for the whole pair.
  if (eye == 0)
    c.proj = c.ready && Opt().head && (Opt().head >= 2 || !g_menu.load(std::memory_order_relaxed));
  else
    c.proj = proj_before && c.ready;
  return c;
}
}  // namespace
void StutterDiagFrame(double swap_ms);  // defined at the end (performance round)
REX_HOOK_RAW(sub_82E658D0) {
  const auto t_swap = std::chrono::steady_clock::now();
  {
    const u32 c0 = g_frame.load(std::memory_order_relaxed);
    const int eye = static_cast<int>((c0 / Opt().period) & 1);
    const bool mine = (g_vf.frame == c0);
    if (Api().mark_eye2) Api().mark_eye2(eye, (mine && g_vf.proj && g_vf.used_ok) ? &g_vf.used : nullptr);
    // Menu = an interface camera was seen, or the scene camera did not move (title, loading screens).
    if (Opt().camera) g_menu.store(!mine || g_vf.menu, std::memory_order_relaxed);
    if ((Opt().head || Opt().controllers) && std::getenv("EDEN_VR_TRACE") && c0 % 300 == 0)
      std::fprintf(stderr, "[vr-mode] frame=%u camera_seen=%d menu=%d by=%08X ready=%d proj=%d used=%d\n", c0, mine, g_vf.menu,
                   g_vf.lr_menu, g_vf.ready, g_vf.proj, g_vf.used_ok);
  }
  static bool done = false;
  if (StackFrame() && !done && g_frame.load() >= StackFrame()) {
    done = true;
    DumpStack("end_of_frame", ctx, base);
  }
  __imp__sub_82E658D0(ctx, base);
  StutterDiagFrame(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_swap).count());
  const u32 c = g_frame.fetch_add(1, std::memory_order_relaxed) + 1;
  // EDEN_VR_FPS=1: real frames per second every 600 frames (to measure the per-eye rate when alternating).
  static const bool fps = [] { const char* e = std::getenv("EDEN_VR_FPS"); return e && *e == '1'; }();
  if (fps && c % 600 == 0) {
    static auto before = std::chrono::steady_clock::now();
    const auto now = std::chrono::steady_clock::now();
    const double s = std::chrono::duration<double>(now - before).count();
    before = now;
    if (c > 600) std::fprintf(stderr, "[vr-fps] frame=%u %.1f fps\n", c, 600.0 / s);
  }
}

// Camera: sub_82FC09A8(r3 = world, r4 = view, r5 = projection).
REX_HOOK_RAW(sub_82FC09A8) {
  VrOptions& o = Opt();
  if (!o.camera) {
    __imp__sub_82FC09A8(ctx, base);
    return;
  }
  const u32 lr = static_cast<u32>(ctx.lr);
  const u32 g_view = ctx.r4.u32, g_proj = ctx.r5.u32;
  const u32 frame = g_frame.load(std::memory_order_relaxed);
  const char kind = Classify(reinterpret_cast<const u8*>(REX_RAW_ADDR(g_proj)));

  if (o.log) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (frame != g_frame_seen) {
      if (frame / o.every != g_frame_seen / o.every) {
        std::fprintf(o.log, "SUMMARY up_to_frame=%u", frame);
        for (auto& [k, v] : g_by_lr) std::fprintf(o.log, " %08X:%u", k, v);
        std::fprintf(o.log, "\n");
        std::fflush(o.log);
        g_by_lr.clear();
      }
      g_frame_seen = frame;
      g_call_in_frame = 0;
    }
    ++g_by_lr[lr];
    if (frame % o.every == 0) {
      const u8* P = reinterpret_cast<const u8*>(REX_RAW_ADDR(g_proj));
      const u8* V = reinterpret_cast<const u8*>(REX_RAW_ADDR(g_view));
      std::fprintf(o.log, "frame=%u n=%u lr=%08X type=%c", frame, g_call_in_frame, lr, kind);
      if (kind == 'P' || kind == 'p') {
        const float fovy = 2.0f * std::atan(1.0f / ReadF(P, 5)) * 57.29578f;
        std::fprintf(o.log, " fovy=%.2f aspect=%.4f", fovy, ReadF(P, 5) / ReadF(P, 0));
      }
      Dump(o.log, "P", P);
      Dump(o.log, "V", V);
      std::fprintf(o.log, "\n");
    }
    ++g_call_in_frame;
  }

  __imp__sub_82FC09A8(ctx, base);

  // Stage 4: headset head. The scene camera (a single caller) receives the rotation and position of the eye and its
  // asymmetric projection; the 3D interface layers mark the frame as "menu" (floating screen).
  if (o.head || o.controllers) {
    const int eye_i = static_cast<int>((frame / o.period) & 1);
    VrFrame& c = FrameVr(frame, eye_i);
    const u32 R0 = REX_LOAD_U32(kPtrRender);
    if (lr != kLrScene) {
      c.menu = true;
      c.lr_menu = lr;
    } else if (R0 && kind == 'P') {
      u8* V = reinterpret_cast<u8*>(REX_RAW_ADDR(R0 + 128));
      u8* P = reinterpret_cast<u8*>(REX_RAW_ADDR(R0 + 256));
      // Title and loading screens: the scene view is the identity; there is no world to look at there.
      bool identity = true;
      for (int i = 0; i < 16 && identity; ++i) identity = std::fabs(ReadF(V, i) - ((i % 5 == 0) ? 1.0f : 0.0f)) < 1e-5f;
      if (identity) c.menu = true, c.lr_menu = 1;
      if (c.proj) {
        const RexVrView& v = c.st.eye[eye_i];
        float Rm[3][3], t[3];
        Rotation(v.quat, Rm);
        for (int k = 0; k < 3; ++k) {
          const float center = 0.5f * (c.st.eye[0].pos[k] + c.st.eye[1].pos[k]);
          t[k] = o.scale * ((v.pos[k] - center) + (o.head_pos ? (center - g_ref[k]) : 0.0f));
        }
        // Row vectors: p_eye = p_view · M, with M = [R ; −Rᵀ·t] (OpenXR and the game: X right, Y up, −Z forward).
        float M[16] = {0}, A[16], N[16];
        for (int i = 0; i < 3; ++i)
          for (int j = 0; j < 3; ++j) M[4 * i + j] = Rm[i][j];
        for (int j = 0; j < 3; ++j) M[12 + j] = -(Rm[0][j] * t[0] + Rm[1][j] * t[1] + Rm[2][j] * t[2]);
        M[15] = 1.0f;
        for (int i = 0; i < 16; ++i) A[i] = ReadF(V, i);
        for (int i = 0; i < 4; ++i)
          for (int j = 0; j < 4; ++j) {
            float s = 0;
            for (int k = 0; k < 4; ++k) s += A[4 * i + k] * M[4 * k + j];
            N[4 * i + j] = s;
          }
        for (int i = 0; i < 16; ++i) WriteF(V, i, N[i]);
        const float tl = std::tan(v.fov[0]), tr = std::tan(v.fov[1]), tu = std::tan(v.fov[2]), td = std::tan(v.fov[3]);
        WriteF(P, 0, 2.0f / (tr - tl));
        WriteF(P, 5, 2.0f / (tu - td));
        WriteF(P, 8, (tr + tl) / (tr - tl));
        WriteF(P, 9, (tu + td) / (tu - td));
        c.used = v;
        c.used_ok = true;
        return;
      }
    }
    // No projection (menu): the usual stereo pair; if EDEN_VR_SEP was not given, the real separation of the eyes.
    if (o.sep == 0.0f && !o.sbs && c.ready && o.head && (kind == 'P')) {
      float d2 = 0;
      for (int k = 0; k < 3; ++k) d2 += (c.st.eye[1].pos[k] - c.st.eye[0].pos[k]) * (c.st.eye[1].pos[k] - c.st.eye[0].pos[k]);
      if (R0) {
        u8* V = reinterpret_cast<u8*>(REX_RAW_ADDR(R0 + 128));
        WriteF(V, 12, ReadF(V, 12) - (eye_i ? 0.5f : -0.5f) * std::sqrt(d2) * o.scale);
      }
      return;
    }
  }

  if (o.sep == 0.0f && !o.sbs) return;
  if (!o.lrs.empty()) {
    bool found = false;
    for (u32 v : o.lrs) found |= (v == lr);
    if (!found) return;
  }
  const bool persp = (kind == 'P' || kind == 'p');
  if (!persp && !(o.sbs && o.ortho && kind == 'O')) return;

  const u32 R = REX_LOAD_U32(kPtrRender);
  if (!R) return;
  u8* V = reinterpret_cast<u8*>(REX_RAW_ADDR(R + 128));
  u8* P = reinterpret_cast<u8*>(REX_RAW_ADDR(R + 256));
  const float eye = ((frame / o.period) & 1) ? 1.0f : -1.0f;  // -1 left, +1 right
  const bool row = (kind != 'p');

  if (persp && o.sep != 0.0f) {
    // Moving the eye +d along the camera's X axis = subtracting d from the X of every point in view space.
    const int i = row ? 12 : 3;
    WriteF(V, i, ReadF(V, i) - eye * o.sep * 0.5f);
  }
  if (o.sbs) {
    // x' = x/2 + eye*w/2: each eye in its half of the screen, without touching the viewport.
    for (int k = 0; k < 4; ++k) {
      const int ix = row ? 4 * k : k, iw = row ? 4 * k + 3 : 12 + k;
      WriteF(P, ix, 0.5f * ReadF(P, ix) + eye * 0.5f * ReadF(P, iw));
    }
  }
}

// Constructor of the Natal cursor: m_bFakeNatalPad is the byte obj+80 (0 by default).
REX_HOOK_RAW(sub_82D495F0) {
  const u32 obj = ctx.r3.u32;
  __imp__sub_82D495F0(ctx, base);
  if (Opt().fakepad && obj) {
    *reinterpret_cast<u8*>(REX_RAW_ADDR(obj + 80)) = 1;
    std::fprintf(stderr, "[vr] FakeNatalPad enabled on obj=%08X\n", obj);
  }
}

// --- NUI library (Kinect): logging and simulated startup ---------------------------------------------------------
//   EDEN_VR_NUILOG=1    logs to stderr the first calls to each NUI function, with its caller and result.
//   EDEN_VR_FAKENUI=1   NuiInitialize, NuiSkeletonTrackingEnable and NuiImageStreamOpen return success without touching
//                       the hardware; the "next frame" calls return failure (no data). Only to see what the game does.
namespace {
struct NuiOpt {
  bool log = false, fake = false;
  NuiOpt() {
    if (const char* e = std::getenv("EDEN_VR_NUILOG"); e && *e == '1') log = true;
    if (const char* e = std::getenv("EDEN_VR_FAKENUI"); e && *e == '1') fake = log = true;
  }
};
NuiOpt& Nui() {
  static NuiOpt o;
  return o;
}
void NuiLog(const char* name, std::atomic<u32>& n, u32 lr, u32 a0, u32 a1, u32 res) {
  const u32 k = n.fetch_add(1);
  if (k < 6 || (k % 2000) == 0)
    std::fprintf(stderr, "[vr-nui] %s #%u lr=%08X r3=%08X r4=%08X -> %08X\n", name, k, lr, a0, a1, res);
}
}  // namespace

#define VR_NUI_HOOK(sub, name, fake_expr)                                       \
  REX_HOOK_RAW(sub) {                                                           \
    NuiOpt& o = Nui();                                                          \
    if (!o.log) {                                                               \
      __imp__##sub(ctx, base);                                                  \
      return;                                                                   \
    }                                                                           \
    static std::atomic<u32> n{0};                                               \
    const u32 lr = static_cast<u32>(ctx.lr), a0 = ctx.r3.u32, a1 = ctx.r4.u32;  \
    if (o.fake && (fake_expr) != 1u)                                            \
      ctx.r3.u64 = static_cast<u32>(fake_expr);                                 \
    else                                                                        \
      __imp__##sub(ctx, base);                                                  \
    NuiLog(name, n, lr, a0, a1, ctx.r3.u32);                                    \
  }

// fake_expr: value to return in simulated mode; 1 = do not simulate (call the original).
VR_NUI_HOOK(sub_82D54010, "CNatal::Init", 1u)
VR_NUI_HOOK(sub_82D531E8, "CNatal::thread", 1u)
VR_NUI_HOOK(sub_83106DC8, "NuiInitialize", 0u)
VR_NUI_HOOK(sub_830FB2E8, "NuiSkeletonTrackingEnable", 0u)
VR_NUI_HOOK(sub_830FB438, "NuiSkeletonGetNextFrame", 0x80004005u)
VR_NUI_HOOK(sub_830FD820, "NuiImageStreamOpen", 0u)
VR_NUI_HOOK(sub_830FCC68, "NuiImageStreamGetNextFrame", 0x80004005u)
VR_NUI_HOOK(sub_830FCF90, "NuiImageStreamReleaseFrame", 0u)
// Stage 2: the title adjusts the sensor tilt ("Your sensor is starting up") and retries while it fails.
VR_NUI_HOOK(sub_830FE6B8, "NuiCameraAdjustTilt", 0u)

// --- Stage 2: Kinect mode without a Kinect -----------------------------------------------------------------------
//   EDEN_VR_NATALACTIVE=<n>  before each CNatal::Update (sub_82D546A8) writes n to the sensor's global state
//                            (0x8337CCB0; 1 = "all good", what sub_82D52388 leaves when the frame arrives without error).
//                            Update copies it to obj+440 and sub_82D4E920 ("Kinect active?") answers yes with 1..3 or 10.
//                            Requires EDEN_VR_FAKENUI=1 (so that Init leaves obj+96 = 1).
namespace {
constexpr u32 kNatalState = 0x8337CCB0;
int NatalActive() {
  static int v = [] {
    const char* e = std::getenv("EDEN_VR_NATALACTIVE");
    return (e && *e) ? std::atoi(e) : 0;
  }();
  return v;
}
void WriteU32(u8* base, u32 addr, u32 v) {
  v = __builtin_bswap32(v);
  std::memcpy(REX_RAW_ADDR(addr), &v, 4);
}
}  // namespace

// --- Stage 2: synthetic skeleton ----------------------------------------------------------------------------------
//   EDEN_VR_SKELETON=1         before each CNatal::Update publishes a NUI_SKELETON_FRAME (2736 bytes) with one
//                              "tracked" player in the same global buffers where the Kinect thread (sub_82D531E8) leaves it:
//                              refined at 0x8337A120 + i*2736, raw at 0x8337B6D0 + i*2736 (i = *0x8337CC7C),
//                              frame number at 0x8333CA40, and sensor state = 1. Implies NATALACTIVE=1.
//   EDEN_VR_HANDS=<file>       position of the hands in meters, Kinect space (x to the player's right, y up,
//                              z = distance to the sensor): "rx ry rz lx ly lz" (right, left). Re-read every frame;
//                              this is the point where the VR controllers come in later. No file: right hand forward.
//                              Alternate format (stage 3): "a <right°> <up°> <trigger_n> <mode>", see PublishSkeleton.
namespace {
constexpr u32 kSkelRefined = 0x8337A120, kSkelRaw = 0x8337B6D0, kSkelIndex = 0x8337CC7C, kSkelFrame = 0x8333CA40;
constexpr u32 kSkelArrived = 0x8337CCAC, kSkelNoPlayer = 0x8333CA3C;
struct SkelOpt {
  bool active = false;
  const char* hands = nullptr;
  SkelOpt() {
    if (const char* e = std::getenv("EDEN_VR_SKELETON"); e && *e == '1') active = true;
    if (const char* e = std::getenv("EDEN_VR_HANDS"); e && *e) hands = e;
  }
};
SkelOpt& Skel() {
  static SkelOpt o;
  return o;
}
void WriteBE32(u8* p, u32 v) {
  v = __builtin_bswap32(v);
  std::memcpy(p, &v, 4);
}
void WriteVec(u8* p, float x, float y, float z, float w) {
  WriteF(p, 0, x), WriteF(p, 1, y), WriteF(p, 2, z), WriteF(p, 3, w);
}
// Joints in XDK order: hip, spine, shoulders, head, left arm (shoulder, elbow, wrist, hand),
// right arm, left leg (hip, knee, ankle, foot), right leg.
void BuildSkeleton(u8* f, u32 number, const float rh[3], const float lh[3]) {
  std::memset(f, 0, 2736);
  WriteBE32(f + 4, number * 33);     // liTimeStamp (low part), ms
  WriteBE32(f + 8, number);          // dwFrameNumber
  WriteVec(f + 16, 0, 1, 0, 1);      // vFloorClipPlane
  WriteVec(f + 32, 0, 1, 0, 0);      // vNormalToGravity
  u8* s = f + 48;                    // SkeletonData[0], 448 bytes each
  WriteBE32(s + 0, 2);               // eTrackingState = tracked
  WriteBE32(s + 4, 1);               // dwTrackingID
  const float z = 2.2f;
  float j[20][3] = {
      {0, 0, z},          {0, 0.2f, z},        {0, 0.45f, z},       {0, 0.65f, z},
      {-0.2f, 0.4f, z},   {0, 0, 0},           {0, 0, 0},           {lh[0], lh[1], lh[2]},
      {0.2f, 0.4f, z},    {0, 0, 0},           {0, 0, 0},           {rh[0], rh[1], rh[2]},
      {-0.1f, -0.05f, z}, {-0.1f, -0.5f, z},   {-0.1f, -0.9f, z},   {-0.1f, -0.95f, z - 0.1f},
      {0.1f, -0.05f, z},  {0.1f, -0.5f, z},    {0.1f, -0.9f, z},    {0.1f, -0.95f, z - 0.1f}};
  for (int side = 0; side < 2; ++side) {  // elbow and wrist interpolated between shoulder and hand
    const int h = side ? 8 : 4;
    for (int k = 0; k < 3; ++k) {
      j[h + 1][k] = j[h][k] + 0.5f * (j[h + 3][k] - j[h][k]);
      j[h + 2][k] = j[h][k] + 0.9f * (j[h + 3][k] - j[h][k]);
    }
    j[h + 1][1] -= 0.08f;
  }
  WriteVec(s + 16, j[0][0], j[0][1], j[0][2], 1);
  for (int i = 0; i < 20; ++i) {
    WriteVec(s + 32 + 16 * i, j[i][0], j[i][1], j[i][2], 1);
    WriteBE32(s + 352 + 4 * i, 2);   // joint tracked
  }
}
float g_rh[3], g_lh[3];  // last published hands (for the stage 3 trace)
// Stage 4: hands from the headset's controllers. Returns false if there is no session or no active controllers.
//  - In the level: the controller's direction (relative to the forward of LOCAL space) is the aim angle (stage 3
//    law). Right trigger = shot (one pulse per press). Left trigger held = rapid fire, aiming with
//    the left controller. Both grips = Euphoria.
//  - In menus and tutorials (floating screen): the right controller is a laser pointer on the screen; the point where
//    it hits is converted into the hand position that takes the cursor there (menu cursor law, stage 2).
bool HandsFromControllers(float rh[3], float lh[3]) {
  if (!Opt().controllers || !Api().state) return false;
  RexVrState st;
  if (!Api().state(&st)) return false;
  const RexVrController& R = st.controller[1];
  const RexVrController& L = st.controller[0];
  if (!R.active && !L.active) return false;
  auto fwd = [](const RexVrController& m, float d[3]) {  // −Z of the controller in LOCAL space
    const float x = m.quat[0], y = m.quat[1], z = m.quat[2], w = m.quat[3];
    d[0] = -2 * (x * z + w * y), d[1] = -2 * (y * z - w * x), d[2] = -(1 - 2 * (x * x + y * y));
  };
  auto angles = [&](const RexVrController& m, float* yaw, float* pitch) {
    float d[3];
    fwd(m, d);
    *yaw = std::atan2(d[0], -d[2]) * 57.29578f;
    *pitch = std::asin(std::fmax(-1.0f, std::fmin(1.0f, d[1]))) * 57.29578f;
    *yaw = std::fmax(-60.0f, std::fmin(60.0f, *yaw));
    *pitch = std::fmax(-45.0f, std::fmin(45.0f, *pitch));
  };
  static bool pressed = false;
  static int pulse = 0;
  const bool now = pressed ? (R.trigger > 0.3f) : (R.trigger > 0.6f);
  if (now && !pressed) pulse = 10;  // Update calls = 5 skeleton frames (like the file input)
  pressed = now;
  const float z = (pulse > 0) ? 1.55f : 1.75f;
  if (pulse > 0) --pulse;
  const float kDegrees = 133.33f, kRefX = 0.135f, kRefY = 0.2383f;
  static u32 n = 0;
  const bool trace = (std::getenv("EDEN_VR_TRACE") != nullptr) && (n++ % 60) == 0;
  if (g_menu.load(std::memory_order_relaxed)) {
    if (!R.active) return false;
    float d[3];
    fwd(R, d);
    if (d[2] > -0.05f) return false;  // pointing sideways or backwards: does not hit the screen
    const float s = (-st.quad_dist - R.pos[2]) / d[2];
    const float hx = R.pos[0] + s * d[0], hy = R.pos[1] + s * d[1];
    const float height = st.quad_width * 720.0f / 1280.0f;
    const float px = std::fmax(-60.0f, std::fmin(1340.0f, (hx / st.quad_width + 0.5f) * 1280.0f));
    const float py = std::fmax(-60.0f, std::fmin(780.0f, (0.5f - hy / height) * 720.0f));
    rh[0] = 0.20f + (px - 860.0f) / 3450.0f, rh[1] = 0.20f + (435.0f - py) / 1933.0f, rh[2] = 1.75f;
    if (trace)
      std::fprintf(stderr, "[vr-ctrl] menu px=%.0f py=%.0f hand=%.3f,%.3f ctrl=%.2f,%.2f,%.2f dir=%.2f,%.2f,%.2f\n", px, py, rh[0],
                   rh[1], R.pos[0], R.pos[1], R.pos[2], d[0], d[1], d[2]);
    return true;
  }
  float yaw = 0, pitch = 0;
  int mode = 0;
  if (R.grip > 0.7f && L.grip > 0.7f) {
    mode = 2;
    rh[0] = 0.3f, rh[1] = 0.9f, rh[2] = 2.0f;
    lh[0] = -0.3f, lh[1] = 0.9f, lh[2] = 2.0f;
  } else if (L.active && L.trigger > 0.5f) {
    mode = 1;
    angles(L, &yaw, &pitch);
    rh[0] = 0.3f, rh[1] = -0.15f, rh[2] = 2.15f;
    lh[0] = -kRefX + yaw / kDegrees, lh[1] = kRefY + pitch / kDegrees, lh[2] = 1.75f;
  } else if (R.active) {
    angles(R, &yaw, &pitch);
    rh[0] = kRefX + yaw / kDegrees, rh[1] = kRefY + pitch / kDegrees, rh[2] = z;
  } else {
    return false;
  }
  if (trace) std::fprintf(stderr, "[vr-ctrl] level mode=%d ang=%.1f,%.1f trig=%.2f/%.2f pulse=%d\n", mode, yaw, pitch, R.trigger, L.trigger, pulse);
  return true;
}
void PublishSkeleton(u8* base) {
  static u32 calls = 0, number = 100;
  float rh[3] = {0.30f, 0.35f, 1.75f}, lh[3] = {-0.30f, -0.15f, 2.15f};
  if (HandsFromControllers(rh, lh)) {
    // done: the hands come from the controllers
  } else if (Skel().hands) {
    if (FILE* a = std::fopen(Skel().hands, "r")) {
      char line[160] = {0};
      if (std::fgets(line, sizeof line, a)) {
        float v[6];
        float yaw, pitch;
        int shots = 0, mode = 0;
        if (line[0] == 'a' && std::sscanf(line + 1, "%f %f %d %d", &yaw, &pitch, &shots, &mode) >= 2) {
          // Stage 3: "VR controller" input: aim angle in degrees (right and up positive), trigger
          // counter and mode (0 = right hand, lock-on laser; 1 = left hand, rapid fire; 2 = both hands up,
          // Euphoria). It is translated to the hand the game expects with the law measured in run 240:
          //   angle = 133.33 °/m · (hand − reference), reference = (±0.135, 0.2383) for this skeleton.
          // Each time the counter changes, the hand advances 20 cm towards the sensor for 5 skeleton frames
          // (the game fires when the hand advances ≥ 11 cm in 120 ms; run 241).
          static int seen = 0, pulse = 0;
          if (shots != seen) {
            seen = shots;
            pulse = 10;  // Update calls (60/s) = 5 skeleton frames
          }
          const float z = (pulse > 0) ? 1.55f : 1.75f;
          if (pulse > 0) --pulse;
          const float kDegrees = 133.33f, kRefX = 0.135f, kRefY = 0.2383f;
          if (mode == 2) {
            rh[0] = 0.3f, rh[1] = 0.9f, rh[2] = 2.0f;
            lh[0] = -0.3f, lh[1] = 0.9f, lh[2] = 2.0f;
          } else if (mode == 1) {
            rh[0] = 0.3f, rh[1] = -0.15f, rh[2] = 2.15f;
            lh[0] = -kRefX + yaw / kDegrees, lh[1] = kRefY + pitch / kDegrees, lh[2] = z;
          } else {
            rh[0] = kRefX + yaw / kDegrees, rh[1] = kRefY + pitch / kDegrees, rh[2] = z;
          }
        } else if (std::sscanf(line, "%f %f %f %f %f %f", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) == 6) {
          std::memcpy(rh, v, sizeof rh);
          std::memcpy(lh, v + 3, sizeof lh);
        }
      }
      std::fclose(a);
    }
  }
  std::memcpy(g_rh, rh, sizeof rh);
  std::memcpy(g_lh, lh, sizeof lh);
  WriteU32(base, kNatalState, 1);
  *reinterpret_cast<u8*>(REX_RAW_ADDR(kSkelNoPlayer)) = 0;  // Update copies it to obj+9832 ("No player detected")
  if ((calls++ & 1) != 0) return;  // 30 skeleton frames per second, like the sensor
  ++number;
  u32 i;
  std::memcpy(&i, REX_RAW_ADDR(kSkelIndex), 4);
  i = __builtin_bswap32(i) & 1;
  u8 f[2736];
  BuildSkeleton(f, number, rh, lh);
  std::memcpy(REX_RAW_ADDR(kSkelRefined + i * 2736), f, 2736);
  std::memcpy(REX_RAW_ADDR(kSkelRaw + i * 2736), f, 2736);
  *reinterpret_cast<u8*>(REX_RAW_ADDR(kSkelArrived)) = 1;
  WriteU32(base, kSkelFrame, number);
  if (number == 101) std::fprintf(stderr, "[vr] synthetic skeleton active (hands=%s)\n", Skel().hands ? Skel().hands : "fixed");
}
}  // namespace

REX_HOOK_RAW(sub_82D546A8) {
  const u32 obj = ctx.r3.u32;
  if (const int n = NatalActive()) {
    WriteU32(base, kNatalState, static_cast<u32>(n));
    static bool said = false;
    if (!said) {
      said = true;
      std::fprintf(stderr, "[vr] NatalActive=%d obj=%08X obj+96=%u\n", n, obj, *reinterpret_cast<u8*>(REX_RAW_ADDR(obj + 96)));
    }
  }
  if (Skel().active) PublishSkeleton(base);
  __imp__sub_82D546A8(ctx, base);
  // EDEN_VR_NATALDIAG=1: every 120 calls dumps the CNatal fields that decide "there is a player".
  static const bool diag = [] { const char* e = std::getenv("EDEN_VR_NATALDIAG"); return e && *e == '1'; }();
  static u32 n = 0;
  if (diag && (n++ % 120) == 0) {
    auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(obj + d), 4); return __builtin_bswap32(v); };
    auto B = [&](u32 d) { return static_cast<u32>(*reinterpret_cast<u8*>(REX_RAW_ADDR(obj + d))); };
    std::fprintf(stderr,
                 "[vr-diag] n=%u hist=%08X no_frame=%u new=%u state=%u sel=%u/%u b9832=%u notices=%03X idx=%u frame=%u "
                 "skel0=%u id=%u ident=%u/%u\n",
                 n, L(104), L(432), B(436), L(440), B(9816), L(9820), B(9832), L(10348), L(10268), L(10272), L(576 + 48),
                 L(576 + 52), L(9924), L(9928));
  }
}

// Player identification: sub_82D4EFD8(obj, &user, enrollment_index) asks the NUI library which
// profile matches the skeleton. With the synthetic skeleton we answer "it is user 0" without touching the library.
REX_HOOK_RAW(sub_82D4EFD8) {
  if (!Skel().active) {
    __imp__sub_82D4EFD8(ctx, base);
    return;
  }
  WriteU32(base, ctx.r4.u32, 0);
  ctx.r3.u64 = 1;
}

// The title's sign-in state machine (sub_82D70488): with EDEN_VR_NATALDIAG=1 logs every state change.
REX_HOOK_RAW(sub_82D70488) {
  static const bool diag = [] { const char* e = std::getenv("EDEN_VR_NATALDIAG"); return e && *e == '1'; }();
  const u32 obj = ctx.r3.u32;
  __imp__sub_82D70488(ctx, base);
  if (!diag) return;
  auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(obj + d), 4); return __builtin_bswap32(v); };
  auto B = [&](u32 d) { return static_cast<u32>(*reinterpret_cast<u8*>(REX_RAW_ADDR(obj + d))); };
  static u32 before[3] = {~0u, ~0u, ~0u};
  const u32 now[3] = {L(16), L(76), B(88)};
  if (std::memcmp(before, now, sizeof before) != 0) {
    std::memcpy(before, now, sizeof before);
    std::fprintf(stderr, "[vr-session] frame=%u state=%u sub=%u kinect=%u user=%d/%d end=%u b20-22=%u%u%u\n",
                 g_frame.load(), now[0], now[1], now[2], static_cast<int>(L(80)), static_cast<int>(L(84)), L(100),
                 B(20), B(21), B(22));
  }
}

// Storage selector: on the Kinect path the game calls XamShowNuiDeviceSelectorUI (sub_82E7AB78), which
// the runtime does not implement (stub); the game takes it as "no storage" and starts without a save.
// Its arguments are those of XamShowDeviceSelectorUI (sub_82E7AF08) preceded by the tracking id: it is redirected.
REX_HOOK_RAW(sub_82E7AB78) {
  if (!Skel().active) {
    __imp__sub_82E7AB78(ctx, base);
    return;
  }
  ctx.r3.u64 = ctx.r4.u64;
  ctx.r4.u64 = ctx.r5.u64;
  ctx.r5.u64 = ctx.r6.u64;
  ctx.r6.u64 = ctx.r7.u64;
  ctx.r7.u64 = ctx.r8.u64;
  ctx.r8.u64 = ctx.r9.u64;
  sub_82E7AF08(ctx, base);
  std::fprintf(stderr, "[vr] XamShowNuiDeviceSelectorUI redirected -> %08X\n", ctx.r3.u32);
}

// --- Stage 2, part B: where each frame comes from ------------------------------------------------------------------
//   EDEN_VR_STACK=<frame>   on reaching that frame prints the call chain (lr values saved on the game's stack)
//                           at the end of frame (sub_82E658D0) and at the scene camera (sub_829EDDF8).
namespace {
u32 StackFrame() {
  static u32 v = [] {
    const char* e = std::getenv("EDEN_VR_STACK");
    return (e && *e) ? static_cast<u32>(std::atoi(e)) : 0u;
  }();
  return v;
}
void DumpStack(const char* where, PPCContext& ctx, u8* base) {
  std::fprintf(stderr, "[vr-stack] %s frame=%u lr=%08X:", where, g_frame.load(), static_cast<u32>(ctx.lr));
  u32 sp = ctx.r1.u32;
  for (int i = 0; i < 24 && sp >= 0x10000; ++i) {
    u32 prev, lr;
    std::memcpy(&prev, REX_RAW_ADDR(sp), 4);
    prev = __builtin_bswap32(prev);
    if (prev <= sp || prev - sp > 0x100000) break;
    std::memcpy(&lr, REX_RAW_ADDR(prev - 8), 4);
    lr = __builtin_bswap32(lr);
    std::fprintf(stderr, " %08X", lr);
    sp = prev;
  }
  std::fprintf(stderr, "\n");
}
}  // namespace

REX_HOOK_RAW(sub_829EDDF8) {
  static bool done = false;
  if (StackFrame() && !done && g_frame.load() >= StackFrame()) {
    done = true;
    DumpStack("camera", ctx, base);
  }
  __imp__sub_829EDDF8(ctx, base);
}

// --- Crash of 2026-11-20 on the handheld: XMA voice with a null context ----------------------------------------------
// sub_82E84FE8(player) copies the pending state of each stream (96-byte entry; "dirty" flags at
// +48/+52/+56) to its XMA context (pointer at +64). If the context does not exist (XMACreateContext failed or it was
// already released) the game writes to address 0 and the process dies. Here, with the same critical section the function
// uses (0x83345AC0), the pending writes of the streams without a context are discarded and a note is left in the log.
// It does not depend on environment variables: it is a fix, not a test.
REX_HOOK_RAW(sub_82E84FE8) {
  const u32 obj = ctx.r3.u32;
  auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(d), 4); return __builtin_bswap32(v); };
  if (obj) {
    const u64 r3 = ctx.r3.u64;
    ctx.r3.u64 = 0x83345AC0;
    __imp__RtlEnterCriticalSection(ctx, base);  // RtlEnterCriticalSection (recursive)
    const u32 n = L(obj), arr = L(obj + 8);
    for (u32 i = 0; arr && i < n && i < 64; ++i) {
      const u32 e = arr + 96 * i;
      if (L(e + 64) != 0) continue;
      if (L(e + 48) | L(e + 52) | L(e + 56)) {
        static std::atomic<u32> warnings{0};
        if (warnings.fetch_add(1) < 40)
          std::fprintf(stderr, "[eden] XMA: stream %u of player %08X has no context (flags %08X, state %08X); "
                               "skipping the write that used to crash the game\n", i, obj, L(e), L(obj + 4));
        std::memset(REX_RAW_ADDR(e + 48), 0, 12);
      }
    }
    ctx.r3.u64 = r3;
    __imp__sub_82E84FE8(ctx, base);
    const u64 r3b = ctx.r3.u64;
    ctx.r3.u64 = 0x83345AC0;
    __imp__RtlLeaveCriticalSection(ctx, base);  // RtlLeaveCriticalSection
    ctx.r3.u64 = r3b;
    return;
  }
  __imp__sub_82E84FE8(ctx, base);
}

// The other half: sub_82E84760 releases a player's contexts (XMAReleaseContext and pointer to 0) WITHOUT taking the
// critical section that sub_82E84FE8 does take. On the console the two threads almost never run at once; here they do.
// With the same lock, releasing and writing can no longer cross. (Measured: exhausting the contexts does not crash the game,
// run 302 with EDEN_XMA_MAX=12; that is why the cause of the crash is this crossing and not the exhaustion.)
// Third crash of the family (run 425, 2026-11-20): sub_82E84E78 also reads the null context, and before it were
// sub_82E84FE8 (writes) and sub_82E84820 (reads). Instead of patching each function, a voice without a context points to a
// "phantom context": 64 zeroed bytes of game memory that nobody decodes. Reading it gives zeros and writing it does nothing.
// The pointer is only 0 inside sub_82E84760 and sub_82E84650, which are the ones that distinguish "no context".
namespace {
std::atomic<u32> g_xma_phantom{0};
template <class C>
u32 XmaPhantom(C& ctx, u8* base) {  // call with the critical section 0x83345AC0 held
  u32 f = g_xma_phantom.load();
  if (f) return f;
  const u64 r3 = ctx.r3.u64, lr = ctx.lr;
  ctx.r3.u64 = 64;
  __imp__sub_82FB7CF8(ctx, base);  // the game's operator new
  f = ctx.r3.u32;
  ctx.r3.u64 = r3;
  ctx.lr = lr;
  if (f) {
    std::memset(REX_RAW_ADDR(f), 0, 64);
    g_xma_phantom.store(f);
    std::fprintf(stderr, "[eden] XMA: phantom context at %08X\n", f);
  }
  return f;
}
// to_phantom: the null pointers become the phantom; otherwise the phantom ones go back to 0. Returns how many it changed.
template <class C>
u32 XmaSwap(C& ctx, u8* base, u32 obj, bool to_phantom) {
  auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(d), 4); return __builtin_bswap32(v); };
  const u32 f = XmaPhantom(ctx, base);
  if (!obj || !f) return 0;
  const u32 n = L(obj), arr = L(obj + 8);
  u32 c = 0;
  for (u32 i = 0; arr && i < n && i < 64; ++i) {
    const u32 d = arr + 96 * i + 64, v = L(d);
    if (v != (to_phantom ? 0u : f)) continue;
    const u32 w = to_phantom ? __builtin_bswap32(f) : 0u;
    std::memcpy(REX_RAW_ADDR(d), &w, 4);
    ++c;
  }
  return c;
}
template <class C, class F>
void XmaWithLock(C& ctx, u8* base, F&& original) {
  const u32 obj = ctx.r3.u32;
  const u64 r3 = ctx.r3.u64;
  ctx.r3.u64 = 0x83345AC0;
  __imp__RtlEnterCriticalSection(ctx, base);
  XmaSwap(ctx, base, obj, false);  // phantom -> 0: the original sees the truth
  ctx.r3.u64 = r3;
  original();
  const u64 r3b = ctx.r3.u64;
  const u32 c = XmaSwap(ctx, base, obj, true);  // 0 -> phantom
  static std::atomic<u32> warnings{0};
  if (c && warnings.fetch_add(1) < 20)
    std::fprintf(stderr, "[eden] XMA: player %08X is left with %u voice(s) without a context; they point to the phantom\n", obj, c);
  ctx.r3.u64 = 0x83345AC0;
  __imp__RtlLeaveCriticalSection(ctx, base);
  ctx.r3.u64 = r3b;
}
}  // namespace

REX_HOOK_RAW(sub_82E84760) {  // releases the player's contexts
  XmaWithLock(ctx, base, [&] { __imp__sub_82E84760(ctx, base); });
}
REX_HOOK_RAW(sub_82E84650) {  // creates the missing contexts (XMACreateContext); on failure leaves 0
  XmaWithLock(ctx, base, [&] { __imp__sub_82E84650(ctx, base); });
}

// --- Stage 3: reticle and gesture shot ------------------------------------------------------------------------------
//   EDEN_VR_TRACE=1   (a) revives the game's own debug trace: sub_829B1FF0 is a "printf" emptied in the
//                     retail build (just `blr`); here the format and its first two arguments are printed for the
//                     messages of the Kinect cursor class (formats at 0x823A4000..0x823A6000);
//                     (b) logs the final position of the reticle (sub_82D476F0) together with the published hands;
//                     (c) logs every change in the result of the shot detector (sub_82D47A10).
namespace {
bool Trace() {
  static const bool v = [] { const char* e = std::getenv("EDEN_VR_TRACE"); return e && *e == '1'; }();
  return v;
}
u32 TraceEvery() {
  static const u32 v = [] { const char* e = std::getenv("EDEN_VR_TRACE_EVERY"); return (e && *e) ? std::max(1, std::atoi(e)) : 30; }();
  return static_cast<u32>(v);
}
}  // namespace

REX_HOOK_RAW(sub_829B1FF0) {
  if (!Trace()) return;
  const u32 f = ctx.r4.u32;
  if (f < 0x823A4000 || f >= 0x823A6000) return;
  static std::mutex m;
  static std::map<u32, u32> counts;
  std::lock_guard<std::mutex> lk(m);
  const u32 k = counts[f]++;
  if (k >= 3 && (k % TraceEvery()) != 0) return;
  char fmt[48];
  std::snprintf(fmt, sizeof fmt, "%s", reinterpret_cast<const char*>(REX_RAW_ADDR(f)));
  for (char* c = fmt; *c; ++c)
    if (*c == '\n') *c = ' ';
  double a, b;
  std::memcpy(&a, &ctx.r5.u64, 8);
  std::memcpy(&b, &ctx.r6.u64, 8);
  std::fprintf(stderr, "[vr-trace] frame=%u #%u '%s' r5=%d/%g r6=%d/%g f1=%g f2=%g lr=%08X\n", g_frame.load(), k, fmt,
               static_cast<int>(ctx.r5.u32), a, static_cast<int>(ctx.r6.u32), b, ctx.f1.f64, ctx.f2.f64,
               static_cast<u32>(ctx.lr));
}

// Stage 4: the reticle is 2D. It is drawn by sub_82D1A488 (method 5 of the sight object, virtual table 0x8237F560) at
// the screen position obj+696/700 (or +712/716), computed for the game's original camera (45° vertical, 16:9).
// When the frame is drawn with the headset view, that point no longer lands on what is being aimed at: here the
// pixel is converted to a direction (with the original projection), rotated with the head and projected again with the eye's.
// It is only changed during the draw; on exit it is restored, so as not to touch the game logic.
REX_HOOK_RAW(sub_82D1A488) {
  const u32 obj = ctx.r3.u32;
  VrOptions& o = Opt();
  if (!o.head || !obj) {
    __imp__sub_82D1A488(ctx, base);
    return;
  }
  const u32 frame = g_frame.load(std::memory_order_relaxed);
  const int eye_i = static_cast<int>((frame / o.period) & 1);
  VrFrame& c = FrameVr(frame, eye_i);
  if (!c.proj) {
    __imp__sub_82D1A488(ctx, base);
    return;
  }
  u8* m = reinterpret_cast<u8*>(REX_RAW_ADDR(obj + 696));  // 6 floats: 696..716
  u8 saved[24];
  std::memcpy(saved, m, 24);
  const RexVrView& v = c.st.eye[eye_i];
  float Rm[3][3];
  Rotation(v.quat, Rm);
  const float tl = std::tan(v.fov[0]), tr = std::tan(v.fov[1]), tu = std::tan(v.fov[2]), td = std::tan(v.fov[3]);
  const float ty0 = 0.41421356f, tx0 = ty0 * 16.0f / 9.0f;
  for (int pair : {0, 4}) {  // (696,700) and (712,716)
    const float px = ReadF(m, pair), py = ReadF(m, pair + 1);
    const float d[3] = {(px - 640.0f) / 640.0f * tx0, (360.0f - py) / 360.0f * ty0, -1.0f};
    float e[3];
    for (int j = 0; j < 3; ++j) e[j] = d[0] * Rm[0][j] + d[1] * Rm[1][j] + d[2] * Rm[2][j];
    float nx = 9.0f, ny = 9.0f;  // off screen if it ends up behind
    if (e[2] < -1e-3f) {
      nx = (2.0f * (e[0] / -e[2]) - (tr + tl)) / (tr - tl);
      ny = (2.0f * (e[1] / -e[2]) - (tu + td)) / (tu - td);
    }
    WriteF(m, pair, 640.0f + nx * 640.0f);
    WriteF(m, pair + 1, 360.0f - ny * 360.0f);
  }
  __imp__sub_82D1A488(ctx, base);
  std::memcpy(m, saved, 24);
}

REX_HOOK_RAW(sub_82D476F0) {
  if (Trace()) {
    static u32 n = 0;
    if ((n++ % TraceEvery()) == 0)
      std::fprintf(stderr, "[vr-sight] frame=%u x=%.2f y=%.2f r6=%u lr=%08X hands=%.3f,%.3f,%.3f|%.3f,%.3f,%.3f\n",
                   g_frame.load(), ctx.f1.f64, ctx.f2.f64, ctx.r6.u32, static_cast<u32>(ctx.lr), g_rh[0], g_rh[1],
                   g_rh[2], g_lh[0], g_lh[1], g_lh[2]);
  }
  __imp__sub_82D476F0(ctx, base);
}

REX_HOOK_RAW(sub_82D47A10) {
  const u32 obj = ctx.r3.u32, a4 = ctx.r4.u32, a5 = ctx.r5.u32;
  __imp__sub_82D47A10(ctx, base);
  if (!Trace()) return;
  auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(obj + d), 4); return __builtin_bswap32(v); };
  static u32 before[4] = {~0u, ~0u, ~0u, ~0u};
  const u32 now[4] = {ctx.r3.u32, L(2372), L(2376), L(488)};
  if (std::memcmp(before, now, sizeof before) != 0) {
    std::memcpy(before, now, sizeof before);
    std::fprintf(stderr, "[vr-shot] frame=%u res=%u b2372=%u joint=%u e488=%u args=%u,%u hands=%.3f,%.3f,%.3f|%.3f,%.3f,%.3f\n",
                 g_frame.load(), now[0], now[1], now[2], now[3], a4 & 255, a5 & 255, g_rh[0], g_rh[1], g_rh[2],
                 g_lh[0], g_lh[1], g_lh[2]);
  }
}

// sub_82D475A8(obj, r4): called by the paths that take a shot for granted (or cancel it). With the trace on, each
// call is logged (the first 400) to count shots without depending on the image.
REX_HOOK_RAW(sub_82D475A8) {
  if (Trace()) {
    static u32 n = 0;
    if (n++ < 400)
      std::fprintf(stderr, "[vr-trigger] frame=%u #%u r4=%u lr=%08X hands=%.3f,%.3f,%.3f|%.3f,%.3f,%.3f\n", g_frame.load(), n,
                   ctx.r4.u32 & 255, static_cast<u32>(ctx.lr), g_rh[0], g_rh[1], g_rh[2], g_lh[0], g_lh[1], g_lh[2]);
  }
  __imp__sub_82D475A8(ctx, base);
}

// ---------------------------------------------------------------------------------------------------------------------
// Debug cheats. Off without their environment variable.
//   EDEN_INVINCIBLE=1   before each hit restores health to the maximum: the hit is processed in full (reaction, damage
//                       message, invulnerability window, HUD) but health never reaches 0.
//   EDEN_INVINCIBLE=2   does not even process the hit (does not call the original): no reaction and no blinking.
//
// What was measured in the PPC listing (static analysis, without running):
//   - Player class: vtable 0x823776A8, ctor sub_82D02E30, size 2512 (single factory sub_82D0A938).
//   - Health: signed 32-bit integer at obj+1332, from 0 to 10000; one petal = 2000 (sub_82D03AC0 converts it to
//     0..5). Initial value 6000 = 3 petals (sub_82D09418 @ `li r11,6000; stw r11,1332(r31)` and sub_82D05BE0).
//   - sub_82D07F00 (vtable slot 38, vt+152) is the ONLY function of the class that subtracts health:
//       lwz r10,1332(r29); mulli r11,r11,2000; subf. r11,r11,r10; (clamped at 0); stw r11,1332(r29)
//     with r11 = 0, 1 or 2 petals depending on a configuration byte (0 -> 0, 2 -> 2, other -> 1).
//   - Death is decided in the updates sub_82D05FC8 / sub_82D06E70:
//       lwz r11,1332(r31); cmpwi r11,0; bne ...; lwz r11,1344(r31); cmpwi r11,0; beq ...; vt[20]()  -> sub_82D05DE8
//     which sends message 5; CCheckPlayerMission (sub_82D5AF70/sub_82D5AFD0) drops its counter to 0 and sends
//     message 18; sub_82D89E98 sets bit 0 of stage+3548 and sub_82D8A8D8 creates CGameOverMenuTask (sub_82935538).
//   Since the hit subtracts at most 4000 (2 petals), with health at 10000 before the hit it never reaches 0.

namespace {
constexpr u32 kPlayerHealth = 1332;    // s32, 0..10000 (2000 per petal)
constexpr u32 kPlayerHealthMax = 10000;

int Invincible() {
  static const int v = [] {
    const char* e = std::getenv("EDEN_INVINCIBLE");
    return (e && *e) ? std::atoi(e) : 0;
  }();
  return v;
}
}  // namespace

// Player::Damage (sub_82D07F00, r3 = player). No return value the caller cares about (virtual call vt+152).
REX_HOOK_RAW(sub_82D07F00) {
  const int mode = Invincible();
  const u32 obj = ctx.r3.u32;
  if (mode == 0 || !obj) {
    __imp__sub_82D07F00(ctx, base);
    return;
  }
  static u32 n = 0;
  if (n++ < 20 || n % 200 == 0)
    std::fprintf(stderr, "[health] hit %u on player=%08X health=%u (invincible=%d)\n", n, obj,
                 REX_LOAD_U32(obj + kPlayerHealth), mode);
  if (mode >= 2) return;  // hit ignored completely
  // Restore BEFORE the original: that way health never passes through 0 and the HUD never gets to see "0 petals".
  u32 v = __builtin_bswap32(kPlayerHealthMax);
  std::memcpy(REX_RAW_ADDR(obj + kPlayerHealth), &v, 4);
  __imp__sub_82D07F00(ctx, base);
}

//   EDEN_AUTOAIM=1      every frame moves the reticle to the LOCKABLE target closest to where the reticle already is.
//   EDEN_AUTOAIM=2      same, but also counts the targets with flag 0x08 (not lockable; [inferred] the rapid-fire ones).
//   Without the variable the hook just calls the original.
//
// What was measured in the PPC listing (static analysis, without running):
//   - Main::Player::Sight (vtable 0x8237F560). Its update (slot 4, sub_82D1D9D8) calls sub_82D1B5A8 once
//     (bl @0x82D1DCBC, single caller), which is the lock-on routine.
//   - sub_82D1B5A8 first sets the frame's reticle position at sight+696/700 (controller: copies sight+1460/1464;
//     Kinect: projects the matrix sight+1216) and right after calls sub_82D19760(sight, &ray, &W/2, &H/2, sight+696,
//     sight+700) (bl @0x82D1B830, single caller; lr = 0x82D1B834) to convert that pixel into a ray. EVERYTHING after that
//     (ray, "reticle on top", lock-on) reads sight+696/700 through a pointer (r19/r18). That is why the hook goes HERE:
//     writing sight+696/700 earlier gets overwritten, and writing later leaves the old ray.
//   - Targets: manager = *(sight+1488) (vtable 0x82376408); its slot 9 is sub_82AD9C90 = `addi r3,r3,264; blr`:
//     std::vector<Target*> with begin at manager+264 and end at manager+268 (4 bytes per element).
//   - Target: +4 health (s32), +8 flags (0x08 = not lockable), +12 current locks (s16), +14 maximum locks (s16),
//     +20 state (0 dead/inactive, 1 lockable, 2 locked to the maximum), +32 world position (4 floats), +56 radius.
//   - Projection (sub_8297C840): clip = (x,y,z,1) · (A·B), with A = cam+144 and B = cam+224 (row vectors);
//     X = (clip.x/clip.w + 1)·W/2, Y = (1 − clip.y/clip.w)·H/2; returns clip.z (> 0 = in front). Same units as
//     sight+696/700 (1280x720 pixels). cam = sub_82D262C0(*0x83377210), replicated below on the host.
//   - The game's lock-on test (0x82D1C530..0x82D1C6B4): state == 1, flags & 8 == 0, z > 0, X > 0, Y > 0, the box
//     [X±r, Y±r] touches the screen and touches the reticle box [mx±s, my±s] (s = sight+688, r = projected radius), and
//     sub_82CFBC10 accepts (locks < maximum and locks·damage < health). At most one lock per pass.
//
// Not verified at run time: that the manager's vtable is always 0x82376408 (that is why it is checked and reported), and
// that in controller mode nothing else depends on the player's own cursor.

namespace {
constexpr u32 kVtSight = 0x8237F560;
constexpr u32 kVtTargetManager = 0x82376408;
constexpr u32 kPtrCameras = 0x83377210;  // sub_8297C840: lis r11,-31945; lwz r3,29200(r11); bl sub_82D262C0

int AutoAim() {
  static const int v = [] {
    const char* e = std::getenv("EDEN_AUTOAIM");
    return (e && *e) ? std::atoi(e) : 0;
  }();
  return v;
}

float AimF(u8* base, u32 addr) {  // big-endian float from game memory
  u32 v;
  std::memcpy(&v, REX_RAW_ADDR(addr), 4);
  v = __builtin_bswap32(v);
  float f;
  std::memcpy(&f, &v, 4);
  return f;
}
void AimWriteF(u8* base, u32 addr, float f) {
  u32 v;
  std::memcpy(&v, &f, 4);
  v = __builtin_bswap32(v);
  std::memcpy(REX_RAW_ADDR(addr), &v, 4);
}
u32 AimU32(u8* base, u32 addr) {
  u32 v;
  std::memcpy(&v, REX_RAW_ADDR(addr), 4);
  return __builtin_bswap32(v);
}
bool AimAddrValid(u32 d) { return d >= 0x10000 && (d & 3) == 0; }

// sub_82D262C0 + sub_82D26150: active camera node; the camera data is at node+80.
u32 AimCamera(u8* base) {
  const u32 g = AimU32(base, kPtrCameras);
  if (!AimAddrValid(g)) return 0;
  u32 n = AimU32(base, g + 8);
  if (!AimAddrValid(n)) return 0;
  u32 next = AimU32(base, n + 384);
  if (next && *REX_RAW_ADDR(n + 32) == 0) {
    n = next;
    next = AimU32(base, n + 384);
    for (int i = 0; next && i < 64; ++i) {
      if (*REX_RAW_ADDR(n + 32) != 0) break;
      n = next;
      next = AimU32(base, n + 384);
    }
  }
  return n + 80;
}
}  // namespace

// The player's real cursor in controller mode. The sight update (sub_82D1D9D8) obtains it like this and copies it every frame to
// sight+1460/1464: manager = sub_829202B0(); a = manager->slot7(); dev = a->slot8(0); p = dev->slot19();
// x = *(p+4), y = *(p+8). Writing only sight+1460 does not work: it is overwritten on the next frame (run 478).
// Returns the address of p (0 if something does not match). Preserves the caller's context.
static u32 AimRealCursor(PPCContext& ctx, u8* base) {
  const PPCContext saved = ctx;
  u32 p = 0;
  auto virt = [&](u32 obj, u32 slot_bytes) -> bool {
    if (!AimAddrValid(obj)) return false;
    const u32 vt = AimU32(base, obj);
    if (!AimAddrValid(vt)) return false;
    const u32 f = AimU32(base, vt + slot_bytes);
    if (f < 0x82000000u || f >= 0x84000000u) return false;
    ctx.r3.u64 = obj;
    ctx.ctr.u64 = f;
    REX_CALL_INDIRECT_FUNC(ctx.ctr.u32);
    return true;
  };
  sub_829202B0(ctx, base);
  if (virt(ctx.r3.u32, 28)) {
    const u32 a = ctx.r3.u32;
    ctx.r4.u64 = 0;
    if (virt(a, 32) && virt(ctx.r3.u32, 76) && AimAddrValid(ctx.r3.u32)) p = ctx.r3.u32;
  }
  ctx = saved;
  return p;
}

// --- Video that stays black and never ends (Journey, area 5; runs 484 to 495). SOLVED in run 502 by the
// hook on sub_8292A118 (further down); what follows is the trace that led to the cause (EDEN_VIDEO_TRACE=1) ---
// The game's WMV player has three threads per video (sub_82EE3A10, sub_82EE3CF0, sub_82EE53B8) that suspend
// themselves (sub_82E7A278) when they have no work; the routine that requests frames (sub_82EE47E0) resumes them
// (sub_82E7A138, lr 82EE49F4 and 82EE49FC) and waits for samples. Measured (runs 492 and 495): in a NEW player of a
// 256x256 video of area 5 (with jny_a5_af_bty.wmv and jny_a5_event.wmv open), the sub_82EE3CF0 thread suspends
// in the same millisecond in which it is resumed (lr 82EE3FBC) with obj+224 = obj+228 = 2 (in the working ones they are 0 and
// it suspends ~10 s later, on finishing), and sub_82EE47E0 never returns: black image with the game alive (pause
// responds). Two fixes tried and discarded: treating the resume as pending (run 490, it never triggered)
// and delaying the just-resumed thread until startup finishes (runs 494 and 495, the black screen remained).
// The trace remains: EDEN_VIDEO_TRACE=1 logs every suspend/resume with the player's state.
namespace {
std::mutex g_vid_mx;
std::map<u32, int> g_vid_inside;  // player -> calls to sub_82EE47E0 in progress
bool VidTrace() {  // EDEN_VIDEO_TRACE=1: logs every suspend/resume of the player and every video start
  static const bool v = [] { const char* e = std::getenv("EDEN_VIDEO_TRACE"); return e && *e == '1'; }();
  return v;
}
long long VidMs() {
  static const auto t0 = std::chrono::steady_clock::now();
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
}
bool VidInside(u32 obj) {
  std::lock_guard lock(g_vid_mx);
  auto it = g_vid_inside.find(obj);
  return it != g_vid_inside.end() && it->second > 0;
}
}  // namespace

// sub_82EE47E0(r3 = player, r4, r5): requests the next frame; on the first call it starts playback.
REX_HOOK_RAW(sub_82EE47E0) {
  const u32 obj = ctx.r3.u32;
  const long long t0 = VidMs();
  {
    std::lock_guard lock(g_vid_mx);
    if (g_vid_inside.size() > 512) g_vid_inside.clear();
    ++g_vid_inside[obj];
  }
  __imp__sub_82EE47E0(ctx, base);
  {
    std::lock_guard lock(g_vid_mx);
    auto it = g_vid_inside.find(obj);
    if (it != g_vid_inside.end() && --it->second <= 0) g_vid_inside.erase(it);
  }
  if (VidTrace() && VidMs() - t0 > 100)
    std::fprintf(stderr, "[eden] vtrace %lld ms: 47E0 obj=%08X took %lld ms\n", VidMs(), obj, VidMs() - t0);
}

// sub_82E7A278(r3 = handle): SuspendThread. It only acts when one of the player's three threads is the caller.
REX_HOOK_RAW(sub_82E7A278) {
  const u32 lr = static_cast<u32>(ctx.lr), handle = ctx.r3.u32, obj = ctx.r30.u32;
  const bool is_player = lr >= 0x82EE3A10u && lr < 0x82EE5C00u;
  if (VidTrace() && is_player)
    std::fprintf(stderr, "[eden] vtrace %lld ms: SUSPEND handle=%08X lr=%08X obj=%08X\n", VidMs(), handle, lr, obj);
  if (VidTrace() && is_player && AimAddrValid(obj)) {
    std::fprintf(stderr, "[eden] vtrace    state obj=%08X:", obj);
    for (u32 d = 224; d <= 280; d += 4) std::fprintf(stderr, " +%u=%08X", d, AimU32(base, obj + d));
    std::fprintf(stderr, "\n");
  }
  __imp__sub_82E7A278(ctx, base);
}

// sub_82E7A138(r3 = handle): ResumeThread; returns the previous suspend count (or -1).
REX_HOOK_RAW(sub_82E7A138) {
  const u32 handle = ctx.r3.u32, lr = static_cast<u32>(ctx.lr), obj = ctx.r25.u32;
  __imp__sub_82E7A138(ctx, base);
  if (VidTrace() && lr >= 0x82EE3000u && lr < 0x82EE6000u)
    std::fprintf(stderr, "[eden] vtrace %lld ms: RESUME handle=%08X lr=%08X obj=%08X prev_count=%d\n", VidMs(), handle, lr,
                 obj, static_cast<int>(ctx.r3.u32));
}

// Left stick requested by the auto-aim. Measured in run 481: the camera moves with the cursor only when
// the stick moves it (the device recomputes the cursor every frame from the stick, with return to center), so
// writing the cursor does not turn the view (runs 478 to 480). The XamInputGetState wrapper (sub_8316E210) replaces
// user 0's stick while the request is fresh.
static std::atomic<int> g_aim_lx{0}, g_aim_ly{0};
static std::atomic<long long> g_aim_ms{0};
static long long AimNowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
static void AimRequestStick(float x, float y) {  // x right, y DOWN (screen), in -1..1
  x = std::min(1.0f, std::max(-1.0f, x));
  y = std::min(1.0f, std::max(-1.0f, y));
  g_aim_lx.store(static_cast<int>(x * 32767.0f));
  g_aim_ly.store(static_cast<int>(-y * 32767.0f));
  g_aim_ms.store(AimNowMs());
}

// sub_8316E210(r3 = user, r4 = XINPUT_STATE*): `mr r5,r4; li r4,1; b XamInputGetState`.
REX_HOOK_RAW(sub_8316E210) {
  const u32 user = ctx.r3.u32, state = ctx.r4.u32;
  __imp__sub_8316E210(ctx, base);
  if (AutoAim() == 0 || user != 0 || ctx.r3.u32 != 0 || !AimAddrValid(state)) return;
  if (AimNowMs() - g_aim_ms.load() > 150) return;  // stale request: the controller rules
  static std::atomic<u32> packet{0x40000000};
  const u32 pk = __builtin_bswap32(packet.fetch_add(1));
  std::memcpy(REX_RAW_ADDR(state), &pk, 4);  // different dwPacketNumber: so the game does not discard the state
  const u16 lx = __builtin_bswap16(static_cast<u16>(static_cast<int16_t>(g_aim_lx.load())));
  const u16 ly = __builtin_bswap16(static_cast<u16>(static_cast<int16_t>(g_aim_ly.load())));
  std::memcpy(REX_RAW_ADDR(state + 8), &lx, 2);   // Gamepad.sThumbLX
  std::memcpy(REX_RAW_ADDR(state + 10), &ly, 2);  // Gamepad.sThumbLY
}

// sub_82D19760(r3 = sight, r4 = &ray, r5 = &W/2, r6 = &H/2, r7 = sight+696, r8 = sight+700).
REX_HOOK_RAW(sub_82D19760) {
  const int mode = AutoAim();
  const u32 sight = ctx.r3.u32;
  if (mode == 0 || static_cast<u32>(ctx.lr) != 0x82D1B834 || !sight || AimU32(base, sight) != kVtSight) {
    __imp__sub_82D19760(ctx, base);
    return;
  }
  static u32 calls = 0;
  ++calls;
  const bool trace = calls <= 30 || calls % 300 == 0;

  const u32 manager = AimU32(base, sight + 1488);
  if (!AimAddrValid(manager) || AimU32(base, manager) != kVtTargetManager) {
    static bool warned = false;
    if (!warned) {
      warned = true;
      std::fprintf(stderr,
                   "[eden] autoaim: the target manager (sight+1488=%08X) does not have the expected vtable %08X (it has "
                   "%08X); the reticle is left untouched.\n",
                   manager, kVtTargetManager, AimAddrValid(manager) ? AimU32(base, manager) : 0);
    }
    __imp__sub_82D19760(ctx, base);
    return;
  }
  const u32 cam = AimCamera(base);
  const u32 begin = AimU32(base, manager + 264), end = AimU32(base, manager + 268);
  const u32 n = (cam && AimAddrValid(begin) && end >= begin) ? (end - begin) / 4 : 0;
  if (n == 0 || n > 4096) {  // no targets, no camera or inconsistent vector: touch nothing
    if (trace) std::fprintf(stderr, "[eden] autoaim: 0 targets (vector %08X..%08X cam=%08X)\n", begin, end, cam);
    __imp__sub_82D19760(ctx, base);
    return;
  }

  // C = A·B (view·projection), row vectors.
  float A[4][4], B[4][4], C[4][4];
  for (int i = 0; i < 4; ++i)
    for (int j = 0; j < 4; ++j) {
      A[i][j] = AimF(base, cam + 144 + 16 * i + 4 * j);
      B[i][j] = AimF(base, cam + 224 + 16 * i + 4 * j);
    }
  for (int i = 0; i < 4; ++i)
    for (int j = 0; j < 4; ++j) C[i][j] = A[i][0] * B[0][j] + A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j];

  const float mw = AimF(base, ctx.r5.u32), mh = AimF(base, ctx.r6.u32);  // W/2 and H/2, the same ones the lock-on uses
  // EDEN_AIM_TEST=1 (diagnostic): alternates the real cursor between the top and the bottom edge every 600 frames and
  // logs the view matrix, to measure whether the camera responds to the cursor.
  static const int test = [] { const char* e = std::getenv("EDEN_AIM_TEST"); return e ? std::atoi(e) : 0; }();  // 2 = log only
  if (test) {
    const u32 phase = (calls / 600) % 2;
    const u32 real = AimRealCursor(ctx, base);
    const float qy = phase ? 2.0f * mh - 24.0f : 24.0f;
    if (test == 1) {
      if (real) { AimWriteF(base, real + 4, mw); AimWriteF(base, real + 8, qy); }
      AimWriteF(base, ctx.r7.u32, mw);
      AimWriteF(base, ctx.r8.u32, qy);
    }
    if (calls % 100 == 0)
      std::fprintf(stderr, "[eden] aim_test: n=%u phase=%u view col2=(%.3f,%.3f,%.3f) col1=(%.3f,%.3f,%.3f) pos=(%.1f,%.1f,%.1f) cursor=(%.0f,%.0f)\n",
                   calls, phase, A[0][2], A[1][2], A[2][2], A[0][1], A[1][1], A[2][1], A[3][0], A[3][1], A[3][2],
                   AimF(base, ctx.r7.u32), AimF(base, ctx.r8.u32));
    __imp__sub_82D19760(ctx, base);
    return;
  }
  const u32 px = ctx.r7.u32, py = ctx.r8.u32;                          // sight+696 and sight+700
  const float mx = AimF(base, px), my = AimF(base, py);

  u32 alive = 0, candidates = 0;
  u32 r_st2 = 0, r_stx = 0, r_nolock = 0, r_behind = 0, r_off = 0;  // why each live target was discarded
  float best = 1e30f, ex = 0, ey = 0;
  u32 chosen = 0;
  // The out-of-view target with the most health (the boss before its projectiles), to turn towards it.
  float fx = 0, fy = 0;  // direction on screen (right, down) towards that target
  int off_health = -1;
  u32 off_chosen = 0;
  auto offscreen = [&](u32 b, float dx, float dy) {
    const int health = static_cast<int>(AimU32(base, b + 4));
    if (health > off_health) {
      off_health = health;
      fx = dx;
      fy = dy;
      off_chosen = b;
    }
  };
  for (u32 k = 0; k < n; ++k) {
    const u32 b = AimU32(base, begin + 4 * k);
    if (!AimAddrValid(b)) continue;
    const u32 state = AimU32(base, b + 20);
    if (state != 0) ++alive;
    {  // EDEN_DAMAGE=N (bot cheat, off without the variable): each hit on a big target (bosses, health > 1000) takes
       // N times what the game took. Measured in run 483: the Journey boss has 10 000 health and each laser
       // takes 1, in batches of ~6 every 165 frames; at the bot's pace that would be hours.
      static const int damage = [] { const char* e = std::getenv("EDEN_DAMAGE"); return e ? std::atoi(e) : 0; }();
      static std::map<u32, int> healths;
      static u32 notices = 0;
      const int health = static_cast<int>(AimU32(base, b + 4));
      auto it = healths.find(b);
      if (health > 1000) {
        if (it == healths.end()) {
          if (healths.size() > 64) healths.clear();
          healths[b] = health;
        } else if (health < it->second) {
          int new_health = health;
          if (damage > 1) {
            new_health = std::max(1, health - (it->second - health) * (damage - 1));
            const u32 be = __builtin_bswap32(static_cast<u32>(new_health));
            std::memcpy(REX_RAW_ADDR(b + 4), &be, 4);
          }
          if (notices++ % 50 == 0)
            std::fprintf(stderr, "[eden] boss %08X health %d -> %d (EDEN_DAMAGE=%d leaves it at %d) frame %u flags=%08X\n", b,
                         it->second, health, damage, new_health, calls, AimU32(base, b + 8));
          it->second = new_health;
        } else {
          it->second = health;
        }
      } else if (it != healths.end()) {
        healths.erase(it);
      }
    }
    if (state != 1) {                                         // 0 dead/inactive, 2 already locked to the maximum
      if (state == 2) ++r_st2; else if (state != 0) ++r_stx;
      continue;
    }
    if (mode < 2 && (AimU32(base, b + 8) & 0x08)) { ++r_nolock; continue; }  // not lockable
    const float p[4] = {AimF(base, b + 32), AimF(base, b + 36), AimF(base, b + 40), 1.0f};
    float c[4];
    for (int j = 0; j < 4; ++j) c[j] = p[0] * C[0][j] + p[1] * C[1][j] + p[2] * C[2][j] + p[3] * C[3][j];
    if (!(c[2] > 0.0f) || !(std::fabs(c[3]) > 1e-6f)) {  // behind the camera
      ++r_behind;
      offscreen(b, c[0], -c[1]);  // clip.x and clip.y keep the side (right/up) even if w is negative
      continue;
    }
    const float x = (c[0] / c[3] + 1.0f) * mw, y = (1.0f - c[1] / c[3]) * mh;
    if (!(x > 0.0f && y > 0.0f && x < 2.0f * mw && y < 2.0f * mh)) {  // off screen
      if (trace && r_off < 3)
        std::fprintf(stderr, "[eden] autoaim: off screen target=%08X (%.0f,%.0f) health=%d flags=%08X\n", b, x, y,
                     static_cast<int>(AimU32(base, b + 4)), AimU32(base, b + 8));
      ++r_off;
      offscreen(b, x - mw, y - mh);
      continue;
    }
    ++candidates;
    const float d = (x - mx) * (x - mx) + (y - my) * (y - my);
    if (d < best) {
      best = d;
      ex = x;
      ey = y;
      chosen = b;
    }
  }
  if (chosen) {
    AimWriteF(base, px, ex);
    AimWriteF(base, py, ey);
    AimRequestStick((ex - mw) / mw, (ey - mh) / mh);  // and the view follows the target
  } else if (off_chosen) {
    // Run 475 (Journey): the boss ends up above the screen and the view only turns if the player's cursor goes
    // to the edge. With no targets on screen the cursor (sight+1460/1464, what the game copies to sight+696/700 in
    // controller mode) is taken to the edge closest to the target that was left out.
    // Point on the screen edge in the direction of the target (also valid if it ended up behind the camera).
    const float margin = 24.0f;
    float ax = std::fabs(fx), ay = std::fabs(fy);
    if (ax < 1e-3f && ay < 1e-3f) { fx = 1.0f; ax = 1.0f; }  // right behind: turn to the right
    const float k = std::min(ax > 1e-3f ? (mw - margin) / ax : 1e30f, ay > 1e-3f ? (mh - margin) / ay : 1e30f);
    const float bx = mw + fx * k, by = mh + fy * k;
    const float len = std::sqrt(fx * fx + fy * fy);
    AimRequestStick(fx / len, fy / len);
    const u32 real = 0;
    AimWriteF(base, px, bx);
    AimWriteF(base, py, by);
    if (trace)
      std::fprintf(stderr, "[eden] autoaim: no targets on screen; cursor to the edge (%.0f,%.0f) towards target=%08X "
                           "health=%d dir=(%.0f,%.0f) real_cursor=%08X\n", bx, by, off_chosen, off_health, fx, fy, real);
  }
  if (trace) {
    if (chosen)
      std::fprintf(stderr, "[eden] autoaim: %u targets, chosen (%.1f,%.1f)  [vector=%u alive=%u target=%08X health=%d "
                           "before=(%.1f,%.1f)]\n",
                   candidates, ex, ey, n, alive, chosen, static_cast<int>(AimU32(base, chosen + 4)), mx, my);
    else
      std::fprintf(stderr, "[eden] autoaim: 0 targets, chosen (none)  [vector=%u alive=%u before=(%.1f,%.1f) "
                           "discarded: locked=%u other_state=%u not_lockable=%u behind=%u off_screen=%u]\n", n,
                   alive, mx, my, r_st2, r_stx, r_nolock, r_behind, r_off);
  }
  __imp__sub_82D19760(ctx, base);  // the ray is computed with the new position already
}

// --- Crash of 2026-11-20 on the build machine (run 423): the same XMA voice without a context, through another door ----
// sub_82E84820(r3 = player, r4 = stream index) is a leaf function that reads the registers of the stream's XMA
// context (pointer at entry+64, unless bit 0x20000 of player+4 says the entry itself acts as the context)
// to return how much is pending. With the pointer at 0 it reads address 4 and the process dies
// ("unhandled title read of 0x00000004", stack sub_82E84820 <- sub_82E87F28 <- sub_82E88A28 <- … <- sub_82E7D008).
// The guard in sub_82E84FE8 did not cover this read. Here 0 is returned (nothing pending) and a note is left in the log.
REX_HOOK_RAW(sub_82E84820) {
  const u32 obj = ctx.r3.u32;
  auto L = [&](u32 d) { u32 v; std::memcpy(&v, REX_RAW_ADDR(d), 4); return __builtin_bswap32(v); };
  if (obj && !(L(obj + 4) & 0x20000)) {
    const u32 arr = L(obj + 8);
    if (!arr || L(arr + 96 * ctx.r4.u32 + 64) == 0) {
      static std::atomic<u32> warnings{0};
      if (warnings.fetch_add(1) < 40)
        std::fprintf(stderr, "[eden] XMA: read of stream %u of player %08X without a context; returning 0 instead "
                             "of crashing the game\n", ctx.r4.u32, obj);
      ctx.r3.u64 = 0;
      return;
    }
  }
  __imp__sub_82E84820(ctx, base);
}

// --- Black video that never ends (Journey, area 5): a file read the game took as empty ---
// sub_8292A118(r3 = handle, r4 = position, r5 = buffer, r6 = length, r7 = &bytes_read, r8 = OVERLAPPED) is the file
// read of the game's video player. It calls ReadFile (sub_82E79550) WITHOUT a bytes-read pointer and only
// fills *bytes_read through GetOverlappedResult when ReadFile answers "pending" (997) or end of file (38). On the
// console an asynchronous read always stays pending; here it finishes instantly, ReadFile answers success and *bytes_read
// stays at 0. The codec's 64 KB reader (sub_82ED8388) takes it as "no data", the audio decoder
// returns 0x80500001 -> 0x8000FFFF, its thread stops the player and sub_82EE47E0 waits for samples forever.
// It only happens when the audio needs data beyond the first 64 KB (which the game has preloaded):
// jny_a5_event.wmv and ubi_logo.wmv, out of 165 videos. Measured in runs 498, 500 and 501.
// Fix: after a successful read, put in *bytes_read what the OVERLAPPED says (InternalHigh), which is the same as
// what GetOverlappedResult would have returned.
REX_HOOK_RAW(sub_8292A118) {
  const u32 bytes_read = ctx.r7.u32, ov = ctx.r8.u32;
  __imp__sub_8292A118(ctx, base);
  if (ctx.r3.u32 != 0 || !AimAddrValid(bytes_read) || !AimAddrValid(ov)) return;
  const u32 state = AimU32(base, ov), n = AimU32(base, ov + 4);
  if (static_cast<int>(state) < 0 || state == 259) return;  // error or still pending: do not touch
  const u32 before = AimU32(base, bytes_read);
  if (before != n) {
    const u32 be = __builtin_bswap32(n);
    std::memcpy(REX_RAW_ADDR(bytes_read), &be, 4);
    static std::atomic<int> notices{0};
    if (notices.fetch_add(1) < 5)
      std::fprintf(stderr, "[eden] video: read completed instantly, bytes read %u -> %u (OVERLAPPED %08X)\n",
                   before, n, ov);
  }
}

// --- Trace of the WMV player's flags (EDEN_VIDEO_TRACE=1; run 498) ---
// obj+224 and obj+228 are the flags of the two decoder threads (sub_82EE3A10 reads them through vtable+256,
// sub_82EE3CF0 through vtable+260; bit 4 = exit, bit 2 = stop decoding). Only four virtual routines change
// them: sub_82EE3780 (sets in +224), sub_82EE37E8 (sets in +228), sub_82EE38B8 (clears from +224) and
// sub_82EE3920 (clears from +228). Who calls them is logged, with the guest's return chain.
namespace {
void VidFlag(PPCContext& ctx, u8* base, const char* what) {
  if (!VidTrace()) return;
  const u32 obj = ctx.r3.u32, mask = ctx.r4.u32;
  char chain[160];
  int n = 0;
  chain[0] = 0;
  u32 sp = ctx.r1.u32;
  for (int i = 0; i < 8 && AimAddrValid(sp); ++i) {
    const u32 next = AimU32(base, sp);  // caller's frame
    if (!AimAddrValid(next) || next <= sp) break;
    const u32 lr = AimU32(base, next - 8);
    n += std::snprintf(chain + n, sizeof(chain) - n, " %08X", lr);
    if (n >= static_cast<int>(sizeof(chain)) - 10) break;
    sp = next;
  }
  std::fprintf(stderr, "[eden] vtrace %lld ms: FLAG %s obj=%08X mask=%X before +224=%X +228=%X lr=%08X chain:%s\n",
               VidMs(), what, obj, mask, AimAddrValid(obj) ? AimU32(base, obj + 224) : 0,
               AimAddrValid(obj) ? AimU32(base, obj + 228) : 0, static_cast<u32>(ctx.lr), chain);
}
}  // namespace

REX_HOOK_RAW(sub_82EE3780) {
  VidFlag(ctx, base, "set224");
  __imp__sub_82EE3780(ctx, base);
}
REX_HOOK_RAW(sub_82EE37E8) {
  VidFlag(ctx, base, "set228");
  __imp__sub_82EE37E8(ctx, base);
}
REX_HOOK_RAW(sub_82EE38B8) {
  VidFlag(ctx, base, "clear224");
  __imp__sub_82EE38B8(ctx, base);
}
REX_HOOK_RAW(sub_82EE3920) {
  VidFlag(ctx, base, "clear228");
  __imp__sub_82EE3920(ctx, base);
}

// obj+220: flags watched by the sample wait of sub_82EE47E0 (vtable+252; bit 1 = abandon the wait).
// sub_82EE3718 sets and sub_82EE3850 clears; in addition sub_82EE47E0 overwrites them with its r4 on entry.
REX_HOOK_RAW(sub_82EE3718) {
  VidFlag(ctx, base, "set220");
  if (VidTrace() && AimAddrValid(ctx.r3.u32))
    std::fprintf(stderr, "[eden] vtrace    +220=%X\n", AimU32(base, ctx.r3.u32 + 220));
  __imp__sub_82EE3718(ctx, base);
}
REX_HOOK_RAW(sub_82EE3850) {
  VidFlag(ctx, base, "clear220");
  if (VidTrace() && AimAddrValid(ctx.r3.u32))
    std::fprintf(stderr, "[eden] vtrace    +220=%X\n", AimU32(base, ctx.r3.u32 + 220));
  __imp__sub_82EE3850(ctx, base);
}

// The player's codec. Measured in run 498: the black screen of Journey's area 5 starts when sub_82ED7D98
// (vtable+120 of the decoder, obj+44 -> +48) returns an error on the first sample and the sub_82EE3CF0 thread itself
// calls "stop" (sub_82EE2670, chain 82EE3F2C 82EE34A4). These are its internal routines: every
// non-zero return is logged (33 = no more data) to find out which one fails and with what code.
namespace {
std::atomic<int> g_vid_codec_lines{0};
void VidCodec(const char* what, u32 in_r3, u32 in_r4, u32 lr, u32 ret) {
  // Errors only: the positive codes (0x0050xxxx, 33) are normal notices and filled the cap in run 499.
  if (!VidTrace() || (static_cast<int>(ret) >= 0 && (ret < 1 || ret > 64 || ret == 33))) return;
  if (g_vid_codec_lines.fetch_add(1) > 600) return;
  std::fprintf(stderr, "[eden] vtrace %lld ms: CODEC %s r3=%08X r4=%08X lr=%08X returns %d (%08X)\n", VidMs(), what,
               in_r3, in_r4, lr, static_cast<int>(ret), ret);
}
}  // namespace
#define EDEN_VID_CODEC(fn)                                                  \
  REX_HOOK_RAW(fn) {                                                        \
    const u32 a3 = ctx.r3.u32, a4 = ctx.r4.u32, lr = static_cast<u32>(ctx.lr); \
    __imp__##fn(ctx, base);                                                 \
    VidCodec(#fn, a3, a4, lr, ctx.r3.u32);                                  \
  }
EDEN_VID_CODEC(sub_82ED7D98)
EDEN_VID_CODEC(sub_82EDF0D0)
EDEN_VID_CODEC(sub_82EDF1E0)
EDEN_VID_CODEC(sub_82EDF598)
EDEN_VID_CODEC(sub_82EDEC08)
EDEN_VID_CODEC(sub_82EDCB48)
EDEN_VID_CODEC(sub_82EDD0C0)
EDEN_VID_CODEC(sub_82EDD2C0)
#undef EDEN_VID_CODEC

// The player's 64 KB cached reader. Measured in run 500: the codec's error 0x80500001 comes from
// sub_82EE88F8 when this routine (via sub_82ED8568) delivers 0 bytes. It returns 0 if more than 64 KB are requested or if
// any of the three calls to the stream at obj+52 fails (vtable+56 open, +52 seek, +60 read).
REX_HOOK_RAW(sub_82ED8388) {
  const u32 obj = ctx.r3.u32, size = ctx.r5.u32, out = ctx.r6.u32, lr = static_cast<u32>(ctx.lr);
  const u64 pos = ctx.r4.u64, r10 = ctx.r10.u64;
  __imp__sub_82ED8388(ctx, base);
  static std::atomic<int> lines{0};
  const bool failed = ctx.r3.u32 == 0 || (AimAddrValid(out) && AimU32(base, out) == 0);
  static std::atomic<bool> first{true};
  if (!VidTrace() || !AimAddrValid(obj)) return;
  if (!(failed || first.exchange(false)) || lines.fetch_add(1) > 60) return;
  const u32 stream = AimU32(base, obj + 52);
  const u32 vt = AimAddrValid(stream) ? AimU32(base, stream) : 0;
  std::fprintf(stderr,
               "[eden] vtrace %lld ms: READER %s obj=%08X pos=%llX size=%X r10=%llX lr=%08X returns %X; +112=%X +524=%08X "
               "+536=%X stream=%08X vt=%08X [52]=%08X [56]=%08X [60]=%08X [12]=%08X [20]=%08X\n",
               VidMs(), failed ? "FAILED" : "first", obj, static_cast<unsigned long long>(pos), size,
               static_cast<unsigned long long>(r10), lr, ctx.r3.u32, AimU32(base, obj + 112), AimU32(base, obj + 524),
               AimU32(base, obj + 536), stream, vt, AimAddrValid(vt) ? AimU32(base, vt + 52) : 0,
               AimAddrValid(vt) ? AimU32(base, vt + 56) : 0, AimAddrValid(vt) ? AimU32(base, vt + 60) : 0,
               AimAddrValid(vt) ? AimU32(base, vt + 12) : 0, AimAddrValid(vt) ? AimU32(base, vt + 20) : 0);
  if (AimAddrValid(stream)) {
    std::fprintf(stderr, "[eden] vtrace    stream:");
    for (u32 d = 0; d < 96; d += 4) std::fprintf(stderr, " %08X", AimU32(base, stream + d));
    std::fprintf(stderr, "\n");
  }
}

// ---- Performance round: the D3D wait no longer spins ----
// sub_82E58A00 waits for the GPU to advance the read pointer of the command ring by calling
// sub_82E5DF40 in a loop (32 db16cyc and a 5 s hang detector), without ever yielding: the main thread burned a whole
// core. Here the original iteration is kept, but after a short stretch of spinning (EDEN_WAIT_SPIN_US, 50 by
// default) each iteration sleeps EDEN_WAIT_SLEEP_US microseconds (200 by default). EDEN_WAIT_SLEEP_US=0 keeps the original spin.
namespace {
struct WaitOpt {
  int sleep_us = 200, spin_us = 50;
  WaitOpt() {
    if (const char* e = std::getenv("EDEN_WAIT_SLEEP_US"); e && *e) sleep_us = std::max(0, std::atoi(e));
    if (const char* e = std::getenv("EDEN_WAIT_SPIN_US"); e && *e) spin_us = std::max(0, std::atoi(e));
    std::fprintf(stderr, "[eden] D3D wait: spin %d us, sleep %d us\n", spin_us, sleep_us);
  }
};
const WaitOpt& WaitCfg() { static const WaitOpt o; return o; }
thread_local std::chrono::steady_clock::time_point wait_start;
// EDEN_STUTTER_DIAG=<ms>: for each frame longer than <ms>, says how much was game work (between one Swap and the
// next), how long the Swap took and how much of all that was waiting for the GPU. Only counts the thread that calls Swap.
thread_local double wait_ms_frame = 0;
thread_local int waits_frame = 0;
}  // namespace

void StutterDiagFrame(double swap_ms) {
  static const double threshold = [] { const char* e = std::getenv("EDEN_STUTTER_DIAG"); return (e && *e) ? std::atof(e) : 0.0; }();
  if (threshold <= 0) return;
  static auto before = std::chrono::steady_clock::now();
  static auto origin = before;
  static u32 n = 0;
  const auto now = std::chrono::steady_clock::now();
  const double frame = std::chrono::duration<double, std::milli>(now - before).count();
  before = now;
  ++n;
  if (frame > threshold && n > 1)
    std::fprintf(stderr, "[eden] stutter %.1f s (mono=%.4f) frame=%u: %.1f ms = game %.1f + swap %.1f; waiting for the GPU %.1f ms in %d waits\n",
                 std::chrono::duration<double>(now - origin).count(),
                 std::chrono::duration<double>(now.time_since_epoch()).count(), n, frame, frame - swap_ms, swap_ms,
                 wait_ms_frame, waits_frame);
  wait_ms_frame = 0;
  waits_frame = 0;
}

REX_HOOK_RAW(sub_82E5DE48) {  // sets up the state of a new wait
  wait_start = std::chrono::steady_clock::now();
  __imp__sub_82E5DE48(ctx, base);
}

REX_HOOK_RAW(sub_82E5DE78) {  // closes the wait
  wait_ms_frame += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - wait_start).count();
  ++waits_frame;
  __imp__sub_82E5DE78(ctx, base);
}

REX_HOOK_RAW(sub_82E5DF40) {
  __imp__sub_82E5DF40(ctx, base);
  const WaitOpt& o = WaitCfg();
  if (o.sleep_us == 0 || ctx.r3.u32 == 0) return;  // 0 = stop waiting (device lost)
  if (std::chrono::steady_clock::now() - wait_start < std::chrono::microseconds(o.spin_us)) return;
  std::this_thread::sleep_for(std::chrono::microseconds(o.sleep_us));
}
