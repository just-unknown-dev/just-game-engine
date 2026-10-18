#version 460 core
#include <flutter/runtime_effect.glsl>

// 2-D lighting: the frame and its normals (material_2d_normals.frag: red,
// green = the normal's x, y; blue = how emissive; alpha = where something
// is) in, the frame lit by up to 16 lights over the ambient light out. Lit
// in the world's space: uToWorld turns a pixel of the view into a point of
// the world, where the lights are. With shadows on, a light's row of the
// shadow map (shadow_map_2d.frag) says how far it reaches each way; inside
// a shadow caster (the mask: alpha where one is, red its depth) the light
// reaches that far in, then fades. The layout is Lighting2DPass in
// lib/src/subsystems/lighting_2d/.

uniform vec4 uSize;        // view width, height (logical px), light count, show normals (1)
uniform vec4 uAmbient;     // rgb (times its strength), unused
uniform vec4 uToWorld0;    // view to world: a, b, c, d   (world = [a c; b d] * view + [e f])
uniform vec4 uToWorld1;    // e, f, unused, unused
uniform vec4 uLights[16];  // world x, y, radius, height
uniform vec4 uColours[16]; // rgb (times its intensity), falloff
uniform vec4 uSpots[16];   // direction x, y; cos(half the cone), or -2 for a point light; 1 / (cos(inner) - cos(half the cone))
uniform vec4 uShadowInfo;  // shadow map directions, rows, softness (0-1), view pixels per world unit
uniform vec4 uMaskInfo;    // mask width, height (pixels), view pixels to mask pixels, shadows on (1)
uniform vec4 uShadowLights[16]; // view x, y, radius (view px), shadow map row (or -1: no shadows)

uniform sampler2D uScene;
uniform sampler2D uNormals;
uniform sampler2D uMask;
uniform sampler2D uShadowMap;

out vec4 fragColor;

// How much of light [i]'s light reaches view pixel [fc]: 1 lit, 0 in shadow.
float reach(vec2 fc, vec4 sl, vec4 mask) {
  vec2 dv = fc - sl.xy;
  float radius = max(sl.z, 1.0);
  float rv = length(dv) / radius;
  float ang = atan(dv.y, dv.x);
  if (ang < 0.0) {
    ang += 6.2831853;
  }
  float v = (sl.w + 0.5) / max(uShadowInfo.y, 1.0);
  float soft = 0.004 + uShadowInfo.z * 0.04;
  float spread = uShadowInfo.z * 0.004;
  float sum = 0.0;
  for (int k = -2; k <= 2; k++) {
    float u = fract(ang / 6.2831853 + float(k) * spread);
    vec4 s = texture(uShadowMap, vec2(u, v));
    float blocked = s.r + s.g / 255.0;
    if (mask.a > 0.5) {
      // Inside a caster: lit for its depth past where the light came in.
      float depth = mask.r / mask.a * 64.0 * uShadowInfo.w / radius;
      sum += 1.0 - smoothstep(blocked, blocked + max(depth, 0.001), rv);
    } else {
      sum += 1.0 - smoothstep(blocked - soft, blocked + soft, rv);
    }
  }
  return sum / 5.0;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / max(uSize.xy, vec2(1.0));
  vec4 base = texture(uScene, uv);
  vec4 nb = texture(uNormals, uv);
  vec3 n = vec3(0.0, 0.0, 1.0);
  float emissive = 0.0;
  if (nb.a > 0.004) {
    vec3 e = nb.rgb / nb.a;
    n.xy = e.xy * 2.0 - 1.0;
    n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
    emissive = clamp(e.z, 0.0, 1.0);
  }
  vec2 world = vec2(
    uToWorld0.x * fc.x + uToWorld0.z * fc.y + uToWorld1.x,
    uToWorld0.y * fc.x + uToWorld0.w * fc.y + uToWorld1.y
  );
  bool shadows = uMaskInfo.w > 0.5;
  vec4 mask = vec4(0.0);
  if (shadows) {
    mask = texture(uMask, fc * uMaskInfo.z / max(uMaskInfo.xy, vec2(1.0)));
  }

  vec3 light = uAmbient.rgb;
  for (int i = 0; i < 16; i++) {
    if (float(i) >= uSize.z) {
      break;
    }
    vec4 l = uLights[i];
    vec2 d = l.xy - world;
    float r = length(d);
    if (r >= l.z) {
      continue;
    }
    float k = pow(1.0 - r / l.z, uColours[i].w);
    vec3 toLight = normalize(vec3(d, l.w));
    float ndl = max(dot(n, toLight), 0.0);
    vec4 spot = uSpots[i];
    float cone = 1.0;
    if (spot.z > -1.5 && r > 0.0) {
      float along = dot(-d / r, spot.xy);
      cone = clamp((along - spot.z) * spot.w, 0.0, 1.0);
    }
    float lit = 1.0;
    vec4 sl = uShadowLights[i];
    if (shadows && sl.w >= 0.0 && k * ndl * cone > 0.0) {
      lit = reach(fc, sl, mask);
    }
    light += uColours[i].rgb * k * ndl * cone * lit;
  }
  vec3 lit = base.rgb * mix(light, vec3(1.0), emissive);
  // Showing the normals (an editor's view of them) instead: as a normal map
  // draws them, green up, flat (0.5, 0.5, 1). Chosen here at the end, not
  // returned early: an early return with a loop crashed the OpenGL ES
  // compile on Windows.
  fragColor = uSize.w > 0.5
      ? vec4(n.x * 0.5 + 0.5, 0.5 - n.y * 0.5, n.z * 0.5 + 0.5, 1.0)
      : vec4(lit, base.a);
}
