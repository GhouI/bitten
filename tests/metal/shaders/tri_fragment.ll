; A fragment shader in AIR's form: the interpolated colour, times the
; texel of texture 0 at the pixel (read_texture_2d), with fast_clamp.
target triple = "air64-apple-macosx14.0.0"

declare { <4 x float>, i8 } @air.read_texture_2d.v4f32(ptr addrspace(1) readonly, <2 x i32>, i32, i32)
declare float @air.fast_clamp.f32(float, float, float)
declare <2 x i32> @air.convert.u.v2i32.f.v2f32(<2 x float>)

define <4 x float> @tri_fragment(<4 x float> %pos, <4 x float> %color, ptr addrspace(1) %tex) {
  %xy = shufflevector <4 x float> %pos, <4 x float> poison, <2 x i32> <i32 0, i32 1>
  %ixy = call <2 x i32> @air.convert.u.v2i32.f.v2f32(<2 x float> %xy)
  %t = call { <4 x float>, i8 } @air.read_texture_2d.v4f32(ptr addrspace(1) %tex, <2 x i32> %ixy, i32 0, i32 0)
  %tv = extractvalue { <4 x float>, i8 } %t, 0
  %m = fmul <4 x float> %color, %tv
  %a = extractelement <4 x float> %m, i32 3
  %ac = call float @air.fast_clamp.f32(float %a, float 0.0, float 1.0)
  %r = insertelement <4 x float> %m, float %ac, i32 3
  ret <4 x float> %r
}

!air.fragment = !{!0}
!0 = !{ptr @tri_fragment, !1, !3}
!1 = !{!2}
!2 = !{!"air.render_target", i32 0, i32 0, !"air.arg_type_name", !"float4", !"air.arg_name", !"color"}
!3 = !{!4, !5, !6}
!4 = !{i32 0, !"air.position", !"air.center", !"air.no_perspective", !"air.arg_type_name", !"float4", !"air.arg_name", !"pos"}
!5 = !{i32 1, !"air.fragment_input", !"generated(5colorDv4_f)", !"air.center", !"air.perspective", !"air.arg_type_name", !"float4", !"air.arg_name", !"color"}
!6 = !{i32 2, !"air.texture", !"air.location_index", i32 0, i32 1, !"air.sample", !"air.arg_type_name", !"texture2d<float>", !"air.arg_name", !"tex"}
