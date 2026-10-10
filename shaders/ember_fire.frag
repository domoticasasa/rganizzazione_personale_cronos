// Sfondo scuro "fiammella" per Gestopro360 (tema scuro).
// Base grafite/blu notte, braci che salgono lente, bagliore caldo in basso e
// una scia di fuoco che segue il puntatore. Usato da
// lib/widgets/ember_fire_background.dart.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;       // pixel logici
uniform float uTime;      // secondi
uniform vec3 uMouse;      // x, y, presenza fiammella 0..1
uniform float uIntensity; // 0..1.5
// Punti della scia: x, y, eta' (s), forza (0 = spento)
uniform vec4 uP0;
uniform vec4 uP1;
uniform vec4 uP2;
uniform vec4 uP3;
uniform vec4 uP4;
uniform vec4 uP5;
uniform vec4 uP6;
uniform vec4 uP7;
uniform vec4 uP8;
uniform vec4 uP9;
uniform vec4 uP10;
uniform vec4 uP11;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * vnoise(p);
    p = p * 2.03 + vec2(17.1, 9.2);
    a *= 0.5;
  }
  return v;
}

// Calore (x) e fumo (y) di un punto della scia.
vec2 flame(vec4 q, vec2 wp) {
  if (q.w <= 0.0) {
    return vec2(0.0);
  }
  float age = q.z;
  vec2 c = q.xy + vec2(0.0, -age * 85.0);  // il fuoco sale
  vec2 d = wp - c;
  d.y *= d.y < 0.0 ? 0.55 : 1.25;          // lingua allungata verso l'alto
  float r = (14.0 + age * 42.0) * (0.75 + 0.3 * q.w);
  float g = exp(-dot(d, d) / (r * r));
  float heat = q.w * exp(-age * 3.2) * g;
  float rs = r * 1.8;
  float smoke = q.w * smoothstep(0.15, 0.9, age) * exp(-age * 1.1) *
                exp(-dot(d, d) / (rs * rs));
  return vec2(heat, smoke);
}

float embers(vec2 pos, float t, float cell, float speed, float seed) {
  vec2 p = pos / cell;
  p.y += t * speed / cell;
  vec2 id = floor(p);
  vec2 f = fract(p);
  float h = hash(id + seed);
  if (h > 0.2) {
    return 0.0;
  }
  vec2 c = vec2(hash(id + seed + 1.3), hash(id + seed + 7.1)) * 0.6 + 0.2;
  c.x += 0.12 * sin(t * 1.3 + h * 40.0);
  vec2 d = (f - c) * cell;
  float sz = 1.1 + 1.8 * hash(id + seed + 3.3);
  float dd = dot(d, d);
  float flick = 0.55 + 0.45 * sin(t * (3.0 + h * 25.0) + h * 100.0);
  return (exp(-dd / (sz * sz)) + 0.22 * exp(-dd / (sz * sz * 10.0))) * flick;
}

vec3 fireRamp(float x) {
  vec3 red = vec3(0.70, 0.12, 0.06);
  vec3 orange = vec3(1.0, 0.478, 0.102);   // #FF7A1A
  vec3 amber = vec3(1.0, 0.710, 0.278);    // #FFB547
  vec3 core = vec3(1.0, 0.93, 0.78);
  vec3 c = mix(red, orange, smoothstep(0.15, 0.55, x));
  c = mix(c, amber, smoothstep(0.55, 0.95, x));
  c = mix(c, core, smoothstep(0.95, 1.6, x));
  return c;
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  float hgt = max(uSize.y, 1.0);
  float v = pos.y / hgt;
  float t = uTime;
  float ia = clamp(uIntensity, 0.0, 1.5);

  // Base: #0A0D14 in alto -> #121826 in basso.
  vec3 col = mix(vec3(0.039, 0.051, 0.078), vec3(0.071, 0.094, 0.149), v);
  float n = fbm(vec2(pos.x / hgt * 2.2, v * 1.6 - t * 0.05));
  col += vec3(0.020, 0.028, 0.045) * n;

  // Bagliore caldo in basso, che respira piano.
  float warm = exp(-(1.0 - v) * 4.5) * (0.65 + 0.35 * fbm(vec2(pos.x / hgt * 1.5 + t * 0.04, t * 0.08)));
  col += vec3(1.0, 0.42, 0.12) * 0.11 * warm * ia;

  // Braci che salgono (due strati).
  float e = embers(pos, t, 46.0, 38.0, 0.0) * (0.25 + 0.75 * v * v) +
            embers(pos + vec2(19.0, 7.0), t, 72.0, 22.0, 5.7) * 0.6 * (0.15 + 0.85 * v);
  col += vec3(1.0, 0.55, 0.18) * e * 0.55 * ia;

  // Turbolenza che fa danzare le fiamme.
  vec2 wp = pos + vec2(
      (fbm(pos * 0.018 + vec2(0.0, t * 1.6)) - 0.5) * 26.0,
      (fbm(pos * 0.022 + vec2(5.2, t * 2.1)) - 0.5) * 18.0);

  vec2 hs = flame(uP0, wp) + flame(uP1, wp) + flame(uP2, wp) +
            flame(uP3, wp) + flame(uP4, wp) + flame(uP5, wp) +
            flame(uP6, wp) + flame(uP7, wp) + flame(uP8, wp) +
            flame(uP9, wp) + flame(uP10, wp) + flame(uP11, wp);

  // Fiammella fissa sul cursore.
  if (uMouse.z > 0.001) {
    vec2 d = wp - uMouse.xy + vec2(0.0, 6.0);
    d.y *= d.y < 0.0 ? 0.5 : 1.4;
    float flick = 0.85 + 0.15 * sin(t * 13.0) * sin(t * 7.3 + 1.0);
    hs.x += uMouse.z * 0.95 * flick * exp(-dot(d, d) / (13.0 * 13.0));
  }

  // Lingue di fuoco: il rumore spezza la scia.
  float tongues = 0.45 + 0.9 * fbm(wp * vec2(0.03, 0.018) + vec2(0.0, t * 3.0));
  float heat = hs.x * tongues * ia;
  // Scintille veloci che salgono dal fuoco.
  float sp = embers(pos, t, 18.0, 120.0, 2.2) *
             smoothstep(0.03, 0.3, hs.x + hs.y * 0.5);
  col += vec3(1.0, 0.71, 0.28) * sp * 1.2 * ia;
  // Fumo: velo grigio-blu appena percettibile.
  col = mix(col, vec3(0.16, 0.18, 0.22), clamp(hs.y * 0.22 * ia, 0.0, 0.35));
  // Fuoco: additivo con alone morbido.
  float glowA = smoothstep(0.0, 0.6, heat);
  col += fireRamp(heat) * glowA * 0.95;
  col += vec3(1.0, 0.45, 0.12) * 0.10 * smoothstep(0.0, 0.25, heat);

  // Vignettatura.
  vec2 q = pos / max(uSize, vec2(1.0)) - 0.5;
  col *= 1.0 - 0.35 * smoothstep(0.3, 0.85, length(q));

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
