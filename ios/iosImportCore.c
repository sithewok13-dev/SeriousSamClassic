// Added: entire file. See iosImportCore.h.
//
// Plain C (POSIX and zlib) with no engine or Apple headers, so the same file
// builds for the phone, for a desktop test, and in the owner's other ports.

#include "iosImportCore.h"

#include <dirent.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

#define IMP_MAX_ENTRIES 60000   // enough for any game folder; stops a scan of a whole drive
#define IMP_MAX_DEPTH 8
#define IMP_BUF (1 << 20)

typedef struct {
    char* rel;        // under the virtual folder, '/'-separated, as found
    char* lower;      // rel with ASCII letters lowered (same length, same offsets)
    char* path;       // plain file: where it is; zip entry: the .zip
    int64_t size;     // -1 if unknown (an iCloud file not downloaded yet)
    int bZip;
    int zMethod;      // 0 stored, 8 deflated, -1 something else
    int bEncrypted;
    uint64_t zOffset; // the entry's local header
    uint64_t zComp;
    uint32_t zCrc;
    int bUse;         // part of the plan
    int restOfs;      // where its destination path starts in rel
} impEntry;

struct iosImportIndex {
    impEntry* e;
    int n, cap;
    char badZip[512];
};

static char* imp_strdup(const char* s)
{
    size_t n = strlen(s) + 1;
    char* d = (char*)malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

static void imp_lower(char* s)
{
    for (; *s; s++) {
        if (*s >= 'A' && *s <= 'Z') *s = (char)(*s - 'A' + 'a');
    }
}

static int imp_endsWithCase(const char* s, const char* end)
{
    size_t a = strlen(s), b = strlen(end);
    return a >= b && !strcasecmp(s + a - b, end);
}

static const char* imp_baseName(const char* p)
{
    const char* s = strrchr(p, '/');
    return s ? s + 1 : p;
}

// Names never worth copying: Finder and Windows leftovers
static int imp_isJunk(const char* name)
{
    return !strcmp(name, ".DS_Store") || !strncmp(name, "._", 2) || !strcasecmp(name, "__MACOSX")
           || !strcasecmp(name, "Thumbs.db") || !strcasecmp(name, "desktop.ini");
}

static impEntry* imp_add(iosImportIndex* idx, const char* rel, const char* path, int64_t size)
{
    if (idx->n >= IMP_MAX_ENTRIES) return NULL;
    if (idx->n == idx->cap) {
        int cap = idx->cap ? idx->cap * 2 : 256;
        impEntry* e = (impEntry*)realloc(idx->e, sizeof(impEntry) * cap);
        if (!e) return NULL;
        idx->e = e;
        idx->cap = cap;
    }
    impEntry* e = &idx->e[idx->n];
    memset(e, 0, sizeof(*e));
    e->rel = imp_strdup(rel);
    e->lower = imp_strdup(rel);
    e->path = imp_strdup(path);
    if (!e->rel || !e->lower || !e->path) {
        free(e->rel);
        free(e->lower);
        free(e->path);
        return NULL;
    }
    imp_lower(e->lower);
    e->size = size;
    idx->n++;
    return e;
}

iosImportIndex* iosImport_NewIndex(void)
{
    return (iosImportIndex*)calloc(1, sizeof(iosImportIndex));
}

void iosImport_FreeIndex(iosImportIndex* idx)
{
    if (!idx) return;
    for (int i = 0; i < idx->n; i++) {
        free(idx->e[i].rel);
        free(idx->e[i].lower);
        free(idx->e[i].path);
    }
    free(idx->e);
    free(idx);
}

static FILE* imp_open(const char* path, iosImportOpenFn pOpen, void* user)
{
    return pOpen ? pOpen(path, user) : fopen(path, "rb");
}

// ---- folders ----------------------------------------------------------------

static void imp_walk(iosImportIndex* idx, const char* dir, const char* rel, int depth)
{
    DIR* d = opendir(dir);
    if (!d) return;
    struct dirent* de;
    char path[2048], sub[2048], name[512];
    while ((de = readdir(d)) != NULL) {
        const char* n = de->d_name;
        if (!strcmp(n, ".") || !strcmp(n, "..") || imp_isJunk(n)) continue;
        int64_t size = -2;
        // An iCloud file that isn't on the phone yet shows as ".Name.icloud" on
        // older iOS versions; reading the real name (through the app's open
        // function) downloads it.
        size_t len = strlen(n);
        if (n[0] == '.' && len > 8 && !strcmp(n + len - 7, ".icloud")) {
            snprintf(name, sizeof(name), "%.*s", (int)(len - 8), n + 1);
            size = -1;
        } else if (n[0] == '.') {
            continue;
        } else {
            snprintf(name, sizeof(name), "%s", n);
        }
        snprintf(path, sizeof(path), "%s/%s", dir, name);
        snprintf(sub, sizeof(sub), "%s%s%s", rel, rel[0] ? "/" : "", name);
        if (size == -1) {
            imp_add(idx, sub, path, -1);
            continue;
        }
        struct stat st;
        if (stat(path, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            if (depth < IMP_MAX_DEPTH) imp_walk(idx, path, sub, depth + 1);
        } else if (S_ISREG(st.st_mode)) {
            imp_add(idx, sub, path, (int64_t)st.st_size);
        }
    }
    closedir(d);
}

// ---- zip --------------------------------------------------------------------

static uint16_t rd16(const unsigned char* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t rd32(const unsigned char* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t rd64(const unsigned char* p) { return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32); }

// A safe relative name: '\' becomes '/', no leading '/', no "." or ".." parts
// (a zip can't write outside the staging folder), and no junk.
static int imp_cleanZipName(const char* in, size_t n, char* out, size_t out_sz)
{
    if (n == 0 || n >= out_sz) return 0;
    size_t o = 0;
    for (size_t i = 0; i < n; i++) {
        char c = in[i];
        if (c == '\\') c = '/';
        if (c == 0) return 0;
        if (c == '/' && (o == 0 || out[o - 1] == '/')) continue;
        out[o++] = c;
    }
    out[o] = 0;
    if (o == 0 || out[o - 1] == '/') return 0; // a folder entry
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", out);
    for (char* part = strtok(tmp, "/"); part; part = strtok(NULL, "/")) {
        if (!strcmp(part, ".") || !strcmp(part, "..") || imp_isJunk(part)) return 0;
    }
    return 1;
}

static int imp_zipIndex(iosImportIndex* idx, const char* path, const char* prefix, iosImportOpenFn pOpen, void* user)
{
    FILE* f = imp_open(path, pOpen, user);
    if (!f) return 0;
    int ok = 0;
    unsigned char* tail = NULL;
    unsigned char* cd = NULL;
    if (fseeko(f, 0, SEEK_END) != 0) goto done;
    off_t fsize = ftello(f);
    if (fsize < 22) goto done;
    off_t tailLen = fsize < 65557 ? fsize : 65557;
    tail = (unsigned char*)malloc((size_t)tailLen);
    if (!tail || fseeko(f, fsize - tailLen, SEEK_SET) != 0 || fread(tail, 1, (size_t)tailLen, f) != (size_t)tailLen) goto done;
    off_t eocd = -1;
    for (off_t i = tailLen - 22; i >= 0; i--) {
        if (rd32(tail + i) == 0x06054b50) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) goto done;
    uint64_t count = rd16(tail + eocd + 10);
    uint64_t cdSize = rd32(tail + eocd + 12);
    uint64_t cdOfs = rd32(tail + eocd + 16);
    if (count == 0xFFFF || cdSize == 0xFFFFFFFFu || cdOfs == 0xFFFFFFFFu) {
        // Zip64: the real numbers are in a record the locator points to
        if (eocd < 20 || rd32(tail + eocd - 20) != 0x07064b50) goto done;
        uint64_t z64 = rd64(tail + eocd - 20 + 8);
        unsigned char rec[56];
        if (fseeko(f, (off_t)z64, SEEK_SET) != 0 || fread(rec, 1, 56, f) != 56 || rd32(rec) != 0x06064b50) goto done;
        count = rd64(rec + 32);
        cdSize = rd64(rec + 40);
        cdOfs = rd64(rec + 48);
    }
    if (cdSize > (64u << 20) || cdOfs + cdSize > (uint64_t)fsize) goto done;
    cd = (unsigned char*)malloc((size_t)cdSize + 1);
    if (!cd || fseeko(f, (off_t)cdOfs, SEEK_SET) != 0 || fread(cd, 1, (size_t)cdSize, f) != (size_t)cdSize) goto done;

    uint64_t p = 0;
    char name[1024], rel[2048];
    for (uint64_t i = 0; i < count; i++) {
        if (p + 46 > cdSize || rd32(cd + p) != 0x02014b50) goto done;
        uint16_t flags = rd16(cd + p + 8);
        uint16_t method = rd16(cd + p + 10);
        uint32_t crc = rd32(cd + p + 16);
        uint64_t csz = rd32(cd + p + 20);
        uint64_t usz = rd32(cd + p + 24);
        uint16_t nlen = rd16(cd + p + 28);
        uint16_t xlen = rd16(cd + p + 30);
        uint16_t clen = rd16(cd + p + 32);
        uint64_t lho = rd32(cd + p + 42);
        if (p + 46 + nlen + xlen + clen > cdSize) goto done;
        const unsigned char* x = cd + p + 46 + nlen;
        for (uint32_t xo = 0; xo + 4 <= xlen;) {
            uint16_t id = rd16(x + xo), len = rd16(x + xo + 2);
            if (xo + 4 + len > xlen) break;
            if (id == 0x0001) {
                const unsigned char* z = x + xo + 4;
                uint32_t zo = 0;
                if (usz == 0xFFFFFFFFu && zo + 8 <= len) { usz = rd64(z + zo); zo += 8; }
                if (csz == 0xFFFFFFFFu && zo + 8 <= len) { csz = rd64(z + zo); zo += 8; }
                if (lho == 0xFFFFFFFFu && zo + 8 <= len) { lho = rd64(z + zo); zo += 8; }
            }
            xo += 4 + len;
        }
        if (imp_cleanZipName((const char*)cd + p + 46, nlen, name, sizeof(name))) {
            snprintf(rel, sizeof(rel), "%s%s%s", prefix, prefix[0] ? "/" : "", name);
            impEntry* e = imp_add(idx, rel, path, (int64_t)usz);
            if (e) {
                e->bZip = 1;
                e->zMethod = (method == 0 || method == 8) ? method : -1;
                e->bEncrypted = (flags & 1) != 0;
                e->zOffset = lho;
                e->zComp = csz;
                e->zCrc = crc;
            }
        }
        p += 46 + nlen + xlen + clen;
    }
    ok = 1;
done:
    free(tail);
    free(cd);
    fclose(f);
    return ok;
}

int iosImport_AddItem(iosImportIndex* idx, const char* path, iosImportOpenFn pOpen, void* user)
{
    const char* base = imp_baseName(path);
    char name[512];
    snprintf(name, sizeof(name), "%s", base);
    struct stat st;
    int bIcloud = 0;
    size_t len = strlen(name);
    if (name[0] == '.' && len > 8 && !strcmp(name + len - 7, ".icloud")) {
        memmove(name, name + 1, len - 8);
        name[len - 8] = 0;
        bIcloud = 1;
    }
    if (!bIcloud && stat(path, &st) != 0) return 0;
    if (!bIcloud && S_ISDIR(st.st_mode)) {
        imp_walk(idx, path, name, 1);
        return 1;
    }
    if (imp_endsWithCase(name, ".zip")) {
        char real[2048];
        if (bIcloud) {
            snprintf(real, sizeof(real), "%.*s%s", (int)(base - path), path, name);
            path = real;
        }
        char prefix[512];
        snprintf(prefix, sizeof(prefix), "%.*s", (int)(strlen(name) - 4), name);
        if (imp_zipIndex(idx, path, prefix, pOpen, user)) return 1;
        snprintf(idx->badZip, sizeof(idx->badZip), "%s", name);
        return 0;
    }
    return imp_add(idx, name, path, bIcloud ? -1 : (int64_t)st.st_size) != NULL;
}

void iosImport_AddFolderContents(iosImportIndex* idx, const char* pDir, const char* const* pSkip, iosImportOpenFn pOpen, void* user)
{
    DIR* d = opendir(pDir);
    if (!d) return;
    struct dirent* de;
    char path[2048];
    while ((de = readdir(d)) != NULL) {
        const char* n = de->d_name;
        if (!strcmp(n, ".") || !strcmp(n, "..") || imp_isJunk(n)) continue;
        int bSkip = 0;
        for (const char* const* s = pSkip; s && *s; s++) {
            if (!strcasecmp(n, *s)) bSkip = 1;
        }
        if (bSkip) continue;
        snprintf(path, sizeof(path), "%s/%s", pDir, n);
        iosImport_AddItem(idx, path, pOpen, user);
    }
    closedir(d);
}

// ---- finding the game ---------------------------------------------------------

static int imp_cmpLower(const void* a, const void* b)
{
    return strcmp(((const impEntry*)a)->lower, ((const impEntry*)b)->lower);
}

static impEntry* imp_find(iosImportIndex* idx, const char* lower)
{
    if (idx->n == 0) return NULL;
    impEntry key;
    key.lower = (char*)lower;
    return (impEntry*)bsearch(&key, idx->e, idx->n, sizeof(impEntry), imp_cmpLower);
}

// Is there a file at root/rel (any case)?
static int imp_hasFile(iosImportIndex* idx, const char* root, const char* rel)
{
    char buf[2048];
    snprintf(buf, sizeof(buf), "%s%s%s", root, root[0] ? "/" : "", rel);
    imp_lower(buf);
    return imp_find(idx, buf) != NULL;
}

// Is there a file at root/rel, or a folder with files in it?
static int imp_hasPath(iosImportIndex* idx, const char* root, const char* rel)
{
    if (imp_hasFile(idx, root, rel)) return 1;
    char buf[2048];
    snprintf(buf, sizeof(buf), "%s%s%s/", root, root[0] ? "/" : "", rel);
    imp_lower(buf);
    size_t n = strlen(buf);
    for (int i = 0; i < idx->n; i++) {
        if (!strncmp(idx->e[i].lower, buf, n)) return 1;
    }
    return 0;
}

// A required item: a file, or with a trailing '/' a folder with files in it
static int imp_hasReq(iosImportIndex* idx, const char* root, const char* req)
{
    size_t n = strlen(req);
    if (n && req[n - 1] == '/') {
        char dir[512];
        snprintf(dir, sizeof(dir), "%.*s", (int)(n - 1), req);
        return imp_hasPath(idx, root, dir);
    }
    return imp_hasFile(idx, root, req);
}

// Does pDir have an item with this name (any case)?
static int imp_dirHas(const char* pDir, const char* name)
{
    DIR* d = opendir(pDir);
    if (!d) return 0;
    struct dirent* de;
    int bFound = 0;
    while (!bFound && (de = readdir(d)) != NULL) {
        if (!strcasecmp(de->d_name, name)) bFound = 1;
    }
    closedir(d);
    return bFound;
}

static int imp_depth(const char* s)
{
    if (!s[0]) return 0;
    int d = 1;
    for (; *s; s++) d += (*s == '/');
    return d;
}

// The folders ("roots") whose root/pReq exists: each entry ending in it
static void imp_rootOf(const impEntry* e, const char* reqLower, char* out, size_t out_sz)
{
    size_t a = strlen(e->lower), b = strlen(reqLower);
    size_t rootLen = a - b;
    if (rootLen > 0) rootLen--; // the '/'
    snprintf(out, out_sz, "%.*s", (int)rootLen, e->rel);
}

static int imp_endsWithPath(const char* lower, const char* reqLower)
{
    size_t a = strlen(lower), b = strlen(reqLower);
    if (a < b || strcmp(lower + a - b, reqLower)) return 0;
    return a == b || lower[a - b - 1] == '/';
}

void iosImport_Plan(iosImportIndex* idx, const iosImportGame* game, const char* pDest, iosImportPlan* plan)
{
    memset(plan, 0, sizeof(*plan));
    if (idx->n > 0) qsort(idx->e, idx->n, sizeof(impEntry), imp_cmpLower);
    for (int i = 0; i < idx->n; i++) idx->e[i].bUse = 0;

    int nReq = 0;
    while (game->required[nReq]) nReq++;

    // Every folder that holds at least one required file is a candidate; the
    // game is the shallowest one holding all of them. The best partial match
    // says what's missing.
    char best[1024] = "", cand[1024], req[512];
    int bestCount = 0, bestDepth = 1 << 30, bFull = 0;
    for (int r = 0; r < nReq; r++) {
        snprintf(req, sizeof(req), "%s", game->required[r]);
        imp_lower(req);
        if (req[0] == 0 || req[strlen(req) - 1] == '/') continue; // folders don't place the game
        for (int i = 0; i < idx->n; i++) {
            if (!imp_endsWithPath(idx->e[i].lower, req)) continue;
            imp_rootOf(&idx->e[i], req, cand, sizeof(cand));
            int count = 0;
            for (int k = 0; k < nReq; k++) count += imp_hasReq(idx, cand, game->required[k]);
            int depth = imp_depth(cand);
            if (count > bestCount || (count == bestCount && depth < bestDepth)) {
                bestCount = count;
                bestDepth = depth;
                snprintf(best, sizeof(best), "%s", cand);
            }
        }
    }
    bFull = nReq > 0 && bestCount == nReq;

    if (!bFull) {
        int bOther = 0;
        if (game->otherMarker) {
            snprintf(req, sizeof(req), "%s", game->otherMarker);
            imp_lower(req);
            for (int i = 0; i < idx->n && !bOther; i++) bOther = imp_endsWithPath(idx->e[i].lower, req);
        }
        if (bOther) {
            plan->status = IOSIMPORT_WRONG_GAME;
        } else if (bestCount > 0) {
            plan->status = IOSIMPORT_PARTIAL;
            snprintf(plan->root, sizeof(plan->root), "%s", best);
            for (int k = 0; k < nReq && plan->missingCount < IOSIMPORT_MAX_MISSING; k++) {
                if (!imp_hasReq(idx, best, game->required[k])) plan->missing[plan->missingCount++] = game->required[k];
            }
        } else if (idx->badZip[0]) {
            plan->status = IOSIMPORT_BAD_ZIP;
            snprintf(plan->badZip, sizeof(plan->badZip), "%s", idx->badZip);
        } else {
            plan->status = IOSIMPORT_NOTHING;
        }
        return;
    }

    snprintf(plan->root, sizeof(plan->root), "%s", best);
    char rootLower[1100];
    snprintf(rootLower, sizeof(rootLower), "%s%s", best, best[0] ? "/" : "");
    imp_lower(rootLower);
    size_t rootLen = strlen(rootLower);

    plan->bAllLocal = 1;
    for (int i = 0; i < idx->n; i++) {
        impEntry* e = &idx->e[i];
        if (strncmp(e->lower, rootLower, rootLen)) continue;
        const char* rest = e->rel + rootLen;
        const char* slash = strchr(rest, '/');
        size_t topLen = slash ? (size_t)(slash - rest) : strlen(rest);
        char top[512];
        snprintf(top, sizeof(top), "%.*s", (int)topLen, rest);
        int bUse = 0;
        for (const char* const* c = game->copy; *c && !bUse; c++) {
            if ((*c)[0] == '*') {
                bUse = !slash && imp_endsWithCase(rest, *c + 1);
            } else {
                bUse = !strcasecmp(top, *c);
            }
        }
        for (const char* const* k = game->keep; k && *k && !bUse; k++) {
            bUse = slash && !strcasecmp(top, *k) && !(pDest && imp_dirHas(pDest, top));
        }
        if (!bUse) continue;
        if (e->bZip && (e->bEncrypted || e->zMethod < 0)) {
            plan->status = IOSIMPORT_BAD_ZIP;
            snprintf(plan->badZip, sizeof(plan->badZip), "%s", imp_baseName(e->path));
            return;
        }
        e->bUse = 1;
        e->restOfs = (int)rootLen;
        plan->fileCount++;
        if (e->size > 0) plan->totalBytes += e->size;
        if (e->bZip || e->size < 0) plan->bAllLocal = 0;
    }

    for (const char* const* o = game->optional; o && o[0] && o[1]; o += 2) {
        if (!imp_hasPath(idx, best, o[0]) && plan->missingOptionalCount < IOSIMPORT_MAX_MISSING) {
            plan->missingOptional[plan->missingOptionalCount++] = o[1];
        }
    }
    plan->status = IOSIMPORT_OK;
}

// ---- copying and installing ----------------------------------------------------

void iosImport_RemoveTree(const char* path)
{
    struct stat st;
    if (lstat(path, &st) != 0) return;
    if (S_ISDIR(st.st_mode)) {
        DIR* d = opendir(path);
        if (d) {
            struct dirent* de;
            char sub[2048];
            while ((de = readdir(d)) != NULL) {
                if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
                snprintf(sub, sizeof(sub), "%s/%s", path, de->d_name);
                iosImport_RemoveTree(sub);
            }
            closedir(d);
        }
        rmdir(path);
    } else {
        unlink(path);
    }
}

static int imp_mkdirs(const char* path)
{
    char tmp[2048];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755) == 0 || errno == EEXIST;
}

typedef struct {
    iosImportProgressFn fn;
    void* user;
    int64_t done, total, lastReport;
} impProgress;

static void imp_report(impProgress* pr, const char* name, int bForce)
{
    if (pr->fn && (bForce || pr->done - pr->lastReport >= IMP_BUF)) {
        pr->lastReport = pr->done;
        pr->fn(pr->done, pr->total, name, pr->user);
    }
}

static const char* imp_writeErr(void)
{
    return (errno == ENOSPC) ? "The iPhone ran out of space while copying." : "Couldn't save a file in the app's folder.";
}

static const char* imp_copyFile(const impEntry* e, FILE* in, const char* dst, unsigned char* buf, unsigned char* zbuf, impProgress* pr)
{
    FILE* out = fopen(dst, "wb");
    if (!out) return imp_writeErr();
    const char* err = NULL;
    const char* name = imp_baseName(e->rel);
    int64_t written = 0;

    if (!e->bZip) {
        size_t n;
        while ((n = fread(buf, 1, IMP_BUF, in)) > 0) {
            if (fwrite(buf, 1, n, out) != n) { err = imp_writeErr(); break; }
            written += (int64_t)n;
            pr->done += (int64_t)n;
            imp_report(pr, name, 0);
        }
        if (!err && ferror(in)) err = "Couldn't read one of the files. If it's in iCloud Drive, check the connection and try again.";
        if (!err && e->size >= 0 && written != e->size) err = "A file changed or was cut short while copying. Try again.";
    } else {
        unsigned char lh[30];
        if (fseeko(in, (off_t)e->zOffset, SEEK_SET) != 0 || fread(lh, 1, 30, in) != 30 || rd32(lh) != 0x04034b50
            || fseeko(in, (off_t)(e->zOffset + 30 + rd16(lh + 26) + rd16(lh + 28)), SEEK_SET) != 0) {
            err = "The .zip is damaged.";
        } else {
            uLong crc = crc32(0L, Z_NULL, 0);
            uint64_t left = e->zComp;
            if (e->zMethod == 0) {
                while (left > 0) {
                    size_t want = left > IMP_BUF ? IMP_BUF : (size_t)left;
                    size_t n = fread(buf, 1, want, in);
                    if (n == 0) { err = "The .zip is damaged or incomplete."; break; }
                    if (fwrite(buf, 1, n, out) != n) { err = imp_writeErr(); break; }
                    crc = crc32(crc, buf, (uInt)n);
                    left -= n;
                    written += (int64_t)n;
                    pr->done += (int64_t)n;
                    imp_report(pr, name, 0);
                }
            } else {
                z_stream zs;
                memset(&zs, 0, sizeof(zs));
                if (inflateInit2(&zs, -MAX_WBITS) != Z_OK) {
                    err = "Couldn't unpack the .zip.";
                } else {
                    int zr = Z_OK;
                    while (!err && zr != Z_STREAM_END) {
                        if (zs.avail_in == 0) {
                            size_t want = left > IMP_BUF ? IMP_BUF : (size_t)left;
                            size_t n = want ? fread(zbuf, 1, want, in) : 0;
                            if (n == 0) { err = "The .zip is damaged or incomplete."; break; }
                            left -= n;
                            zs.next_in = zbuf;
                            zs.avail_in = (uInt)n;
                        }
                        zs.next_out = buf;
                        zs.avail_out = IMP_BUF;
                        zr = inflate(&zs, Z_NO_FLUSH);
                        if (zr != Z_OK && zr != Z_STREAM_END) { err = "The .zip is damaged."; break; }
                        size_t n = IMP_BUF - zs.avail_out;
                        if (n && fwrite(buf, 1, n, out) != n) { err = imp_writeErr(); break; }
                        crc = crc32(crc, buf, (uInt)n);
                        written += (int64_t)n;
                        pr->done += (int64_t)n;
                        imp_report(pr, name, 0);
                    }
                    inflateEnd(&zs);
                }
            }
            if (!err && ((uint32_t)crc != e->zCrc || written != e->size)) err = "The .zip is damaged (a file inside doesn't check out).";
        }
    }
    if (fclose(out) != 0 && !err) err = imp_writeErr();
    return err;
}

// The name pDir already uses for this item (any case), or name itself
static void imp_existingName(const char* pDir, const char* name, char* out, size_t out_sz)
{
    snprintf(out, out_sz, "%s", name);
    DIR* d = opendir(pDir);
    if (!d) return;
    struct dirent* de;
    while ((de = readdir(d)) != NULL) {
        if (!strcasecmp(de->d_name, name)) {
            snprintf(out, out_sz, "%s", de->d_name);
            break;
        }
    }
    closedir(d);
}

// Moves everything in src into dst: folders are merged, a file replaces the
// file of the same name (any case), everything else in dst stays.
static const char* imp_merge(const char* src, const char* dst)
{
    if (!imp_mkdirs(dst)) return imp_writeErr();
    DIR* d = opendir(src);
    if (!d) return "Couldn't finish putting the files in place.";
    const char* err = NULL;
    struct dirent* de;
    char from[2048], to[2048], have[512];
    while (!err && (de = readdir(d)) != NULL) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
        snprintf(from, sizeof(from), "%s/%s", src, de->d_name);
        imp_existingName(dst, de->d_name, have, sizeof(have));
        snprintf(to, sizeof(to), "%s/%s", dst, have);
        struct stat sf, st;
        if (stat(from, &sf) != 0) continue;
        int bExists = stat(to, &st) == 0;
        if (S_ISDIR(sf.st_mode) && bExists && S_ISDIR(st.st_mode)) {
            err = imp_merge(from, to);
            continue;
        }
        if (bExists) iosImport_RemoveTree(to);
        if (rename(from, to) != 0) err = "Couldn't finish putting the files in place.";
    }
    closedir(d);
    return err;
}

const char* iosImport_Install(iosImportIndex* idx, const iosImportGame* game, const iosImportPlan* plan,
                              const char* pStaging, const char* pDest, int bMove,
                              iosImportOpenFn pOpen, iosImportProgressFn pProgress, void* user)
{
    (void)game;
    if (plan->status != IOSIMPORT_OK) return "Nothing to copy.";
    iosImport_RemoveTree(pStaging);
    if (!imp_mkdirs(pStaging)) return imp_writeErr();

    unsigned char* buf = (unsigned char*)malloc(IMP_BUF);
    unsigned char* zbuf = (unsigned char*)malloc(IMP_BUF);
    if (!buf || !zbuf) {
        free(buf);
        free(zbuf);
        return "Not enough memory.";
    }
    impProgress pr = { pProgress, user, 0, plan->totalBytes, 0 };
    const char* err = NULL;
    char dst[2048], dir[2048];
    for (int i = 0; i < idx->n && !err; i++) {
        impEntry* e = &idx->e[i];
        if (!e->bUse) continue;
        snprintf(dst, sizeof(dst), "%s/%s", pStaging, e->rel + e->restOfs);
        snprintf(dir, sizeof(dir), "%s", dst);
        *strrchr(dir, '/') = 0;
        if (!imp_mkdirs(dir)) { err = imp_writeErr(); break; }
        if (bMove && !e->bZip && e->size >= 0 && rename(e->path, dst) == 0) {
            pr.done += e->size;
            imp_report(&pr, imp_baseName(e->rel), 0);
            continue;
        }
        FILE* in = imp_open(e->path, pOpen, user);
        if (!in) {
            err = "Couldn't open one of the files. If it's in iCloud Drive, check the connection and try again.";
            break;
        }
        err = imp_copyFile(e, in, dst, buf, zbuf, &pr);
        fclose(in);
    }
    free(buf);
    free(zbuf);
    if (!err) {
        err = imp_merge(pStaging, pDest);
    } else if (bMove) {
        // Moved files are the player's only copy: put them in place rather
        // than throw them away with the staging folder (kept if even that fails)
        if (imp_merge(pStaging, pDest)) return err;
    }
    iosImport_RemoveTree(pStaging);
    if (!err) imp_report(&pr, "", 1);
    return err;
}
