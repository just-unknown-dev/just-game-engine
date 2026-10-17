#version 460 core
#include <flutter/runtime_effect.glsl>

// A screen material (a 2-D material of the `screen` kind): the frame drawn
// into an image, painted back over the whole view through this. Effects
// are switches, applied in the order Material2DEffects lists them: the
// picture moved (pixelate, CRT bulge and fringes), its colour changed
// (grade, gradient map, greyscale), then lines and a vignette over it. The
// layout is ScreenMaterialPass in lib/src/subsystems/materials_2d/.

uniform vec4 uSize;            // view width, height (logical px), seconds, unused
uniform vec4 uOn0;             // pixelate, crt, grade, gradient map
uniform vec4 uOn1;             // greyscale, scanlines, vignette, unused
uniform vec4 uPixel;           // pixel size, curvature, fringe (px), unused
uniform vec4 uGrade;           // brightness, contrast, saturation, hue (deg)
uniform vec4 uGradeTint;       // straight rgba
uniform vec4 uAmounts;         // gradient amount, greyscale, scanline amount, scanline spacing
uniform vec4 uVignette;        // amount, softness, gradient stops, unused
uniform vec4 uVignetteColour;  // straight rgba
uniform vec4 uStopColours[8];
uniform vec4 uStopAt[8];

uniform sampler2D uFrame;

out vec4 fragColor;

vec3 hueShift(vec3 c, float a) {
  vec3 k = vec3(0.57735027);
  float cosA = cos(a);
  return c * cosA + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cosA);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 size = max(uSize.xy, vec2(1.0));
  vec2 uv = fc / size;

  if (uOn0.y > 0.5) {
    vec2 c = uv * 2.0 - 1.0;
    c *= 1.0 + uPixel.y * 0.25 * dot(c, c);
    uv = c * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
      fragColor = vec4(0.0, 0.0, 0.0, 1.0);
      return;
    }
  }
  vec2 p = uv * size;
  if (uOn0.x > 0.5) {
    float s = max(uPixel.x, 1.0);
    p = (floor(p / s) + 0.5) * s;
  }
  vec4 c = texture(uFrame, p / size);
  if (uOn0.y > 0.5 && uPixel.z > 0.0) {
    vec2 off = vec2(uPixel.z * (uv.x - 0.5) * 2.0, 0.0);
    c.r = texture(uFrame, (p + off) / size).r;
    c.b = texture(uFrame, (p - off) / size).b;
  }

  vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;
  vec3 weights = vec3(0.299, 0.587, 0.114);
  if (uOn0.z > 0.5) {
    rgb += uGrade.x;
    rgb = (rgb - 0.5) * uGrade.y + 0.5;
    rgb = mix(vec3(dot(rgb, weights)), rgb, uGrade.z);
    if (uGrade.w != 0.0) {
      rgb = hueShift(rgb, radians(uGrade.w));
    }
    rgb *= mix(vec3(1.0), uGradeTint.rgb, uGradeTint.a);
  }
  if (uOn0.w > 0.5) {
    float lum = clamp(dot(rgb, weights), 0.0, 1.0);
    vec3 g = uStopColours[0].rgb;
    for (int i = 1; i < 8; i++) {
      if (float(i) >= uVignette.z) {
        break;
      }
      float at0 = uStopAt[i - 1].x;
      float at1 = uStopAt[i].x;
      if (lum >= at0) {
        float k = at1 > at0 ? clamp((lum - at0) / (at1 - at0), 0.0, 1.0) : 1.0;
        g = mix(uStopColours[i - 1].rgb, uStopColours[i].rgb, k);
      }
    }
    rgb = mix(rgb, g, uAmounts.x);
  }
  if (uOn1.x > 0.5) {
    rgb = mix(rgb, vec3(dot(rgb, weights)), uAmounts.y);
  }
  if (uOn1.y > 0.5) {
    float spacing = max(uAmounts.w, 1.0);
    float line = 0.5 + 0.5 * cos(fc.y / spacing * 6.2831853);
    rgb *= 1.0 - uAmounts.z * line;
  }
  if (uOn1.z > 0.5) {
    float d = length(uv - 0.5) * 1.41421356;
    float edge = smoothstep(clamp(1.0 - uVignette.y, 0.0, 0.999), 1.0, d);
    rgb = mix(rgb, uVignetteColour.rgb, edge * uVignette.x * uVignetteColour.a);
  }
  rgb = clamp(rgb, 0.0, 1.0);
  fragColor = vec4(rgb * c.a, c.a);
}
