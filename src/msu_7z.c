// MSU-1 packs that come as .7z: the LZMA SDK's 7z reader, behind a few flat
// functions for msu_import.zig.
//
// 7-Zip packs a whole folder of files into one solid stream by default, and
// the SDK's own extraction decodes such a stream into memory in one go - a
// gigabyte or more for a pack of .pcm tracks. So the usual case (one LZMA,
// LZMA2 or stored coder) is decoded here a piece at a time, each file's bytes
// handed on as they come out and checked against the file's CRC. Anything
// else falls back to the SDK's in-memory decode, up to a size that's sane.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../third_party/lzma/7z.h"
#include "../third_party/lzma/7zAlloc.h"
#include "../third_party/lzma/7zCrc.h"
#include "../third_party/lzma/LzmaDec.h"
#include "../third_party/lzma/Lzma2Dec.h"

enum {
  MSU7Z_OK = 0,
  MSU7Z_NOT_FOUND = 1,
  MSU7Z_BAD_ARCHIVE = 2,
  MSU7Z_UNSUPPORTED = 3,
  MSU7Z_CORRUPT = 4,
  MSU7Z_CANCELED = 5,
  MSU7Z_NO_MEMORY = 6,
};

// The most a folder the streaming path can't take may decode to in memory.
#define MSU7Z_MAX_IN_MEMORY ((UInt64)1 << 30)

#define kLzma2 0x21
#define kLzma 0x30101
#define kCopy 0

static const ISzAlloc g_alloc = {SzAlloc, SzFree};
static const ISzAlloc g_alloc_temp = {SzAllocTemp, SzFreeTemp};

// ------------------------------------------------------------------- files

typedef struct {
  ISeekInStream vt;
  FILE *f;
} FileIn;

static int file_seek64(FILE *f, long long off, int whence) {
#ifdef _WIN32
  return _fseeki64(f, off, whence);
#else
  return fseeko(f, (off_t)off, whence);
#endif
}

static long long file_tell64(FILE *f) {
#ifdef _WIN32
  return _ftelli64(f);
#else
  return (long long)ftello(f);
#endif
}

static SRes FileIn_Read(ISeekInStreamPtr pp, void *buf, size_t *size) {
  FileIn *p = Z7_CONTAINER_FROM_VTBL(pp, FileIn, vt);
  if (*size == 0) return SZ_OK;
  *size = fread(buf, 1, *size, p->f);
  return ferror(p->f) ? SZ_ERROR_READ : SZ_OK;
}

static SRes FileIn_Seek(ISeekInStreamPtr pp, Int64 *pos, ESzSeek origin) {
  FileIn *p = Z7_CONTAINER_FROM_VTBL(pp, FileIn, vt);
  int whence = origin == SZ_SEEK_SET ? SEEK_SET : origin == SZ_SEEK_CUR ? SEEK_CUR : SEEK_END;
  if (file_seek64(p->f, (long long)*pos, whence) != 0) return SZ_ERROR_READ;
  *pos = (Int64)file_tell64(p->f);
  return SZ_OK;
}

// ----------------------------------------------------------------- archive

typedef struct Msu7z {
  FileIn file;
  CLookToRead2 look;
  CSzArEx db;
} Msu7z;

#define kLookBufSize ((size_t)1 << 18)

static int map_res(SRes r) {
  switch (r) {
    case SZ_OK: return MSU7Z_OK;
    case SZ_ERROR_MEM: return MSU7Z_NO_MEMORY;
    case SZ_ERROR_UNSUPPORTED: return MSU7Z_UNSUPPORTED;
    case SZ_ERROR_CRC:
    case SZ_ERROR_DATA:
    case SZ_ERROR_INPUT_EOF: return MSU7Z_CORRUPT;
    default: return MSU7Z_BAD_ARCHIVE;
  }
}

