/* KCDPerf 1.0.0 - performance plugin (ASI) for Kingdom Come: Deliverance (KCD1), Steam 1.9.8 WHGame.dll.
 * The code sites in WHGame.dll are found by byte signatures; each must match exactly once, otherwise nothing is changed,
 * so other builds of the game either work or are left untouched.
 * Files, all next to the .asi: KCDPerf.ini (read at start), KCDPerf.cmd (polled every 0.2 s, deleted after it ran),
 * KCDPerf.log (what the plugin did). Both command files hold one command per line; '#', ';' and '[' start a comment line.
 * Commands:
 *   stagger a,b,c   update period in frames of sun shadow cascades 2,3,4 (1-64; stock 2,2,2; needs e_ShadowsSparseGSMUpdate 1)
 *   smart 0|1       1: the plugin decides per frame which far cascade is redrawn: a skipped cascade also keeps its old
 *                   projection (stock recomputes it every frame), and a cascade is redrawn early (but not more often than
 *                   every 2nd frame) when the camera moved or turned more than the limits below
 *   spread 0|1      smart: at most one of the cascades 3 and 4 is redrawn per frame, the other waits a frame
 *   near n          smart: update period of cascade 1 (1-8; stock 1 = every frame)
 *   move f          smart: redraw when the camera moved more than f x the cascade's box size (default 0.05)
 *   mindot f        smart: redraw when dot(view direction now, at the last redraw) is below f (default 0.985 = 10 degrees)
 *   trim 0|1        0: the texture streamer's trim search (searched the whole trimmable list on nearly every mip request)
 *                   returns at once; 1: stock
 *   stats           write the smart setting and the redraw/skip counts of cascades 2-4 to KCDPerf.log
 * Built-in defaults, applied at start before KCDPerf.ini: stagger 2,8,16 and smart 1 (spread on, trim stock).
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define TITLE "KCDPerf 1.0.0"
#define FR_SKIP    0xa3             /* ShadowMapFrustum: byte, 1 = this frame reuses the old shadow map (sparse update) */
#define FR_LOD     0x1074           /* ShadowMapFrustum::nShadowMapLod */
#define FR_TYPE    0x0              /* ShadowMapFrustum::m_eFrustumType (int): 0 = dynamic cascade, 1 = "dynamic distance" = this
                                     * lod's static casters come from the engine shadow cache (r_ShadowsCache); written every frame
                                     * at WHGame.dll+0x381d6f before the hooked call */

void *memcpy(void *d, const void *s, size_t n) { BYTE *a = d; const BYTE *b = s; while (n--) *a++ = *b++; return d; }
void *memset(void *d, int c, size_t n) { BYTE *a = d; while (n--) *a++ = (BYTE)c; return d; }
static int same(const BYTE *a, const BYTE *b, SIZE_T n) { while (n--) if (*a++ != *b++) return 0; return 1; }
static int starts(const char *s, const char *p) { while (*p) if (*s++ != *p++) return 0; return 1; }

