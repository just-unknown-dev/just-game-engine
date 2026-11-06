#version 460 core
#include <flutter/runtime_effect.glsl>

// Every sprite drawn with one 2-D material (and one sheet), in a single
// drawVertices call — one draw per frame per material, however many share
// it. A quad's texture coordinates place it in a grid of slots:
//   x = column * slot width + pad + local x, y = row * slot height + pad + local y
// where local is in the frame's pixels. The slot's row of uParams says
// which frame of the sheet it draws, its tint, where it is, a seed, and its
// own value for each thing an entity overrides (uDyn names that column, or
// -1 for the material's own value, a uniform). The layout is
// Material2DShader in lib/src/subsystems/materials_2d/material_2d_shader.dart.
//
// Effects are switches (uOn*), applied in the order Material2DEffects lists
// them: the picture moved (wave, scroll), its colour changed (palette swap,
// gradient map, greyscale, tint, flash), a shine over it, then what is drawn
// around it (drop shadow, glow, outline), and dissolve over all of it.

uniform vec4 uGrid;          // slot width, slot height, slots per row, pad
uniform vec4 uSheet;         // sheet width, height; params width, height
uniform vec4 uTime;          // seconds, palette swaps, gradient stops, unused
uniform vec4 uOn0;           // wave, scroll, palette swap, gradient map
uniform vec4 uOn1;           // greyscale, tint, flash, dissolve
uniform vec4 uOn2;           // shine, outline, glow, drop shadow
uniform vec4 uWave;          // amplitude, wavelength, speed, vertical (1)
uniform vec4 uScroll;        // speed x, y; swap tolerance; gradient amount
uniform vec4 uAmounts;       // greyscale, flash, dissolve amount, dissolve edge width
uniform vec4 uTint;          // straight rgba
uniform vec4 uFlash;         // straight rgba
uniform vec4 uDissolveEdge;  // straight rgba
uniform vec4 uDissolveShine; // dissolve grain, shine width, shine angle (deg), shine sweep time
uniform vec4 uShineColour;   // straight rgba
uniform vec4 uShine2;        // shine pause, outline width, glow radius, glow strength
uniform vec4 uOutlineColour; // straight rgba
uniform vec4 uGlowColour;    // straight rgba
uniform vec4 uShadow;        // offset x, y, softness, unused
uniform vec4 uShadowColour;  // straight rgba
uniform vec4 uDyn[8];        // per overridable value: its params column, or -1
uniform vec4 uStopColours[8];
uniform vec4 uStopAt[8];     // x: where the stop sits (0-1)
uniform vec4 uSwapFrom[8];
uniform vec4 uSwapTo[8];

uniform sampler2D uSheetImage;
uniform sampler2D uParams;

out vec4 fragColor;

vec4 texel(float col, float row) {
  return texture(uParams, vec2((col + 0.5) / uSheet.z, (row + 0.5) / uSheet.w));
}

// A 16-bit number kept in a texel's red (high byte) and green (low byte).
float u16(float col, float row) {
  vec4 t = texel(col, row);
  return floor(t.r * 255.0 + 0.5) * 256.0 + floor(t.g * 255.0 + 0.5);
}

// [h], 16 bits, as a half float: sign, five bits of exponent, ten of mantissa.
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

float dynNum(float base, float col, float row) {
  return col < 0.0 ? base : half16(u16(col, row));
}

vec4 dynColour(vec4 base, float col, float row) {
  if (col < 0.0) {
    return base;
  }
  vec4 rgb = texel(col, row);
  vec4 a = texel(col + 1.0, row);
  return vec4(rgb.rgb, a.r);
}

// The frame's colour at p (frame pixels), premultiplied; clear outside it.
vec4 frameAt(vec2 p, vec4 frame) {
  if (p.x < 0.0 || p.y < 0.0 || p.x >= frame.z || p.y >= frame.w) {
    return vec4(0.0);
  }
  vec2 q = clamp(p, vec2(0.5), frame.zw - 0.5);
  return texture(uSheetImage, (frame.xy + q) / uSheet.xy);
}

