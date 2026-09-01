class PortraitModelSpec {
  const PortraitModelSpec({
    required this.id,
    required this.displayName,
    required this.description,
    required this.sourceLabel,
    required this.licenseLabel,
    required this.format,
    required this.sizeLabel,
    required this.fileName,
    required this.downloadUrl,
    required this.expectedSha256,
    this.fastRecommended = false,
  });

  final String id;
  final String displayName;
  final String description;
  final String sourceLabel;
  final String licenseLabel;
  final String format;
  final String sizeLabel;
  final String fileName;
  final String downloadUrl;
  final String expectedSha256;
  final bool fastRecommended;
}

class PortraitModelCatalog {
  const PortraitModelCatalog._();

  static const curated = <PortraitModelSpec>[
    PortraitModelSpec(
      id: 'lcm_dreamshaper7',
      displayName: 'LCM DreamShaper 7 · FAST',
      description: '极速推荐 · LCM 6 步 / CFG 1.0，优先用于当前兼容后端的快速人像验证。',
      sourceLabel: 'Hugging Face · Runware/lcm-dreamshaper-v7',
      licenseLabel: 'See model card',
      format: 'SafeTensors',
      sizeLabel: '3.44 GB',
      fileName: 'LCM_Dreamshaper_v7_4k.safetensors',
      downloadUrl:
          'https://huggingface.co/Runware/lcm-dreamshaper-v7/resolve/main/LCM_Dreamshaper_v7_4k.safetensors?download=true',
      expectedSha256:
          '84feab3a32f1d36108b762b25dad483ca9e37f719b23e0cfd0fdc4ad3fd5409b',
      fastRecommended: true,
    ),
    PortraitModelSpec(
      id: 'sd15',
      displayName: 'Stable Diffusion 1.5',
      description: '官方基础模型 · 兼容性优先，适合作为本地推理基线。',
      sourceLabel: 'Hugging Face · stable-diffusion-v1-5',
      licenseLabel: 'CreativeML Open RAIL-M',
      format: 'SafeTensors',
      sizeLabel: '4.27 GB',
      fileName: 'v1-5-pruned-emaonly.safetensors',
      downloadUrl:
          'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors?download=true',
      expectedSha256:
          '6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa',
    ),
    PortraitModelSpec(
      id: 'dreamshaper8',
      displayName: 'DreamShaper 8',
      description: '通用人像与插画 · 约 2.13 GB，标准采样用于质量/兼容性对照。',
      sourceLabel: 'Hugging Face · casque/dreamshaper_8',
      licenseLabel: 'CreativeML Open RAIL-M',
      format: 'SafeTensors',
      sizeLabel: '2.13 GB',
      fileName: 'dreamshaper_8.safetensors',
      downloadUrl:
          'https://huggingface.co/casque/dreamshaper_8/resolve/main/dreamshaper_8.safetensors?download=true',
      expectedSha256:
          '879db523c30d3b9017143d56705015e15a2cb5628762c11d086fed9538abd7fd',
    ),
    PortraitModelSpec(
      id: 'realisticvision6',
      displayName: 'Realistic Vision 6',
      description: '写实人像方向 · 约 2.13 GB，优先用于真人照片质量对照。',
      sourceLabel: 'Hugging Face · visible-tactics',
      licenseLabel: 'CreativeML Open RAIL-M',
      format: 'SafeTensors',
      sizeLabel: '2.13 GB',
      fileName: 'realisticVisionV60B1_v51VAE.safetensors',
      downloadUrl:
          'https://huggingface.co/visible-tactics/realisticVisionV60B1_v51VAE/resolve/main/realisticVisionV60B1_v51VAE.safetensors?download=true',
      expectedSha256:
          '15012c538f503ce2ebfc2c8547b268c75ccdaff7a281db55399940ff1d70e21d',
    ),
  ];
}