/* ---- log ---- */
static WCHAR g_dir[MAX_PATH + 8], g_log_path[MAX_PATH + 32], g_cmd_path[MAX_PATH + 32], g_ini_path[MAX_PATH + 32], g_frames_path[MAX_PATH + 32];
static int g_log_open; static char g_line[600]; static DWORD g_len; static CRITICAL_SECTION g_cs;
static void log_s(const char *s) { while (*s && g_len < sizeof g_line - 2) g_line[g_len++] = *s++; }
static void log_u(ULONGLONG v) { char t[24]; int i = 0; do { t[i++] = (char)('0' + v % 10); v /= 10; } while (v); while (i && g_len < sizeof g_line - 2) g_line[g_len++] = t[--i]; }
static void log_x(ULONG_PTR v) { char t[16]; int i = 0; do { t[i++] = "0123456789abcdef"[v & 15]; v >>= 4; } while (v); log_s("0x"); while (i && g_len < sizeof g_line - 2) g_line[g_len++] = t[--i]; }
static void log_end(void)
{
    HANDLE h; DWORD w;
    g_line[g_len++] = '\r'; g_line[g_len++] = '\n';
    h = CreateFileW(g_log_path, GENERIC_WRITE, FILE_SHARE_READ, NULL, g_log_open ? OPEN_ALWAYS : CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) { g_log_open = 1; SetFilePointer(h, 0, NULL, FILE_END); WriteFile(h, g_line, g_len, &w, NULL); CloseHandle(h); }
    g_len = 0;
}
#define LOG(...) do { EnterCriticalSection(&g_cs); __VA_ARGS__; log_end(); LeaveCriticalSection(&g_cs); } while (0)
static void wcpy(WCHAR *d, const WCHAR *a, const WCHAR *b) { while (*a) *d++ = *a++; while (*b) *d++ = *b++; *d = 0; }
static void paths_init(HINSTANCE self)
{
    DWORD n = GetModuleFileNameW(self, g_dir, MAX_PATH);
    while (n && g_dir[n - 1] != L'\\' && g_dir[n - 1] != L'/') n--;
    g_dir[n] = 0;
    wcpy(g_log_path, g_dir, L"KCDPerf.log"); wcpy(g_cmd_path, g_dir, L"KCDPerf.cmd"); wcpy(g_ini_path, g_dir, L"KCDPerf.ini"); wcpy(g_frames_path, g_dir, L"KCDPerf.frames");
}

static BYTE *g_base;