float hash(vec2 c) {
  return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 premultiplied(vec4 c) {
  return vec4(c.rgb * c.a, c.a);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 cell = floor(fc / uGrid.xy);
  float row = cell.y * uGrid.z + cell.x;
  vec2 local = fc - cell * uGrid.xy - uGrid.w;
  vec4 frame = vec4(u16(0.0, row), u16(1.0, row), u16(2.0, row), u16(3.0, row));
  vec4 tintRgb = texel(4.0, row);
  vec4 tintA = texel(5.0, row);
  vec2 origin = vec2(u16(6.0, row), u16(7.0, row));
  float seed = u16(8.0, row);
  float t = uTime.x;

  // ── The picture moved ─────────────────────────────────────────────────
  vec2 p = local;
  if (uOn0.x > 0.5) {
    float amp = dynNum(uWave.x, uDyn[0].x, row);
    float len = max(dynNum(uWave.y, uDyn[0].y, row), 1.0);
    float speed = dynNum(uWave.z, uDyn[0].z, row);
    if (uWave.w > 0.5) {
      p.y += sin(((p.x + origin.x) / len + t * speed) * 6.2831853) * amp;
    } else {
      p.x += sin(((p.y + origin.y) / len + t * speed) * 6.2831853) * amp;
    }
  }
  if (uOn0.y > 0.5 && p.x >= 0.0 && p.y >= 0.0 && p.x < frame.z && p.y < frame.w) {
    vec2 speed = vec2(dynNum(uScroll.x, uDyn[0].w, row), dynNum(uScroll.y, uDyn[1].x, row));
    p = mod(p - speed * t, max(frame.zw, vec2(1.0)));
  }
  vec4 c = frameAt(p, frame);

  // ── Its colour ────────────────────────────────────────────────────────
  if (c.a > 0.0) {
    vec3 rgb = c.rgb / c.a;
    float a = c.a;
    if (uOn0.z > 0.5) {
      float tolerance = dynNum(uScroll.z, uDyn[1].y, row);
      for (int i = 0; i < 8; i++) {
        if (float(i) >= uTime.y) {
          break;
        }
        if (distance(rgb, uSwapFrom[i].rgb) <= tolerance + 0.002) {
          rgb = uSwapTo[i].rgb;
          a *= uSwapTo[i].a;
          break;
        }
      }
    }
    if (uOn0.w > 0.5) {
      float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
      vec3 g = uStopColours[0].rgb;
      for (int i = 1; i < 8; i++) {
        if (float(i) >= uTime.z) {
          break;
        }
        float at0 = uStopAt[i - 1].x;
        float at1 = uStopAt[i].x;
        if (lum >= at0) {
          float k = at1 > at0 ? clamp((lum - at0) / (at1 - at0), 0.0, 1.0) : 1.0;
          g = mix(uStopColours[i - 1].rgb, uStopColours[i].rgb, k);
        }
      }
      rgb = mix(rgb, g, dynNum(uScroll.w, uDyn[1].z, row));
    }
    if (uOn1.x > 0.5) {
      float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
      rgb = mix(rgb, vec3(grey), dynNum(uAmounts.x, uDyn[1].w, row));
    }
    if (uOn1.y > 0.5) {
      vec4 tint = dynColour(uTint, uDyn[2].x, row);
      rgb *= tint.rgb;
      a *= tint.a;
    }
    if (uOn1.z > 0.5) {
      vec4 flash = dynColour(uFlash, uDyn[2].y, row);
      rgb = mix(rgb, flash.rgb, clamp(dynNum(uAmounts.y, uDyn[2].z, row), 0.0, 1.0) * flash.a);
    }
    rgb *= tintRgb.rgb;
    c = vec4(rgb * a, a);
  }

  // ── A shine over it ───────────────────────────────────────────────────
  if (uOn2.x > 0.5 && c.a > 0.0) {
    vec4 colour = dynColour(uShineColour, uDyn[3].w, row);
    float width = max(dynNum(uDissolveShine.y, uDyn[4].x, row), 0.01);
    float angle = radians(dynNum(uDissolveShine.z, uDyn[4].y, row));
    float sweep = max(dynNum(uDissolveShine.w, uDyn[4].z, row), 0.05);
    float pause = max(dynNum(uShine2.x, uDyn[4].w, row), 0.0);
    vec2 n = p / max(frame.zw, vec2(1.0)) - 0.5;
    float along = n.x * cos(angle) + n.y * sin(angle);
    float cycle = mod(t, sweep + pause);
    if (cycle < sweep) {
      float head = mix(-0.75 - width, 0.75 + width, cycle / sweep);
      float band = 1.0 - smoothstep(0.0, width * 0.5, abs(along - head));
      c.rgb = min(c.rgb + colour.rgb * colour.a * band * c.a, vec3(c.a));
    }
  }

  // ── Around it ─────────────────────────────────────────────────────────
  vec4 under = vec4(0.0);
  if (c.a < 1.0) {
    if (uOn2.w > 0.5) {
      vec4 colour = dynColour(uShadowColour, uDyn[6].y, row);
      vec2 offset = vec2(dynNum(uShadow.x, uDyn[6].z, row), dynNum(uShadow.y, uDyn[6].w, row));
      float soft = dynNum(uShadow.z, uDyn[7].x, row);
      float shade = 0.0;
      if (soft < 0.5) {
        shade = frameAt(p - offset, frame).a;
      } else {
        for (int i = -1; i <= 1; i++) {
          for (int j = -1; j <= 1; j++) {
            shade += frameAt(p - offset + vec2(float(i), float(j)) * soft * 0.5, frame).a;
          }
        }
        shade /= 9.0;
      }
      under = premultiplied(vec4(colour.rgb, colour.a * shade));
    }
    if (uOn2.z > 0.5) {
      vec4 colour = dynColour(uGlowColour, uDyn[5].z, row);
      float radius = max(dynNum(uShine2.z, uDyn[5].w, row), 0.5);
      float strength = dynNum(uShine2.w, uDyn[6].x, row);
      float g = 0.0;
      for (int i = 0; i < 12; i++) {
        float ang = float(i) * 0.5235988;
        vec2 d = vec2(cos(ang), sin(ang));
        g += frameAt(p + d * radius, frame).a + frameAt(p + d * radius * 0.5, frame).a;
      }
      g = clamp(g / 24.0 * strength * 2.0, 0.0, 1.0);
      vec4 glow = premultiplied(vec4(colour.rgb, colour.a * g));
      under = glow + under * (1.0 - glow.a);
    }
    if (uOn2.y > 0.5) {
      vec4 colour = dynColour(uOutlineColour, uDyn[5].x, row);
      float width = dynNum(uShine2.y, uDyn[5].y, row);
      if (width > 0.0) {
        float o = 0.0;
        for (int i = 0; i < 8; i++) {
          float ang = float(i) * 0.7853982;
          o = max(o, frameAt(p + vec2(cos(ang), sin(ang)) * width, frame).a);
          o = max(o, frameAt(p + vec2(cos(ang + 0.3926991), sin(ang + 0.3926991)) * width * 0.5, frame).a);
        }
        vec4 line = premultiplied(vec4(colour.rgb, colour.a * step(0.5, o)));
        under = line + under * (1.0 - line.a);
      }
    }
  }
  vec4 result = c + under * (1.0 - c.a);

  // ── Dissolve, over all of it ──────────────────────────────────────────
  if (uOn1.w > 0.5 && result.a > 0.0) {
    float amount = dynNum(uAmounts.z, uDyn[2].w, row);
    if (amount > 0.0) {
      float grain = max(dynNum(uDissolveShine.x, uDyn[3].z, row), 1.0);
      float edge = dynNum(uAmounts.w, uDyn[3].y, row);
      float n = noise(local / grain + vec2(seed * 0.618, seed * 0.382));
      if (n < amount) {
        result = vec4(0.0);
      } else if (n < amount + edge * 0.5) {
        vec4 colour = dynColour(uDissolveEdge, uDyn[3].x, row);
        result = premultiplied(vec4(colour.rgb, colour.a * result.a));
      }
    }
  }

  fragColor = result * tintA.r;
}
