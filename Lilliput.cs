using UnityEngine;
using System;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]

public class Lilliput : MonoBehaviour
{
	[HideInInspector]
	public Shader lilliputShader;

	[NonSerialized]
	Material lilliputMaterial;

	const int circleOfConfusionPass = 0;
	const int preFilterPass = 1;
	const int bokehPass = 2;
	const int postFilterPass = 3;
	const int combinePass = 4;


	[Range(0f, 45f)]
	public float tiltingQuadAngle =10f;

	[Range(0f, 2f)]
	public float focusRange = 0.25f;

	[Range(1f, 10f)]
	public float bokehRadius = 4f;

	void OnRenderImage(RenderTexture source, RenderTexture destination)
	{
		if (lilliputMaterial == null)
		{
			lilliputMaterial = new Material(lilliputShader);
			lilliputMaterial.hideFlags = HideFlags.HideAndDontSave;
		}


		float tiltingQuadZ = 0.5f - 0.5f * (tiltingQuadAngle / 45);
		lilliputMaterial.SetFloat("_TiltingQuadZ", tiltingQuadZ);
		lilliputMaterial.SetFloat("_FocusRange", focusRange);
		lilliputMaterial.SetFloat("_BokehRadius", bokehRadius);



		//Save the depth 
		RenderTexture coc = RenderTexture.GetTemporary(
			source.width, source.height, 0,
			RenderTextureFormat.RHalf, RenderTextureReadWrite.Linear
		);

		//DownSampling, to make the image more blur
		int width = source.width / 2;
		int height = source.height / 2;
		RenderTextureFormat format = source.format;
		RenderTexture dof0 = RenderTexture.GetTemporary(width, height, 0, format);
		RenderTexture dof1 = RenderTexture.GetTemporary(width, height, 0, format);

		Graphics.Blit(source, coc, lilliputMaterial, circleOfConfusionPass); // now we got the COC buffer
		lilliputMaterial.SetTexture("_CoCTex", coc);
		lilliputMaterial.SetTexture("_DoFTex", dof0);

		Graphics.Blit(source, dof0, lilliputMaterial, preFilterPass); // at the beginning it's just a downsampling(dont have ", lilliputMaterial, preFilterPass")
		Graphics.Blit(dof0, dof1, lilliputMaterial, bokehPass); // to blur the pic
		Graphics.Blit(dof1, dof0, lilliputMaterial, postFilterPass); // to further blur the pic using simple gaussian blur
		Graphics.Blit(source, destination, lilliputMaterial, combinePass); // now we want some part to be clear, get rid off the effect of downsampling

		RenderTexture.ReleaseTemporary(coc);
		RenderTexture.ReleaseTemporary(dof0);
		RenderTexture.ReleaseTemporary(dof1);
	}
}