/* ---- signature scan (.text of WHGame.dll); -1 in a pattern = any byte ---- */
static BYTE *g_text; static SIZE_T g_text_len;
static BYTE *scan1(const short *pat, int n, const char *name)
{
    BYTE *hit = NULL; SIZE_T i; int j, hits = 0;
    if (g_text_len >= (SIZE_T)n) for (i = 0; i <= g_text_len - (SIZE_T)n; i++) {
        if (g_text[i] != (BYTE)pat[0]) continue;
        for (j = 1; j < n && (pat[j] < 0 || g_text[i + j] == (BYTE)pat[j]); j++) ;
        if (j == n) { if (!hits++) hit = g_text + i; }
    }
    if (hits != 1) { LOG(log_s("signature '"); log_s(name); log_s("': "); log_u((ULONGLONG)hits); log_s(" matches (need 1)")); return NULL; }
    return hit;
}
static BYTE *rel32(BYTE *at) { INT32 r; memcpy(&r, at, 4); return at + 4 + r; }
#define X (-1)
/* in CLightEntity::FillFrustumCastersList_SUN (Steam 1.9.8: 0x37fd48) */
static const short SIG_GATE[]  = { 0x41,0x8b,0x47,0x10, 0x4c,0x8d,0x05,X,X,X,X, 0x41,0x03,0x44,0xe8,0x04, 0x33,0xd2, 0x41,0xf7,0x34,0xe8 };   /* (frame + tab[lod].off) % tab[lod].period */
static const short SIG_CVAR[]  = { 0x41,0x39,0xbe,X,X,0x00,0x00, 0x0f,0x84,X,X,X,X, 0x48,0x8b,0x0d,X,X,X,X, 0x48,0x8b,0x01, 0xff,0x90,X,X,0x00,0x00, 0x41,0x3b,0xc5 };   /* cmp [cvars + e_ShadowsSparseGSMUpdate], 0 */
static const short SIG_RESET[] = { 0x41,0x8a,0xd5, 0xe8,X,X,X,X, 0x48,0x8b,0x0e, 0x40,0x38,0xb9,0xa3,0x00,0x00,0x00 };   /* call ShadowMapFrustum::ResetCasterLists; cmp [fr+0xa3], 0 */
static const short SIG_JE[]    = { 0x48,0x8b,0x88,X,X,0x00,0x00, 0x48,0x85,0xc9, 0x0f,0x84,X,X,X,X, 0x39,0x79,0x08, 0x0f,0x84,X,X,X,X, 0x41,0x8a,0xcd, 0xe9 };   /* "caster list empty: no skip allowed" */
/* in CLightEntity::ProcessFrustum (0x381f78): call InitShadowFrustum_SUN_Conserv(this, pFr**, types, boxSize, dist, lod, passInfo) */
static const short SIG_INIT[]  = { 0xf3,0x0f,0x11,0x5c,0x24,0x20, 0x0f,0x28,0xde, 0xe8,X,X,X,X, 0x48,0x8b,0x07, 0x83,0xc9,0xff };
#undef X
#define NSIG(a) (int)(sizeof(a) / sizeof(a[0]))
static int *g_tab;            /* {int period, int offset} x16 */
static BYTE **g_cv_pp; static int g_cv_off;   /* 3D engine CVars*, offset of e_ShadowsSparseGSMUpdate */
static BYTE *g_reset_site, *g_je_site, *g_init_site; static int FR_CASTERS = 0x1a8;   /* ShadowMapFrustum: PodArray<IShadowCaster*>* (count at +8) */
static int sites_find(void)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)g_base; IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)(g_base + dos->e_lfanew);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt); BYTE *gate, *cv, *rs, *je, *in, *q; int i;
    for (i = 0; i < nt->FileHeader.NumberOfSections; i++) if (same(sec[i].Name, (const BYTE *)".text\0\0", 8)) { g_text = g_base + sec[i].VirtualAddress; g_text_len = sec[i].Misc.VirtualSize; }
    if (!g_text) { LOG(log_s("no .text section found")); return 0; }
    gate = scan1(SIG_GATE, NSIG(SIG_GATE), "period table"); cv = scan1(SIG_CVAR, NSIG(SIG_CVAR), "sparse update cvar");
    rs = scan1(SIG_RESET, NSIG(SIG_RESET), "caster list reset"); je = scan1(SIG_JE, NSIG(SIG_JE), "skip test"); in = scan1(SIG_INIT, NSIG(SIG_INIT), "cascade init call");
    if (!gate || !cv || !rs || !je || !in) return 0;
    for (q = cv - 3; q > cv - 96 && !(q[0] == 0x4c && q[1] == 0x8b && q[2] == 0x35); q--) ;   /* mov r14, [rip + CVars*] */
    if (q <= cv - 96) { LOG(log_s("signature 'cvars pointer': not found")); return 0; }
    g_tab = (int *)(void *)rel32(gate + 7); g_cv_pp = (BYTE **)(void *)rel32(q + 3); memcpy(&g_cv_off, cv + 3, 4);
    g_reset_site = rs + 3; g_je_site = je + 19; memcpy(&FR_CASTERS, je + 3, 4); g_init_site = in + 9;
    LOG(log_s("sites: table +"); log_x((ULONG_PTR)((BYTE *)g_tab - g_base)); log_s(" cvars +"); log_x((ULONG_PTR)((BYTE *)g_cv_pp - g_base)); log_s(" [+"); log_x((ULONG_PTR)g_cv_off);
        log_s("] reset call +"); log_x((ULONG_PTR)(g_reset_site - g_base)); log_s(" skip test +"); log_x((ULONG_PTR)(g_je_site - g_base)); log_s(" init call +"); log_x((ULONG_PTR)(g_init_site - g_base));
        log_s(" casters +"); log_x((ULONG_PTR)FR_CASTERS));
    return 1;
}

/* ---- stagger: periods of the far sun cascades ---- */
static const int TAB_STOCK[10] = { 1, 0, 1, 0, 2, 1, 2, 0, 2, 0 };
static int g_tab_ok;
static int g_period[16] = { 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 };
static const int g_phase[16] = { 0, 0, 1, 0, 2, 3, 5, 7, 0, 0, 0, 0, 0, 0, 0, 0 };   /* periods 2/4/8: never two cascades in one frame */
static int g_keeplist; static ULONGLONG g_kept;
static int g_smart; static float g_move = 0.05f, g_mindot = 0.985f;
static void stagger_set(const char *v)
{
    int p[3] = { 0, 0, 0 }, i = 0, *tab;
    for (; *v && i < 3; v++) { if (*v >= '0' && *v <= '9') p[i] = p[i] * 10 + (*v - '0'); else if (*v == ',') i++; }
    if (!g_tab_ok) { LOG(log_s("stagger: table not recognised, nothing changed")); return; }
    tab = g_tab;
    for (i = 0; i < 3; i++) {
        if (p[i] < 1) p[i] = 1;
        if (p[i] > 64) p[i] = 64;
        g_period[2 + i] = p[i];
        if (!g_smart) { tab[(2 + i) * 2 + 1] = g_phase[2 + i] % p[i]; tab[(2 + i) * 2] = p[i]; }   /* offset first */
    }
    LOG(log_s("stagger: cascade 2/3/4 update every "); log_u(p[0]); log_s("/"); log_u(p[1]); log_s("/"); log_u(p[2]); log_s(" frames"));
}

