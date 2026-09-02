enum PortraitModelBackend {
  stableDiffusionCpp,
  dreamQnnSdxl,
}

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
    this.backend = PortraitModelBackend.stableDiffusionCpp,
    this.isArchive = false,
    this.generationSize = 512,
    this.dreamModelId,
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
  final PortraitModelBackend backend;
  final bool isArchive;
  final int generationSize;
  final String? dreamModelId;

  bool get usesDreamQnn => backend == PortraitModelBackend.dreamQnnSdxl;

  String? get dreamSelectionUri =>
      dreamModelId == null ? null : 'dream://${dreamModelId!}';

  String? standaloneSelectionUri(String installedPath) {
    final modelId = dreamModelId;
    if (!usesDreamQnn || modelId == null || installedPath.trim().isEmpty) {
      return null;
    }
    return Uri(
      scheme: 'qnn',
      host: 'standalone',
      queryParameters: <String, String>{
        'model_id': modelId,
        'path': installedPath,
        'type': 'sdxl',
        'size': '$generationSize',
      },
    ).toString();
  }
}

class PortraitModelCatalog {
  const PortraitModelCatalog._();

  static const curated = <PortraitModelSpec>[
    PortraitModelSpec(
      id: 'illustrious_v16_dmd2_qnn',
      displayName: 'Illustrious v16 DMD2',
      description: 'DREAM 同源极速模型 · SDXL/QNN/HTP · 1024×1024 · DMD2。下载独立包后可直接在 Portrait Lab 本机 NPU 运行；DREAM Host 仅作为可选复用路径。',
      sourceLabel: 'Hugging Face · xororz/sdxl-qnn',
      licenseLabel: 'Model package · see upstream model card',
      format: 'QNN SDXL ZIP',
      sizeLabel: '3.72 GB ZIP',
      fileName: 'illustrious_v16_dmd2_qnn2.28_8gen3.zip',
      downloadUrl:
          'https://huggingface.co/xororz/sdxl-qnn/resolve/main/illustrious_v16_dmd2_qnn2.28_8gen3.zip?download=true',
      expectedSha256: '',
      fastRecommended: true,
      backend: PortraitModelBackend.dreamQnnSdxl,
      isArchive: true,
      generationSize: 1024,
      dreamModelId: 'illustrious_v16_dmd2',
    ),
    PortraitModelSpec(
      id: 'cyber_realistic_v10_dmd2_qnn',
      displayName: 'CyberRealistic v10 DMD2',
      description: 'DREAM 同源写实极速模型 · SDXL/QNN/HTP · 1024×1024 · DMD2。独立包安装后优先本机 QNN 直跑，无需开启 DREAM Host。',
      sourceLabel: 'Hugging Face · xororz/sdxl-qnn',
      licenseLabel: 'Model package · see upstream model card',
      format: 'QNN SDXL ZIP',
      sizeLabel: '3.75 GB ZIP',
      fileName: 'cyber_realistic_v10_dmd2_qnn2.28_8gen3.zip',
      downloadUrl:
          'https://huggingface.co/xororz/sdxl-qnn/resolve/main/cyber_realistic_v10_dmd2_qnn2.28_8gen3.zip?download=true',
      expectedSha256:
          '1c6a9647666e276ca262bf96328234536a07261567bf4eb572b50d1edb0987af',
      fastRecommended: true,
      backend: PortraitModelBackend.dreamQnnSdxl,
      isArchive: true,
      generationSize: 1024,
      dreamModelId: 'cyber_realistic_v10_dmd2',
    ),
    PortraitModelSpec(
      id: 'sd15',
      displayName: 'Stable Diffusion 1.5',
      description: '兼容后端基础模型 · CPU/Vulkan fallback。',
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
      description: '兼容后端通用人像与插画模型，用于 fallback/对照。',
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
      description: '兼容后端写实人像模型，用于 fallback/对照。',
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
