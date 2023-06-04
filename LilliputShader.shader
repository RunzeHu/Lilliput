Shader "Unlit/LilliputShader"
{
    Properties {
		_MainTex ("Texture", 2D) = "white" {}
	}

	CGINCLUDE
		#include "UnityCG.cginc"

		sampler2D _MainTex, _CameraDepthTexture, _CoCTex, _DoFTex;
		float4 _MainTex_TexelSize;
		float _TiltingQuadZ, _FocusRange,_BokehRadius;

		struct VertexData {
			float4 vertex : POSITION;
			float2 uv : TEXCOORD0;
		};

		struct Interpolators {
			float4 pos : SV_POSITION;
			float2 uv : TEXCOORD0;
		};

		Interpolators VertexProgram (VertexData v) {
			Interpolators i;
			i.pos = UnityObjectToClipPos(v.vertex);
			i.uv = v.uv;
			return i;
		}



		/////////////////////////////////////////////////////////////////////////LILLIPUT * DOF////////////////////////////////////////////////////////
		Interpolators TiltQuadVertex (uint vertexID : SV_VertexID) {
			Interpolators output;
			output.pos = float4(
				vertexID <= 1 ? -1.0 : 1.0,
				(vertexID == 1 || vertexID == 2) ? 1.0 : -1.0,
				(vertexID == 1 || vertexID == 2) ? _TiltingQuadZ : (1-_TiltingQuadZ), 
				1.0
			);

			//Looks like I must invert the y coordinate, so it's "0.0 : 1.0" here instead of "1.0 : 0.0" as it supposed to be
			output.uv = float2(
				vertexID <= 1 ? 0.0 : 1.0,
				(vertexID == 1 || vertexID == 2) ? 0.0 : 1.0
			);

			return output;
		}

		half4 FragmentProgram_liliput (Interpolators i) : SV_Target {
			return (LinearEyeDepth(i.pos.z));
		}

		half CalculateCoc(half depth){		
			depth = LinearEyeDepth(depth); //convert the depth from NDC to linear value
			float coc = (depth - LinearEyeDepth(0.5)) / _FocusRange;
			coc = clamp(coc, -1, 1)* _BokehRadius;
			return coc;

		}

	ENDCG

	SubShader {
		Cull Off
		ZTest Always
		ZWrite Off

		Pass { // 0 COC
			CGPROGRAM
				#pragma vertex TiltQuadVertex
				#pragma fragment FragmentProgram

				half FragmentProgram (Interpolators i) : SV_Target {
					half depth = i.pos.z;
					depth = LinearEyeDepth(depth);
					float coc = (depth - LinearEyeDepth(0.5)) / _FocusRange;
					coc = clamp(coc, -1, 1)* _BokehRadius;
					return coc;
				}
	
			ENDCG
		}

		Pass { // 1 preFilterPass
			CGPROGRAM
				#pragma vertex TiltQuadVertex
				#pragma fragment FragmentProgram

				half4 FragmentProgram (Interpolators i) : SV_Target {
					float4 o = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
					half coc0 = tex2D(_CoCTex, i.uv + o.xy).r;
					half coc1 = tex2D(_CoCTex, i.uv + o.zy).r;
					half coc2 = tex2D(_CoCTex, i.uv + o.xw).r;
					half coc3 = tex2D(_CoCTex, i.uv + o.zw).r;
					
					//half coc = (coc0 + coc1 + coc2 + coc3) * 0.25;

					//why the most extremely value among the four?
					half cocMin = min(min(min(coc0, coc1), coc2), coc3);
					half cocMax = max(max(max(coc0, coc1), coc2), coc3);
					half coc = cocMax >= -cocMin ? cocMax : cocMin;

					return half4(tex2D(_MainTex, i.uv).rgb, coc);
				}

			ENDCG
		}

		Pass { // 2 bokehPass
			CGPROGRAM
				#pragma vertex VertexProgram
				#pragma fragment FragmentProgram

				// From https://github.com/Unity-Technologies/PostProcessing/
				// blob/v2/PostProcessing/Shaders/Builtins/DiskKernels.hlsl
				static const int kernelSampleCount = 22;
					static const float2 kernel[kernelSampleCount] = {
						float2(0, 0),
						float2(0.53333336, 0),
						float2(0.3325279, 0.4169768),
						float2(-0.11867785, 0.5199616),
						float2(-0.48051673, 0.2314047),
						float2(-0.48051673, -0.23140468),
						float2(-0.11867763, -0.51996166),
						float2(0.33252785, -0.4169769),
						float2(1, 0),
						float2(0.90096885, 0.43388376),
						float2(0.6234898, 0.7818315),
						float2(0.22252098, 0.9749279),
						float2(-0.22252095, 0.9749279),
						float2(-0.62349, 0.7818314),
						float2(-0.90096885, 0.43388382),
						float2(-1, 0),
						float2(-0.90096885, -0.43388376),
						float2(-0.6234896, -0.7818316),
						float2(-0.22252055, -0.974928),
						float2(0.2225215, -0.9749278),
						float2(0.6234897, -0.7818316),
						float2(0.90096885, -0.43388376),
					};

				half Weigh (half coc, half radius) {
					return saturate((coc - radius + 2) / 2);
				}

				half4 FragmentProgram (Interpolators i) : SV_Target {
					half coc = tex2D(_MainTex, i.uv).a;

					half3 bgColor = 0, fgColor = 0;
					half bgWeight = 0, fgWeight = 0;
					for (int k = 0; k < kernelSampleCount; k++) {
						float2 o = kernel[k] * _BokehRadius;
						half radius = length(o);
						o *= _MainTex_TexelSize.xy;
						half4 s = tex2D(_MainTex, i.uv + o);

						half bgw = Weigh(max(0, min(s.a, coc)), radius);
						bgColor += s.rgb * bgw;
						bgWeight += bgw;

						half fgw = Weigh(-s.a, radius);
						fgColor += s.rgb * fgw;
						fgWeight += fgw;
					}
					bgColor *= 1 / (bgWeight + (bgWeight == 0));
					fgColor *= 1 / (fgWeight + (fgWeight == 0));

					half bgfg = min(1, fgWeight* 3.14159265359 / kernelSampleCount);
					half3 color = lerp(bgColor, fgColor, bgfg);
					return half4(color, bgfg);
				}



			ENDCG
		}

		Pass { // 3 postFilterPass
			CGPROGRAM
				#pragma vertex VertexProgram
				#pragma fragment FragmentProgram

				half4 FragmentProgram (Interpolators i) : SV_Target {
					float4 o = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
					half4 s =
						tex2D(_MainTex, i.uv + o.xy) +
						tex2D(_MainTex, i.uv + o.zy) +
						tex2D(_MainTex, i.uv + o.xw) +
						tex2D(_MainTex, i.uv + o.zw);
					return s * 0.25;
				}
			ENDCG
		}



		Pass { // 4 combinePass
			CGPROGRAM
				#pragma vertex VertexProgram
				#pragma fragment FragmentProgram

				half4 FragmentProgram (Interpolators i) : SV_Target {
					half4 source = tex2D(_MainTex, i.uv);
					half coc = tex2D(_CoCTex, i.uv).r;
					half4 dof = tex2D(_DoFTex, i.uv);

					//half dofStrength = smoothstep(0.1, 1, abs(coc));
					half dofStrength = smoothstep(0.1, 1, abs(coc));
					half3 color = lerp(source.rgb, dof.rgb, dofStrength + dof.a - dofStrength * dof.a);
					return half4(color, source.a);
				}
			ENDCG
		}


	}
}