/* ---- why stock periods above 2 do nothing ----
 * On a skipped frame the game empties the cascade's caster list (that is what skips the drawing; the old shadow map is
 * reused), and an empty list forbids the next skip. So a cascade is redrawn every 2nd frame whatever its period says.
 * Keeping the list instead (0.2.1) makes the skipped frames draw: slower than stock, so g_keeplist stays 0.
 * 0.2.2: in smart mode the "list empty: no skip" jump is removed; the plugin itself knows whether a cascade has been drawn. */
typedef void (*PFN_Reset)(void *fr, BYTE flag);
static PFN_Reset g_reset_orig;
static void my_reset(void *fr, BYTE flag)
{
    if (g_keeplist && *((BYTE *)fr + FR_SKIP)) { g_kept++; return; }
    g_reset_orig(fr, flag);
}

/* ---- smart stagger: replaces the call to InitShadowFrustum_SUN_Conserv ---- */
typedef void (*PFN_Init)(void *self, void **ppFr, int types, float box, float dist, int lod, void *pass);
static PFN_Init g_init_orig;
static struct { void *fr; unsigned frame; float pos[3], dir[3]; } g_st[16];
static struct { ULONGLONG upd[16], skip[16], early[16], cast[16], castn[16], defer[16], cached[16]; } g_sc;
/* fill statistics of the cached frustums (measuring tool): frames in which the shadow cache handed new casters to a cached
 * cascade, their sum, and the runs of consecutive such frames (one run = one rebuild being filled) */
