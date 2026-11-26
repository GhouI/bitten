; A vertex shader in AIR's form: positions and colours from buffer 0,
; moved right by 0.5 * instance id.
target triple = "air64-apple-macosx14.0.0"

%struct.V = type { <2 x float>, <4 x float> }

define <{ <4 x float>, <4 x float> }> @tri_vertex(i32 noundef %vid, i32 noundef %iid, ptr addrspace(2) noundef readonly %verts) {
  %p = getelementptr inbounds [0 x { <2 x float>, <2 x float>, <4 x float> }], ptr addrspace(2) %verts, i64 0, i32 %vid, i32 0
  %xy = load <2 x float>, ptr addrspace(2) %p, align 16
  %cp = getelementptr inbounds [0 x { <2 x float>, <2 x float>, <4 x float> }], ptr addrspace(2) %verts, i64 0, i32 %vid, i32 2
  %c = load <4 x float>, ptr addrspace(2) %cp, align 16
  %fi = uitofp i32 %iid to float
  %dx = fmul float %fi, 5.000000e-01
  %x = extractelement <2 x float> %xy, i32 0
  %y = extractelement <2 x float> %xy, i32 1
  %x2 = fadd float %x, %dx
  %p0 = insertelement <4 x float> <float 0.0, float 0.0, float 0.0, float 1.0>, float %x2, i32 0
  %p1 = insertelement <4 x float> %p0, float %y, i32 1
  %r0 = insertvalue <{ <4 x float>, <4 x float> }> poison, <4 x float> %p1, 0
  %r1 = insertvalue <{ <4 x float>, <4 x float> }> %r0, <4 x float> %c, 1
  ret <{ <4 x float>, <4 x float> }> %r1
}

!air.vertex = !{!0}
!0 = !{ptr @tri_vertex, !1, !4}
!1 = !{!2, !3}
!2 = !{!"air.position", !"air.arg_type_name", !"float4", !"air.arg_name", !"position"}
!3 = !{!"air.vertex_output", !"generated(5colorDv4_f)", !"air.arg_type_name", !"float4", !"air.arg_name", !"color"}
!4 = !{!5, !6, !7}
!5 = !{i32 0, !"air.vertex_id", !"air.arg_type_name", !"uint", !"air.arg_name", !"vid"}
!6 = !{i32 1, !"air.instance_id", !"air.arg_type_name", !"uint", !"air.arg_name", !"iid"}
!7 = !{i32 2, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read", !"air.address_space", i32 2, !"air.arg_type_size", i32 32, !"air.arg_type_name", !"V", !"air.arg_name", !"verts"}
