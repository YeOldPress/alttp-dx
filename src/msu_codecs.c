// MSU tracks as FLAC or Ogg Vorbis: dr_flac and stb_vorbis, behind a few flat
// functions so the Zig side never has to mirror either library's structs.
//
// A track's loop point rides along as a LOOPSTART tag (in samples), the way
// game music rips and loop tools write it; LOOP_START is taken as well.

#define DR_FLAC_IMPLEMENTATION
#include "../third_party/dr_libs/dr_flac.h"

#define STB_VORBIS_NO_PUSHDATA_API
#include "../third_party/stb/stb_vorbis.c"

#include <string.h>

typedef struct MsuCodecInfo {
  unsigned rate;
  unsigned channels;
  unsigned long long frames;
  // -1 when the track has no loop tag.
  long long loop_start;
} MsuCodecInfo;

// Reads "LOOPSTART=1234" (any case, or LOOP_START) into *out.
static void msu_loop_tag(const char *s, size_t len, long long *out) {
  static const char *const names[] = {"LOOPSTART=", "LOOP_START="};
  for (size_t n = 0; n < 2; n++) {
    size_t k = strlen(names[n]);
    if (len <= k) continue;
    size_t i = 0;
    while (i < k) {
      char ch = s[i];
      if (ch >= 'a' && ch <= 'z') ch -= 32;
      if (ch != names[n][i]) break;
      i++;
    }
    if (i != k) continue;
    long long v = 0;
    for (; i < len && s[i] >= '0' && s[i] <= '9'; i++) {
      v = v * 10 + (s[i] - '0');
      if (v > 0xffffffffLL) return;
    }
    if (i == k) return;
    *out = v;
    return;
  }
}

// ---------------------------------------------------------------------- FLAC

static void msu_flac_meta(void *ud, drflac_metadata *m) {
  if (m->type != DRFLAC_METADATA_BLOCK_TYPE_VORBIS_COMMENT) return;
  drflac_vorbis_comment_iterator it;
  drflac_init_vorbis_comment_iterator(&it, m->data.vorbis_comment.commentCount, m->data.vorbis_comment.pComments);
  drflac_uint32 len;
  const char *s;
  while ((s = drflac_next_vorbis_comment(&it, &len)) != NULL)
    msu_loop_tag(s, len, (long long *)ud);
}

void *msu_flac_open(const char *path, MsuCodecInfo *info) {
  long long loop = -1;
  drflac *f = drflac_open_file_with_metadata(path, msu_flac_meta, &loop, NULL);
  if (!f) return NULL;
  info->rate = f->sampleRate;
  info->channels = f->channels;
  info->frames = f->totalPCMFrameCount;
  info->loop_start = loop;
  return f;
}

int msu_flac_seek(void *h, unsigned long long frame) {
  return drflac_seek_to_pcm_frame((drflac *)h, frame) ? 1 : 0;
}

unsigned long long msu_flac_read(void *h, short *out, unsigned long long frames) {
  return drflac_read_pcm_frames_s16((drflac *)h, frames, out);
}

void msu_flac_close(void *h) {
  drflac_close((drflac *)h);
}

// ----------------------------------------------------------------- Ogg Vorbis

void *msu_ogg_open(const char *path, MsuCodecInfo *info) {
  int err = 0;
  stb_vorbis *v = stb_vorbis_open_filename(path, &err, NULL);
  if (!v) return NULL;
  stb_vorbis_info vi = stb_vorbis_get_info(v);
  info->rate = vi.sample_rate;
  info->channels = (unsigned)vi.channels;
  info->frames = stb_vorbis_stream_length_in_samples(v);
  info->loop_start = -1;
  stb_vorbis_comment vc = stb_vorbis_get_comment(v);
  for (int i = 0; i < vc.comment_list_length; i++)
    msu_loop_tag(vc.comment_list[i], strlen(vc.comment_list[i]), &info->loop_start);
  return v;
}

int msu_ogg_seek(void *h, unsigned long long frame) {
  if (frame > 0xffffffffULL) return 0;
  return stb_vorbis_seek((stb_vorbis *)h, (unsigned)frame) ? 1 : 0;
}

// Always stereo out: stb_vorbis mixes whatever the file has down (or up) to
// the two channels asked for.
unsigned long long msu_ogg_read(void *h, short *out, unsigned long long frames) {
  unsigned long long got = 0;
  while (got < frames) {
    unsigned long long want = frames - got;
    if (want > 4096) want = 4096;
    int n = stb_vorbis_get_samples_short_interleaved((stb_vorbis *)h, 2, out + got * 2, (int)(want * 2));
    if (n <= 0) break;
    got += (unsigned long long)n;
  }
  return got;
}

void msu_ogg_close(void *h) {
  stb_vorbis_close((stb_vorbis *)h);
}
