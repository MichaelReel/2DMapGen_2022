shader_type canvas_item;
uniform vec2 Mouse;

const float K1 = 0.366025404; // (sqrt(3)-1)/2;
const float K2 = 0.211324865; // (3-sqrt(3))/6;

vec2 hash( vec2 p )
{
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise( in vec2 p )
{
	vec2  i = floor(p + (p.x + p.y) * K1);
	vec2  a = p - i + (i.x + i.y) * K2;
	float m = step(a.y, a.x); 
	vec2  o = vec2(m, 1.0 - m);
	vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0 * K2;
	vec3  h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	vec3  n = h * h * h * h * vec3(dot(a, hash(i+0.0)), dot(b, hash(i+o)), dot(c, hash(i+1.0)));
	return dot(n, vec3(70.0));
}

float fbm(vec2 uv) {
	uv *= 5.0;
	mat2 m = mat2(vec2(1.6,  1.2), vec2(-1.2,  1.6));
	
	float f = 0.0;
	f  = 0.5000 * noise(uv);
	uv = m * uv;
	f += 0.2500 * noise(uv);
	uv = m * uv;
	f += 0.1250 * noise(uv);
	uv = m * uv;
	f += 0.0625 * noise(uv);
	uv = m * uv;
	
	f = 0.5 + 0.5 * f;
	
	return f;
}

vec2 square_pos(in vec2 fragcoord, in vec2 spsize, in float ratio) {
    vec2 res = 1.0/spsize;
    vec2 st = fragcoord/res;
    st.x *= res.x/res.y * ratio;
    return st;
}

void fragment() {
	vec2 uv = square_pos(FRAGCOORD.xy, SCREEN_PIXEL_SIZE, 1.0);
	
	// Adding time to the base noises makes the image \"flow\" directionally
	float f1x = 0.0; //  + sin(TIME * 0.25);
	float f1y = 0.0;
	float f2x = 5.2;
	float f2y = 1.3; // - cos(TIME * 0.25);
	
	// Adding time to the input of the combining noise causes an inplace \"flow\"
	float f1 = fbm(uv + vec2(f1x, f1y)) + Mouse.x; // + TIME * 0.05;
	float f2 = fbm(uv + vec2(f2x, f2y)) + Mouse.y; // + TIME * 0.05;
	
	float f = fbm(uv + vec2(f1, f2));
	
	COLOR = vec4(f, f, f, 1.0);
}
