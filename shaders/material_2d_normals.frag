#version 460 core
#include <flutter/runtime_effect.glsl>

// The normals of sprites drawn with one 2-D material, for 2-D lighting: the
// same slot grid as material_2d.frag, each sprite's shape from its sheet
// and its normals from the material's normal map (flat without one) —
// repeated across the sheet where the map is smaller, a texture that tiles —
// turned from the sprite's own space into the world's (by its turn and
// mirroring, slot columns 9-12) and written as red, green = the normal's
// x, y (0-1 for -1 to 1), blue = how emissive it is, alpha = where it is.
// Normal maps are OpenGL-style: green is up.

uniform vec4 uGrid;   // slot width, slot height, slots per row, pad
uniform vec4 uSheet;  // sheet width, height; params width, height
uniform vec4 uMode;   // has a normal map (1), strength, emissive amount, seconds
uniform vec4 uOn;     // wave, scroll, green down (DirectX, 1), unused
uniform vec4 uWave;   // amplitude, wavelength, speed, vertical (1)
uniform vec4 uScroll; // speed x, y, unused, unused
uniform vec4 uMap;    // normal map width, height, unused, unused

uniform sampler2D uSheetImage;
uniform sampler2D uParams;
uniform sampler2D uNormalMap;

out vec4 fragColor;

vec4 texel(float col, float row) {
  return texture(uParams, vec2((col + 0.5) / uSheet.z, (row + 0.5) / uSheet.w));
}

float u16(float col, float row) {
  vec4 t = texel(col, row);
  return floor(t.r * 255.0 + 0.5) * 256.0 + floor(t.g * 255.0 + 0.5);
}

float half16(float h) {
  float s = 1.0;
  if (h >= 32768.0) {
    s = -1.0;
    h -= 32768.0;
  }
  float e = floor(h / 1024.0);
  float m = h - e * 1024.0;
  if (e < 0.5) {
    return s * m * exp2(-24.0);
  }
  return s * (1.0 + m / 1024.0) * exp2(e - 15.0);
}

vec4 frameAt(vec2 p, vec4 frame) {
  if (p.x < 0.0 || p.y < 0.0 || p.x >= frame.z || p.y >= frame.w) {
    return vec4(0.0);
  }
  vec2 q = clamp(p, vec2(0.5), frame.zw - 0.5);
  return texture(uSheetImage, (frame.xy + q) / uSheet.xy);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 cell = floor(fc / uGrid.xy);
  float row = cell.y * uGrid.z + cell.x;
  vec2 local = fc - cell * uGrid.xy - uGrid.w;
  vec4 frame = vec4(u16(0.0, row), u16(1.0, row), u16(2.0, row), u16(3.0, row));
  float alpha = texel(5.0, row).r;
  vec2 origin = vec2(u16(6.0, row), u16(7.0, row));
  float t = uMode.w;

  vec2 p = local;
  if (uOn.x > 0.5) {
    float len = max(uWave.y, 1.0);
    if (uWave.w > 0.5) {
      p.y += sin(((p.x + origin.x) / len + t * uWave.z) * 6.2831853) * uWave.x;
    } else {
      p.x += sin(((p.y + origin.y) / len + t * uWave.z) * 6.2831853) * uWave.x;
    }
  }
  if (uOn.y > 0.5 && p.x >= 0.0 && p.y >= 0.0 && p.x < frame.z && p.y < frame.w) {
    p = mod(p - uScroll.xy * t, max(frame.zw, vec2(1.0)));
  }
  vec4 c = frameAt(p, frame);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 n = vec3(0.0, 0.0, 1.0);
  if (uMode.x > 0.5) {
    // Where the sheet's pixel is in the map: the same place, or — a smaller
    // map — the place it repeats to.
    vec2 q = clamp(p, vec2(0.5), frame.zw - 0.5);
    vec2 size = max(uMap.xy, vec2(1.0));
    vec4 m = texture(uNormalMap, mod(frame.xy + q, size) / size);
    vec3 e = m.a > 0.0 ? m.rgb / m.a : vec3(0.5, 0.5, 1.0);
    // Green up (OpenGL), unless the map has it down (DirectX).
    float up = uOn.z > 0.5 ? 1.0 : -1.0;
    vec3 own = vec3(e.x * 2.0 - 1.0, up * (e.y * 2.0 - 1.0), e.z * 2.0 - 1.0);
    own.xy *= uMode.y;
    // The sprite's space to the world's: [a c; b d]. Normals go by its
    // inverse transpose, which keeps a mirrored sprite's facing right.
    float a = half16(u16(9.0, row));
    float b = half16(u16(10.0, row));
    float cc = half16(u16(11.0, row));
    float d = half16(u16(12.0, row));
    float det = a * d - b * cc;
    vec2 w = vec2(d * own.x - b * own.y, -cc * own.x + a * own.y) * (det < 0.0 ? -1.0 : 1.0);
    float lw = length(w);
    if (lw > 0.0) {
      w = w / lw * length(own.xy);
    }
    n = normalize(vec3(w, max(own.z, 0.001)));
  }
  float a2 = c.a * alpha;
  fragColor = vec4(vec3(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, uMode.z) * a2, a2);
}
