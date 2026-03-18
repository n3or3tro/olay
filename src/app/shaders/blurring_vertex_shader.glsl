#version 410 core

out vec2 uv;

void main() {
	vec2 vertices[4] = vec2[](vec2(-1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0));
	vec2 uvs[4]      = vec2[](vec2( 0.0,  0.0), vec2( 0.0, 1.0), vec2(1.0,  0.0), vec2(1.0, 1.0));

	gl_Position = vec4(vertices[gl_VertexID], 0.0, 1.0);
	uv = uvs[gl_VertexID];
}