Msu7z *msu7z_open(const char *path, int *err) {
  static int crc_ready = 0;
  if (!crc_ready) {
    CrcGenerateTable();
    crc_ready = 1;
  }
  Msu7z *a = (Msu7z *)calloc(1, sizeof(Msu7z));
  if (!a) {
    *err = MSU7Z_NO_MEMORY;
    return NULL;
  }
  a->file.vt.Read = FileIn_Read;
  a->file.vt.Seek = FileIn_Seek;
  a->file.f = fopen(path, "rb");
  if (!a->file.f) {
    free(a);
    *err = MSU7Z_NOT_FOUND;
    return NULL;
  }
  LookToRead2_CreateVTable(&a->look, False);
  a->look.buf = (Byte *)malloc(kLookBufSize);
  if (!a->look.buf) {
    fclose(a->file.f);
    free(a);
    *err = MSU7Z_NO_MEMORY;
    return NULL;
  }
  a->look.bufSize = kLookBufSize;
  a->look.realStream = &a->file.vt;
  LookToRead2_INIT(&a->look)
  SzArEx_Init(&a->db);
  SRes r = SzArEx_Open(&a->db, &a->look.vt, &g_alloc, &g_alloc_temp);
  if (r != SZ_OK) {
    SzArEx_Free(&a->db, &g_alloc);
    free(a->look.buf);
    fclose(a->file.f);
    free(a);
    *err = map_res(r);
    if (*err == MSU7Z_CORRUPT || *err == MSU7Z_OK) *err = MSU7Z_BAD_ARCHIVE;
    return NULL;
  }
  *err = MSU7Z_OK;
  return a;
}

void msu7z_close(Msu7z *a) {
  if (!a) return;
  SzArEx_Free(&a->db, &g_alloc);
  free(a->look.buf);
  fclose(a->file.f);
  free(a);
}

unsigned msu7z_count(const Msu7z *a) { return a->db.NumFiles; }

int msu7z_is_dir(const Msu7z *a, unsigned i) { return SzArEx_IsDir(&a->db, i) ? 1 : 0; }

unsigned long long msu7z_size(const Msu7z *a, unsigned i) { return SzArEx_GetFileSize(&a->db, i); }

