// The tools window's text: stb_truetype, with a few calls around it so the
// Zig side never has to know its structs' insides. The window turns the
// glyphs these bake into a texture and draws from that.
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "../third_party/stb/stb_truetype.h"

// Laid out as stbtt_packedchar, which the Zig side mirrors.
typedef stbtt_packedchar ToolsGlyph;

// Rasterizes `count` codepoints of the font at `px` pixels tall into an
// 8-bit `w` x `h` atlas. 1 if they all fit.
int tools_font_bake(const unsigned char *ttf, float px, unsigned char *atlas, int w, int h,
                    const int *codepoints, int count, ToolsGlyph *out) {
  stbtt_pack_context pc;
  if (!stbtt_PackBegin(&pc, atlas, w, h, 0, 1, NULL)) return 0;
  // Twice across, so glyphs placed between pixels still look even.
  stbtt_PackSetOversampling(&pc, 2, 1);
  stbtt_pack_range range = {0};
  range.font_size = px;
  range.array_of_unicode_codepoints = (int *)codepoints;
  range.num_chars = count;
  range.chardata_for_range = out;
  int ok = stbtt_PackFontRanges(&pc, ttf, 0, &range, 1);
  stbtt_PackEnd(&pc);
  return ok;
}

// The font's ascent and descent at `px` pixels tall, and how many pixels
// one of its units is at that size.
void tools_font_metrics(const unsigned char *ttf, float px, float *ascent, float *descent, float *unit) {
  stbtt_fontinfo info;
  *ascent = *descent = *unit = 0;
  if (!stbtt_InitFont(&info, ttf, 0)) return;
  int a, d, gap;
  stbtt_GetFontVMetrics(&info, &a, &d, &gap);
  float s = stbtt_ScaleForPixelHeight(&info, px);
  *ascent = a * s;
  *descent = d * s;
  *unit = s;
}

// The kerning between every pair of `count` codepoints from `first`, in font
// units, `out[a * count + b]` for a followed by b.
void tools_font_kerning(const unsigned char *ttf, int first, int count, short *out) {
  stbtt_fontinfo info;
  for (int i = 0; i < count * count; i++) out[i] = 0;
  if (!stbtt_InitFont(&info, ttf, 0)) return;
  int glyphs[128];
  if (count > 128) count = 128;
  for (int i = 0; i < count; i++) glyphs[i] = stbtt_FindGlyphIndex(&info, first + i);
  for (int a = 0; a < count; a++)
    for (int b = 0; b < count; b++)
      out[a * count + b] = (short)stbtt_GetGlyphKernAdvance(&info, glyphs[a], glyphs[b]);
}