static struct { ULONGLONG frames, casters, runs, maxrun, cur; } g_cf[16];
static unsigned g_cf_frame = 0xffffffffu; static int g_cf_cnt, g_ncached; static BYTE *g_cf_base; static int g_cf_ok;
static int g_spread = 1; static unsigned g_far_frame = 0xffffffffu;   /* spread: at most one of the cascades 3+ is redrawn per frame */
static volatile LONG g_fmask;   /* bit n: cascade n's caster list was filled when this frame started = it was redrawn in the frame before */
static void my_init(void *self, void **ppFr, int types, float box, float dist, int lod, void *pass)
{
    if (lod >= 0 && lod < 16 && ppFr && *ppFr) {   /* casters gathered at this cascade's last redraw (the list is emptied on skipped frames) */
        void *l = *(void **)((BYTE *)*ppFr + FR_CASTERS); int n = l ? *(int *)((BYTE *)l + 8) : 0;
        if (n > 0) { g_sc.cast[lod] += (unsigned)n; g_sc.castn[lod]++; g_fmask |= 1 << lod; }
    }
    if (g_smart && g_tab_ok && lod >= 1 && lod < 16 && ppFr && *ppFr && pass) {
        BYTE *fr = (BYTE *)*ppFr, *cv = *g_cv_pp; const float *cam = *(const float **)((BYTE *)pass + 0x18);
        unsigned frame = *(unsigned *)((BYTE *)pass + 0x10), age = frame - g_st[lod].frame; int *tab = g_tab + lod * 2;
        int per = g_period[lod], valid, due, moved = 0;
        void *list = *(void **)(fr + FR_CASTERS);
        /* 0.3.8: a lod the shadow cache handles is never skipped. On a skipped frame (fr+0xa3) the renderer does not merge
         * the cached map into this cascade and reuses an old depth texture: far building shadows went missing. */
        if (frame != g_cf_frame) { g_cf_frame = frame; g_ncached = g_cf_cnt; g_cf_cnt = 0; g_cf_ok = 0; g_cf_base = (BYTE *)ppFr - lod * 0x10; }
        else if (g_cf_base == (BYTE *)ppFr - lod * 0x10) g_cf_ok = 1;   /* the frustum pointers really are slots of one array (0x10 apart) */
        if (*(int *)(fr + FR_TYPE) != 0) {
            tab[0] = 1; tab[1] = 0; g_st[lod].fr = 0; g_sc.cached[lod]++; g_cf_cnt++;
            if (g_cf_ok && g_ncached > 0 && g_ncached < 8) {   /* the paired cached frustum sits g_ncached slots further on */
                BYTE **slot = (BYTE **)((BYTE *)ppFr + g_ncached * 0x10), *cf;
                if (!IsBadReadPtr(slot, 8) && (cf = *slot) != NULL && !IsBadReadPtr(cf, 0x1080) && *(int *)cf == 2 && *(int *)(cf + FR_LOD) == lod) {
                    void *cl = *(void **)(cf + FR_CASTERS); int cn = (cl && !IsBadReadPtr(cl, 16)) ? *(int *)((BYTE *)cl + 8) : 0;
                    if (cn > 0) { g_cf[lod].frames++; g_cf[lod].casters += (unsigned)cn; if (!g_cf[lod].cur++) g_cf[lod].runs++; if (g_cf[lod].cur > g_cf[lod].maxrun) g_cf[lod].maxrun = g_cf[lod].cur; }
                    else g_cf[lod].cur = 0;
                }
            }
            g_init_orig(self, ppFr, types, box, dist, lod, pass); return;
        }
        float px = cam[3], py = cam[7], pz = cam[11], dx = cam[1], dy = cam[5], dz = cam[9];
        valid = cv && *(int *)(cv + g_cv_off) && per > 1 && g_st[lod].fr == fr && list && *(int *)(fr + FR_LOD) == lod;
        due = age >= (unsigned)per || (frame + (unsigned)g_phase[lod]) % (unsigned)per == 0;
        if (valid && !due && age >= 2) {
            float mx = px - g_st[lod].pos[0], my = py - g_st[lod].pos[1], mz = pz - g_st[lod].pos[2], lim = g_move * box;
            moved = mx * mx + my * my + mz * mz > lim * lim || dx * g_st[lod].dir[0] + dy * g_st[lod].dir[1] + dz * g_st[lod].dir[2] < g_mindot;
        }
        if (valid && g_spread && lod >= 3 && (due || moved) && g_far_frame == frame && age < 2u * (unsigned)per + 4u) { due = 0; moved = 0; g_sc.defer[lod]++; }   /* another far cascade is redrawn in this frame: this one waits a frame */
        if (valid && !due && !moved) {   /* skip: old projection stays; make the game's own check skip the caster gather too */
            tab[1] = (frame & 1) ? 0 : 1; tab[0] = 2; g_sc.skip[lod]++;
            /* stock empties the caster lists on a skipped frame only when the frustum's update mask is set, and that is
             * set by the init call skipped here: without this the old list would be drawn again (0.2.2: slower than stock) */
            if (g_reset_orig) g_reset_orig(fr, 1);
            return;
        }
        tab[0] = 1; tab[1] = 0;
        g_st[lod].fr = fr; g_st[lod].frame = frame; g_st[lod].pos[0] = px; g_st[lod].pos[1] = py; g_st[lod].pos[2] = pz;
        g_st[lod].dir[0] = dx; g_st[lod].dir[1] = dy; g_st[lod].dir[2] = dz;
        g_sc.upd[lod]++; if (moved) g_sc.early[lod]++; if (lod >= 3) g_far_frame = frame;
    }
    g_init_orig(self, ppFr, types, box, dist, lod, pass);
}
static BYTE COUNT_JE[6]; static const BYTE COUNT_NOP[6] = { 0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00 };   /* COUNT_JE = the stock bytes, saved at start */
static int count_patch(int on)
{
    BYTE *site = g_je_site; DWORD old, tmp; const BYTE *want = on ? COUNT_NOP : COUNT_JE;
    if (same(site, want, 6)) return 1;
    if (!same(site, on ? COUNT_JE : COUNT_NOP, 6)) { LOG(log_s("smart: skip test differs from the supported build, not changed")); return 0; }
    if (!VirtualProtect(site, 6, PAGE_EXECUTE_READWRITE, &old)) return 0;
    memcpy(site, want, 6); VirtualProtect(site, 6, old, &tmp); FlushInstructionCache(GetCurrentProcess(), site, 6);
    return 1;
}
static void smart_set(const char *v)
{
    int on = *v == '1', i, *tab = g_tab;
    if (!g_init_orig || !g_tab_ok) { LOG(log_s("smart: hook not installed")); return; }
    g_smart = 0; Sleep(50);
    if (!count_patch(on)) on = 0;
    tab[3] = 0; tab[2] = 1;   /* cascade 1: stock */
    for (i = 2; i < 5; i++) { tab[i * 2 + 1] = g_phase[i] % g_period[i]; tab[i * 2] = g_period[i]; }   /* plain table mode values */
    memset(&g_sc, 0, sizeof g_sc); memset(g_st, 0, sizeof g_st);
    g_smart = on;
    LOG(log_s("smart: "); log_s(on ? "on" : "off"); log_s(", periods "); log_u(g_period[1]); log_s("/"); log_u(g_period[2]); log_s("/"); log_u(g_period[3]); log_s("/"); log_u(g_period[4]));
}
static float parse_f(const char *v)
{
    float r = 0, sc = 1; int neg = 0;
    if (*v == '-') { neg = 1; v++; }
    for (; *v >= '0' && *v <= '9'; v++) r = r * 10 + (float)(*v - '0');
    if (*v == '.') for (v++; *v >= '0' && *v <= '9'; v++) { sc *= 0.1f; r += sc * (float)(*v - '0'); }
    return neg ? -r : r;
}

