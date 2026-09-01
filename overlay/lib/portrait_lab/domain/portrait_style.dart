enum PortraitStyle {
  japaneseFresh,
  animeIllustration,
  manga,
  businessPortrait,
  cinematicPortrait,
  editorial,
  ancientChinese,
  cyberpunk,
}

class PortraitStyleSpec {
  const PortraitStyleSpec({
    required this.id,
    required this.displayName,
    required this.promptSuffix,
    required this.negativePrompt,
    required this.strength,
    required this.cfgScale,
    required this.steps,
    required this.width,
    required this.height,
    required this.recommendedModelFamily,
  });

  final String id;
  final String displayName;
  final String promptSuffix;
  final String negativePrompt;
  final double strength;
  final double cfgScale;
  final int steps;
  final int width;
  final int height;
  final String recommendedModelFamily;
}

extension PortraitStyleConfiguration on PortraitStyle {
  PortraitStyleSpec get spec {
    switch (this) {
      case PortraitStyle.japaneseFresh:
        return const PortraitStyleSpec(
          id: 'japanese_fresh',
          displayName: '日系清新',
          promptSuffix:
              'professional portrait, japanese fresh style, natural soft light, clean skin texture, detailed face',
          negativePrompt:
              'low quality, blurry, distorted face, deformed, extra fingers, bad anatomy',
          strength: 0.55,
          cfgScale: 6.0,
          steps: 20,
          width: 512,
          height: 768,
          recommendedModelFamily: 'portrait-img2img',
        );
      case PortraitStyle.animeIllustration:
        return const PortraitStyleSpec(
          id: 'anime_illustration',
          displayName: '二次元插画',
          promptSuffix:
              'anime portrait illustration, refined line art, expressive eyes, detailed face, soft cinematic lighting',
          negativePrompt:
              'low quality, blurry, distorted face, malformed hands, photorealistic noise',
          strength: 0.62,
          cfgScale: 6.5,
          steps: 22,
          width: 512,
          height: 768,
          recommendedModelFamily: 'anime-img2img',
        );
      case PortraitStyle.manga:
        return const PortraitStyleSpec(
          id: 'manga',
          displayName: '漫画风',
          promptSuffix:
              'manga portrait, clean ink lines, graphic shading, expressive character design',
          negativePrompt:
              'low quality, blurry, distorted face, muddy lines, malformed hands',
          strength: 0.65,
          cfgScale: 6.5,
          steps: 22,
          width: 512,
          height: 768,
          recommendedModelFamily: 'anime-img2img',
        );
      case PortraitStyle.businessPortrait:
        return const PortraitStyleSpec(
          id: 'business_portrait',
          displayName: '商务肖像',
          promptSuffix:
              'professional business portrait, studio lighting, natural skin, confident expression, premium corporate photography',
          negativePrompt:
              'low quality, blurry, distorted face, casual clothing, harsh artifacts',
          strength: 0.42,
          cfgScale: 5.5,
          steps: 20,
          width: 512,
          height: 768,
          recommendedModelFamily: 'realistic-portrait',
        );
      case PortraitStyle.cinematicPortrait:
        return const PortraitStyleSpec(
          id: 'cinematic_portrait',
          displayName: '电影人像',
          promptSuffix:
              'cinematic portrait, dramatic practical lighting, film still, rich tonal depth, detailed face',
          negativePrompt:
              'low quality, flat lighting, blurry, distorted face, oversaturated skin',
          strength: 0.52,
          cfgScale: 6.0,
          steps: 22,
          width: 512,
          height: 768,
          recommendedModelFamily: 'realistic-portrait',
        );
      case PortraitStyle.editorial:
        return const PortraitStyleSpec(
          id: 'editorial',
          displayName: '杂志写真',
          promptSuffix:
              'editorial portrait photography, magazine quality, fashion lighting, refined composition, detailed face',
          negativePrompt:
              'low quality, snapshot, blurry, distorted face, bad anatomy',
          strength: 0.48,
          cfgScale: 5.8,
          steps: 20,
          width: 512,
          height: 768,
          recommendedModelFamily: 'realistic-portrait',
        );
      case PortraitStyle.ancientChinese:
        return const PortraitStyleSpec(
          id: 'ancient_chinese',
          displayName: '古风',
          promptSuffix:
              'ancient chinese style portrait, elegant traditional costume, poetic atmosphere, delicate lighting, detailed face',
          negativePrompt:
              'low quality, blurry, modern clothing, distorted face, malformed hands',
          strength: 0.62,
          cfgScale: 6.5,
          steps: 24,
          width: 512,
          height: 768,
          recommendedModelFamily: 'illustration-portrait',
        );
      case PortraitStyle.cyberpunk:
        return const PortraitStyleSpec(
          id: 'cyberpunk',
          displayName: '赛博朋克',
          promptSuffix:
              'cyberpunk portrait, neon city lighting, futuristic fashion, cinematic contrast, detailed face',
          negativePrompt:
              'low quality, blurry, washed out, distorted face, malformed hands',
          strength: 0.58,
          cfgScale: 6.5,
          steps: 22,
          width: 512,
          height: 768,
          recommendedModelFamily: 'stylized-portrait',
        );
    }
  }
}
