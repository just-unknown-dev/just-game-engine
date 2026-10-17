#version 460 core
#include <flutter/runtime_effect.glsl>

// 2-D shadows: one row per light, one column per direction round it. Each
// pixel walks its ray out from the light through the mask of what casts
// shadows (alpha) and keeps where it was first blocked, as a share of the
// light's radius (1: nothing in the way), in 16 bits over red and green. A
// light that starts inside a caster is not blocked by it until the ray
// leaves it. Read back by lighting_2d.frag.

uniform vec4 uMap;          // directions, rows, mask width, mask height (pixels)
uniform vec4 uScale;        // view pixels to mask pixels, unused x3
uniform vec4 uLights[16];   // view x, y, radius (view pixels), unused

uniform sampler2D uMask;

out vec4 fragColor;

float blocks(vec2 view) {
  vec2 p = view * uScale.x;
  if (p.x < 0.0 || p.y < 0.0 || p.x >= uMap.z || p.y >= uMap.w) {
    return 0.0;
  }
  return texture(uMask, p / uMap.zw).a;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float row = floor(fc.y);
  vec4 light = vec4(0.0);
  for (int i = 0; i < 16; i++) {
    if (float(i) == row) {
      light = uLights[i];
    }
  }
  float ang = fc.x / uMap.x * 6.2831853;
  vec2 dir = vec2(cos(ang), sin(ang));
  bool clear = blocks(light.xy) < 0.5;
  float hit = 1.0;
  for (int s = 0; s < 128; s++) {
    float t = (float(s) + 0.5) / 128.0;
    float a = blocks(light.xy + dir * t * light.z);
    if (!clear) {
      clear = a < 0.5;
    } else if (a > 0.5) {
      hit = t;
      break;
    }
  }
  float hi = floor(hit * 255.0) / 255.0;
  float lo = fract(hit * 255.0);
  fragColor = vec4(hi, lo, 0.0, 1.0);
}