static BYTE *g_stub_page;   /* one page near WHGame.dll: +64 and +96 jump stubs */
static BYTE *alloc_near(const BYTE *target)
{
    SYSTEM_INFO si; MEMORY_BASIC_INFORMATION mbi; ULONG_PTR gran, t = (ULONG_PTR)target, p; int guard; BYTE *r;
    GetSystemInfo(&si); gran = si.dwAllocationGranularity;
    for (p = (t & ~(gran - 1)) - gran, guard = 0; p > t - 0x70000000u && guard < 100000; guard++) {
        if (!VirtualQuery((void *)p, &mbi, sizeof mbi)) break;
        if (mbi.State == MEM_FREE) { r = VirtualAlloc((void *)p, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE); if (r) return r; p -= gran; }
        else { ULONG_PTR ab = (ULONG_PTR)mbi.AllocationBase; p = ((ab && ab < p ? ab : p) - gran) & ~(gran - 1); }
    }
    return NULL;
}
static void put32(BYTE *p, INT64 v) { p[0] = (BYTE)v; p[1] = (BYTE)(v >> 8); p[2] = (BYTE)(v >> 16); p[3] = (BYTE)(v >> 24); }

static void init_hook_install(void)
{
    BYTE *site = g_init_site, *fn, *stub; DWORD old, tmp;
    if (!site) return;
    fn = rel32(site + 1);
    if (site[0] != 0xE8) { LOG(log_s("cascade hook: code differs from the supported build, not installed")); return; }
    if (!g_stub_page) g_stub_page = alloc_near(site);
    if (!g_stub_page) { LOG(log_s("cascade hook: no memory near WHGame.dll, not installed")); return; }
    stub = g_stub_page + 64; stub[0] = 0xFF; stub[1] = 0x25; put32(stub + 2, 0); *(void **)(stub + 6) = (void *)my_init;
    g_init_orig = (PFN_Init)(void *)fn;
    if (!VirtualProtect(site, 5, PAGE_EXECUTE_READWRITE, &old)) { g_init_orig = NULL; LOG(log_s("cascade hook: cannot write, not installed")); return; }
    put32(site + 1, (INT64)(ULONG_PTR)stub - (INT64)(ULONG_PTR)(site + 5));
    VirtualProtect(site, 5, old, &tmp); FlushInstructionCache(GetCurrentProcess(), site, 5);
    LOG(log_s("cascade hook installed at WHGame.dll+"); log_x((ULONG_PTR)(site - g_base)));
}
static void reset_hook_install(void)
{
    BYTE *site = g_reset_site, *fn, *stub; DWORD old, tmp;
    if (!site) return;
    fn = rel32(site + 1);
    if (site[0] != 0xE8 || !g_stub_page) { LOG(log_s("caster list hook: code differs from the supported build, not installed")); return; }
    stub = g_stub_page + 96; stub[0] = 0xFF; stub[1] = 0x25; put32(stub + 2, 0); *(void **)(stub + 6) = (void *)my_reset;
    g_reset_orig = (PFN_Reset)(void *)fn;
    if (!VirtualProtect(site, 5, PAGE_EXECUTE_READWRITE, &old)) { g_reset_orig = NULL; LOG(log_s("caster list hook: cannot write, not installed")); return; }
    put32(site + 1, (INT64)(ULONG_PTR)stub - (INT64)(ULONG_PTR)(site + 5));
    VirtualProtect(site, 5, old, &tmp); FlushInstructionCache(GetCurrentProcess(), site, 5);
    LOG(log_s("caster list hook installed at WHGame.dll+"); log_x((ULONG_PTR)(site - g_base)));
}