// File i's path in the archive, as UTF-8 with / between folders. Returns its
// length, or 0 when it doesn't fit in `cap` (with room for a terminator).
size_t msu7z_name(const Msu7z *a, unsigned i, char *out, size_t cap) {
  UInt16 buf[1024];
  size_t len = SzArEx_GetFileNameUtf16(&a->db, i, NULL);
  if (len == 0 || len > 1024) return 0;
  SzArEx_GetFileNameUtf16(&a->db, i, buf);
  size_t n = 0;
  for (size_t k = 0; k < len && buf[k]; k++) {
    unsigned cp = buf[k];
    if (cp >= 0xd800 && cp < 0xdc00 && k + 1 < len && buf[k + 1] >= 0xdc00 && buf[k + 1] < 0xe000) {
      cp = 0x10000 + ((cp - 0xd800) << 10) + (buf[k + 1] - 0xdc00);
      k++;
    }
    if (cp == '\\') cp = '/';
    char enc[4];
    size_t m;
    if (cp < 0x80) {
      enc[0] = (char)cp;
      m = 1;
    } else if (cp < 0x800) {
      enc[0] = (char)(0xc0 | (cp >> 6));
      enc[1] = (char)(0x80 | (cp & 0x3f));
      m = 2;
    } else if (cp < 0x10000) {
      enc[0] = (char)(0xe0 | (cp >> 12));
      enc[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
      enc[2] = (char)(0x80 | (cp & 0x3f));
      m = 3;
    } else {
      enc[0] = (char)(0xf0 | (cp >> 18));
      enc[1] = (char)(0x80 | ((cp >> 12) & 0x3f));
      enc[2] = (char)(0x80 | ((cp >> 6) & 0x3f));
      enc[3] = (char)(0x80 | (cp & 0x3f));
      m = 4;
    }
    if (n + m + 1 > cap) return 0;
    memcpy(out + n, enc, m);
    n += m;
  }
  out[n] = 0;
  return n;
}

// -------------------------------------------------------------- extraction

// Handed each wanted file's bytes in order: `len` of them at `data`, and
// `last` set with the final piece (which may be empty). Returns nonzero to
// stop the extraction.
typedef int (*Msu7zSink)(void *ctx, unsigned index, const void *data, size_t len, int last);

// Splits a folder's decoded bytes among its files.
typedef struct {
  const Msu7z *a;
  const unsigned char *want;
  Msu7zSink sink;
  void *ctx;
  UInt32 file;       // the file the next bytes belong to
  UInt64 left;       // how many more bytes it has
  UInt32 crc;        // its CRC so far
  int failed;        // MSU7Z_* once something's gone wrong
} Splitter;

// Moves on to the next file in the folder with any bytes, telling the sink
// about empty wanted ones on the way.
static void next_file(Splitter *s, UInt32 folder) {
  const CSzArEx *db = &s->a->db;
  while (s->failed == MSU7Z_OK && s->file < db->NumFiles) {
    if (db->FileToFolder[s->file] != folder) {
      s->file++;
      continue;
    }
    s->left = SzArEx_GetFileSize(db, s->file);
    s->crc = CRC_INIT_VAL;
    if (s->left != 0) return;
    if (s->want[s->file] && s->sink(s->ctx, s->file, NULL, 0, 1)) s->failed = MSU7Z_CANCELED;
    s->file++;
  }
}

static int split(Splitter *s, UInt32 folder, const Byte *data, size_t len) {
  const CSzArEx *db = &s->a->db;
  while (len != 0 && s->failed == MSU7Z_OK) {
    if (s->file >= db->NumFiles) return s->failed = MSU7Z_CORRUPT;
    size_t n = len < s->left ? len : (size_t)s->left;
    int wanted = s->want[s->file];
    if (wanted) s->crc = CrcUpdate(s->crc, data, n);
    s->left -= n;
    int last = s->left == 0;
    if (last && wanted && SzBitWithVals_Check(&db->CRCs, s->file) && CRC_GET_DIGEST(s->crc) != db->CRCs.Vals[s->file])
      return s->failed = MSU7Z_CORRUPT;
    if (wanted && s->sink(s->ctx, s->file, data, n, last)) return s->failed = MSU7Z_CANCELED;
    data += n;
    len -= n;
    if (last) {
      s->file++;
      next_file(s, folder);
    }
  }
  return s->failed;
}

// Decodes folder `f` (a single LZMA, LZMA2 or stored coder) a piece at a
// time. Returns MSU7Z_UNSUPPORTED for anything else, before reading a byte.
static int stream_folder(Msu7z *a, UInt32 f, Splitter *s) {
  const CSzAr *ar = &a->db.db;
  CSzFolder folder;
  CSzData sd;
  const Byte *coders = ar->CodersData + ar->FoCodersOffsets[f];
  sd.Data = coders;
  sd.Size = ar->FoCodersOffsets[f + 1] - ar->FoCodersOffsets[f];
  if (SzGetNextFolderItem(&folder, &sd) != SZ_OK) return MSU7Z_BAD_ARCHIVE;
  if (folder.NumCoders != 1 || folder.NumPackStreams != 1) return MSU7Z_UNSUPPORTED;
  const CSzCoderInfo *coder = &folder.Coders[0];
  UInt32 method = coder->MethodID;
  if (method != kLzma && method != kLzma2 && method != kCopy) return MSU7Z_UNSUPPORTED;
  const Byte *props = coders + coder->PropsOffset;

  UInt32 pack = ar->FoStartPackStreamIndex[f];
  UInt64 in_left = ar->PackPositions[pack + 1] - ar->PackPositions[pack];
  UInt64 out_left = SzAr_GetFolderUnpackSize(ar, f);
  // Where its packed data starts (7z.h declares SzArEx_GetFolderStreamPos
  // for this, but the SDK doesn't define it).
  if (LookInStream_SeekTo(&a->look.vt, a->db.dataPos + ar->PackPositions[pack]) != SZ_OK) return MSU7Z_CORRUPT;

  CLzmaDec lzma;
  CLzma2Dec lzma2;
  LzmaDec_CONSTRUCT(&lzma)
  Lzma2Dec_CONSTRUCT(&lzma2)
  if (method == kLzma) {
    if (LzmaDec_Allocate(&lzma, props, coder->PropsSize, &g_alloc) != SZ_OK) return MSU7Z_NO_MEMORY;
    LzmaDec_Init(&lzma);
  } else if (method == kLzma2) {
    if (coder->PropsSize != 1 || Lzma2Dec_Allocate(&lzma2, props[0], &g_alloc) != SZ_OK) return MSU7Z_NO_MEMORY;
    Lzma2Dec_Init(&lzma2);
  }

  enum { kOut = 1 << 16 };
  Byte *out = (Byte *)malloc(kOut);
  int rc = out ? MSU7Z_OK : MSU7Z_NO_MEMORY;
  s->file = a->db.FolderToFile[f];
  next_file(s, f);
  while (rc == MSU7Z_OK && out_left != 0 && s->failed == MSU7Z_OK) {
    const void *in = NULL;
    size_t look = kLookBufSize;
    if (look > in_left) look = (size_t)in_left;
    if (look == 0 && method == kCopy) {
      rc = MSU7Z_CORRUPT;
      break;
    }
    if (ILookInStream_Look(&a->look.vt, &in, &look) != SZ_OK) {
      rc = MSU7Z_CORRUPT;
      break;
    }
    SizeT in_used = look;
    SizeT out_len = kOut;
    if (out_len > out_left) out_len = (SizeT)out_left;
    if (method == kCopy) {
      if (in_used > out_len) in_used = out_len;
      out_len = in_used;
      memcpy(out, in, out_len);
    } else {
      ELzmaStatus status;
      SRes r = method == kLzma
          ? LzmaDec_DecodeToBuf(&lzma, out, &out_len, (const Byte *)in, &in_used, LZMA_FINISH_ANY, &status)
          : Lzma2Dec_DecodeToBuf(&lzma2, out, &out_len, (const Byte *)in, &in_used, LZMA_FINISH_ANY, &status);
      if (r != SZ_OK || (in_used == 0 && out_len == 0)) {
        rc = MSU7Z_CORRUPT;
        break;
      }
    }
    ILookInStream_Skip(&a->look.vt, in_used);
    in_left -= in_used;
    out_left -= out_len;
    rc = split(s, f, out, out_len);
  }
  free(out);
  LzmaDec_Free(&lzma, &g_alloc);
  Lzma2Dec_Free(&lzma2, &g_alloc);
  if (rc == MSU7Z_OK) rc = s->failed;
  return rc;
}

// The fallback: the whole folder into memory with the SDK, then split.
static int decode_folder(Msu7z *a, UInt32 f, Splitter *s) {
  UInt64 size = SzAr_GetFolderUnpackSize(&a->db.db, f);
  if (size > MSU7Z_MAX_IN_MEMORY) return MSU7Z_UNSUPPORTED;
  Byte *buf = (Byte *)malloc(size ? (size_t)size : 1);
  if (!buf) return MSU7Z_NO_MEMORY;
  SRes r = SzAr_DecodeFolder(&a->db.db, f, &a->look.vt, a->db.dataPos, buf, (size_t)size, &g_alloc);
  int rc = map_res(r);
  if (rc == MSU7Z_OK) {
    s->file = a->db.FolderToFile[f];
    next_file(s, f);
    rc = split(s, f, buf, (size_t)size);
  }
  free(buf);
  return rc;
}

// Hands the wanted files (want[i] nonzero) to `sink`, in the archive's
// order. Folders with nothing wanted in them aren't decoded at all.
int msu7z_extract(Msu7z *a, const unsigned char *want, Msu7zSink sink, void *ctx) {
  const CSzArEx *db = &a->db;
  // Wanted files with nothing in them, which no folder holds.
  for (UInt32 i = 0; i < db->NumFiles; i++) {
    if (want[i] && db->FileToFolder[i] == (UInt32)-1 && !SzArEx_IsDir(db, i))
      if (sink(ctx, i, NULL, 0, 1)) return MSU7Z_CANCELED;
  }
  for (UInt32 f = 0; f < db->db.NumFolders; f++) {
    int any = 0;
    for (UInt32 i = db->FolderToFile[f]; i < db->NumFiles && i < db->FolderToFile[f + 1]; i++)
      if (want[i] && db->FileToFolder[i] == f) any = 1;
    if (!any) continue;
    Splitter s = {a, want, sink, ctx, 0, 0, 0, MSU7Z_OK};
    int rc = stream_folder(a, f, &s);
    // Unsupported is only ever said before a byte's been read.
    if (rc == MSU7Z_UNSUPPORTED) {
      Splitter t = {a, want, sink, ctx, 0, 0, 0, MSU7Z_OK};
      rc = decode_folder(a, f, &t);
    }
    if (rc != MSU7Z_OK) return rc;
  }
  return MSU7Z_OK;
}
