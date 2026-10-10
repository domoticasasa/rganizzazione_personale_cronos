// Sfondo "acqua liquida" azzurro per Gestopro360.
// Caustiche che scorrono lente + increspature (ripple) generate dal mouse/tocco,
// con rifrazione e riflesso morbido. Usato da lib/widgets/liquid_water_background.dart.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;       // dimensione in pixel logici
uniform float uTime;      // secondi
uniform vec3 uMouse;      // x, y, presenza 0..1
uniform float uIntensity; // 0..1.5
// Ripple: x, y, eta' (s), forza (0 = spento)
uniform vec4 uR0;
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uR3;
uniform vec4 uR4;
uniform vec4 uR5;
uniform vec4 uR6;
uniform vec4 uR7;
uniform vec4 uR8;
uniform vec4 uR9;

out vec4 fragColor;

const float TAU = 6.28318530718;

float caustic(vec2 uv, float t) {
  vec2 p = uv * TAU - 250.0;
  vec2 i = p;
  float c = 1.0;
  float inten = 0.005;
  for (int n = 0; n < 4; n++) {
    float tt = t * (1.0 - (3.5 / float(n + 1)));
    i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
    c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten),
                           p.y / (cos(i.y + tt) / inten)));
  }
  c /= 4.0;
  c = 1.17 - pow(c, 1.4);
  return clamp(pow(abs(c), 8.0), 0.0, 1.0);
}

// Ritorna (gradiente.x, gradiente.y, altezza) dell'onda circolare.
vec3 ripple(vec4 r, vec2 pos) {
  if (r.w <= 0.0) {
    return vec3(0.0);
  }
  vec2 d = pos - r.xy;
  float dist = length(d) + 0.001;
  float age = r.z;
  float speed = 240.0;  // px/s
  float k = 0.07;       // rad/px (lunghezza d'onda ~90 px)
  float front = age * speed;
  float env = r.w * exp(-age * 1.5) * exp(-dist * 0.0035);
  env *= 1.0 - smoothstep(front - 30.0, front + 30.0, dist);  // davanti al fronte: calmo
  env *= smoothstep(front - 240.0, front - 50.0, dist);       // solo un anello di onde
  float ph = (dist - front) * k;
  float h = sin(ph) * env;
  float dh = cos(ph) * k * env;
  return vec3(d / dist * dh, h);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  float hgt = max(uSize.y, 1.0);
  vec2 uv = pos / hgt;
  float t = uTime;

  vec3 rp = ripple(uR0, pos) + ripple(uR1, pos) + ripple(uR2, pos) +
            ripple(uR3, pos) + ripple(uR4, pos) + ripple(uR5, pos) +
            ripple(uR6, pos) + ripple(uR7, pos) + ripple(uR8, pos) +
            ripple(uR9, pos);

  // Moto ondoso lento di fondo (gradiente analitico).
  vec2 sw = vec2(
      0.020 * cos(uv.x * 3.1 + t * 0.35) * cos(uv.y * 2.3 - t * 0.27),
      -0.016 * sin(uv.x * 3.1 + t * 0.35) * sin(uv.y * 2.3 - t * 0.27));
  vec2 grad = rp.xy + sw * 0.6;

  // Rifrazione: le caustiche si piegano sotto le onde.
  vec2 refr = grad * 380.0 / hgt;
  float c1 = caustic(uv * 1.9 + refr + vec2(t * 0.012, t * 0.008), t * 0.22);
  float c2 = caustic(uv * 1.1 - refr * 0.6 + vec2(3.7 - t * 0.006, 1.9 + t * 0.010),
                     t * 0.17 + 1.3);
  float caus = clamp((c1 * 0.62 + c2 * 0.42) * 1.9, 0.0, 1.0);

  // Luce del mouse.
  float md = length(pos - uMouse.xy);
  float glow = exp(-(md * md) / (2.0 * 190.0 * 190.0)) * uMouse.z;
  caus *= 1.0 + 0.9 * glow;

  vec3 top = vec3(0.935, 0.965, 0.992);
  vec3 deep = vec3(0.780, 0.885, 0.962);    // #D1E7F7
  vec3 cyan = vec3(0.0, 0.682, 0.937);      // #00AEEF
  vec3 accent = vec3(0.082, 0.396, 0.753);  // #1565C0
  vec3 foam = vec3(0.985, 0.995, 1.0);

  float v = pos.y / hgt;
  float blob = 0.5 + 0.5 * sin(uv.x * 1.7 + t * 0.09) * cos(v * 2.1 - t * 0.07);
  vec3 col = mix(top, deep, clamp(0.18 + 0.55 * v + 0.25 * blob, 0.0, 1.0));
  col = mix(col, mix(deep, cyan, 0.22), 0.22 * blob);

  float ia = clamp(uIntensity, 0.0, 1.5);
  col = mix(col, col * vec3(0.90, 0.955, 0.99), (1.0 - caus) * 0.22 * ia);
  col = mix(col, foam, clamp(caus * 0.75 * ia, 0.0, 1.0));

  // Riflesso/ombra delle increspature (luce da alto-sinistra).
  float sh = dot(grad, normalize(vec2(-0.6, -0.8))) * 7.0 * ia;
  col += vec3(1.0) * max(sh, 0.0) * 0.55;
  col = mix(col, col * vec3(0.84, 0.92, 0.99), clamp(-sh, 0.0, 1.0) * 0.9);

  col = mix(col, foam, 0.30 * glow);
  col += cyan * 0.05 * glow;

  // Vignettatura leggera tono accento.
  vec2 q = pos / max(uSize, vec2(1.0)) - 0.5;
  float vig = smoothstep(0.35, 0.85, length(q * vec2(1.0, 0.9)));
  col = mix(col, mix(col, accent, 0.14), vig);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