/* ---- texture streamer: CPlanningTextureStreamer::TrimTexture (Steam 1.9.8: 0x37c880) searches the whole list of
 * trimmable textures for one in the same pool, on nearly every mip request, because the pool-item probe before it
 * can never succeed in this build. `trim 0` makes it return false at once (xor eax,eax; ret): the request then takes
 * the normal allocate path; the streamer's own memory-pressure trim stays. One aligned 8-byte store. ---- */
static const BYTE TRIM_SIG[48] = { 0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20,0x41,0x54,0x41,0x56,0x41,0x57,0x48,0x83,0xec,0x20,
    0x4d,0x8b,0x18,0x45,0x33,0xe4,0x49,0x8b,0xd9,0x4d,0x8b,0xf0,0x8b,0xf2,0x41,0x8b,0xec,0x41 };
static BYTE *g_trim_fn; static int g_trim_looked, g_trim_off;
static void trim_set(int stock)
{
    static const BYTE on8[8] = { 0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c }, off8[8] = { 0x31,0xc0,0xc3,0x90,0x90,0x48,0x89,0x6c };
    ULONGLONG v; DWORD old, tmp;
    if (!g_trim_looked && g_text) { short pat[48]; int i; g_trim_looked = 1; for (i = 0; i < 48; i++) pat[i] = TRIM_SIG[i]; g_trim_fn = scan1(pat, 48, "texture trim search"); }
    if (!g_trim_fn || ((ULONG_PTR)g_trim_fn & 7)) { LOG(log_s("trim: not available")); return; }
    if (!same(g_trim_fn, g_trim_off ? off8 : on8, 8)) { LOG(log_s("trim: code differs, not changed")); return; }
    memcpy(&v, stock ? on8 : off8, 8);
    if (!VirtualProtect(g_trim_fn, 8, PAGE_EXECUTE_READWRITE, &old)) return;
    *(volatile ULONGLONG *)(void *)g_trim_fn = v;
    VirtualProtect(g_trim_fn, 8, old, &tmp); FlushInstructionCache(GetCurrentProcess(), g_trim_fn, 8);
    g_trim_off = !stock;
    LOG(log_s("trim: texture trim search "); log_s(stock ? "stock" : "off"); log_s(" at WHGame.dll+"); log_x((ULONG_PTR)(g_trim_fn - g_base)));
}

static volatile LONG g_cfreeze, g_frz_ts;
static volatile LONG g_frz_bias, g_frz_fmt, g_frz_ox, g_frz_oy, g_frz_gen;

/* ---- commands ---- */
static void run_line(char *p)
{
    while (*p == ' ' || *p == '\t') p++;
    if (!*p || *p == '#' || *p == ';' || *p == '[') return;
    if (starts(p, "stagger")) { p += 7; while (*p == ' ' || *p == '=') p++; stagger_set(p); }
    else if (starts(p, "spread")) { p += 6; while (*p == ' ' || *p == '=') p++; g_spread = *p != '0'; LOG(log_s("spread: "); log_s(g_spread ? "on" : "off")); }
    else if (starts(p, "smart")) { p += 5; while (*p == ' ' || *p == '=') p++; smart_set(p); }
    else if (starts(p, "near")) { int n = 0; p += 4; while (*p == ' ' || *p == '=') p++; while (*p >= '0' && *p <= '9') n = n * 10 + (*p++ - '0'); g_period[1] = n < 1 ? 1 : n > 8 ? 8 : n; LOG(log_s("near: cascade 1 update every "); log_u((ULONGLONG)g_period[1]); log_s(" frames (smart mode)")); }
    else if (starts(p, "trim")) { p += 4; while (*p == ' ' || *p == '=') p++; trim_set(*p != '0'); }
    else if (starts(p, "move")) { p += 4; while (*p == ' ' || *p == '=') p++; g_move = parse_f(p); LOG(log_s("move limit x1000: "); log_u((ULONGLONG)(g_move * 1000))); }
    else if (starts(p, "mindot")) { p += 6; while (*p == ' ' || *p == '=') p++; g_mindot = parse_f(p); LOG(log_s("mindot x1000: "); log_u((ULONGLONG)(g_mindot * 1000))); }
    else if (starts(p, "stats")) LOG(log_s("smart "); log_s(g_smart ? "on" : "off"); log_s(": cascade redraws/skips  c2 "); log_u(g_sc.upd[2]); log_s("/"); log_u(g_sc.skip[2]); log_s("  c3 "); log_u(g_sc.upd[3]); log_s("/"); log_u(g_sc.skip[3]); log_s("  c4 "); log_u(g_sc.upd[4]); log_s("/"); log_u(g_sc.skip[4]));
    else LOG(log_s("unknown command: "); log_s(p));
}
static int run_file(const WCHAR *path, int del)
{
    static char buf[2048]; DWORD n = 0; char *p, *e; HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    ReadFile(h, buf, sizeof buf - 1, &n, NULL); CloseHandle(h); buf[n] = 0;
    if (del) DeleteFileW(path);
    for (p = buf; *p; p = e) { e = p; while (*e && *e != '\n' && *e != '\r') e++; if (*e) *e++ = 0; run_line(p); }
    return 1;
}
static DWORD WINAPI worker(LPVOID arg)
{
    int i;
    (void)arg;
    for (i = 0; i < 600 && !(g_base = (BYTE *)GetModuleHandleW(L"WHGame.dll")); i++) Sleep(100);
    if (!g_base) { LOG(log_s("WHGame.dll not loaded after 60 s: nothing changed")); return 0; }
    LOG(log_s("WHGame.dll at "); log_x((ULONG_PTR)g_base));
    if (sites_find()) {
        g_tab_ok = same((const BYTE *)g_tab, (const BYTE *)TAB_STOCK, sizeof TAB_STOCK);
        LOG(log_s(g_tab_ok ? "cascade period table found (stock 1,1,2,2,2)" : "cascade period table has unexpected values: shadow patch off"));
        if (g_tab_ok) { memcpy(COUNT_JE, g_je_site, 6); init_hook_install(); reset_hook_install();
            if (g_init_orig && g_reset_orig) { stagger_set("2,8,16"); smart_set("1"); }   /* built-in defaults; KCDPerf.ini lines come after and win */
        }
    } else LOG(log_s("this build of the game is not supported: shadow patch off"));
    run_file(g_ini_path, 0);
    for (;;) { Sleep(200); run_file(g_cmd_path, 1); }
}
BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        HMODULE pin; HANDLE th;
        DisableThreadLibraryCalls(self);
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCWSTR)(void *)worker, &pin);
        InitializeCriticalSection(&g_cs); paths_init(self);
        LOG(log_s(TITLE));
        th = CreateThread(NULL, 0, worker, NULL, 0, NULL); if (th) CloseHandle(th);
    }
    return TRUE;
}
