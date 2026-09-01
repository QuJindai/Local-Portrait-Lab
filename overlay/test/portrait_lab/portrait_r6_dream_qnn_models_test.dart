import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';

void main() {
  test('R6 catalog uses DREAM DMD2 QNN models and removes broken LCM entry', () {
    final ids = PortraitModelCatalog.curated.map((m) => m.id).toList();

    expect(ids, isNot(contains('lcm_dreamshaper7')));
    expect(ids.take(2), <String>[
      'illustrious_v16_dmd2_qnn',
      'cyber_realistic_v10_dmd2_qnn',
    ]);

    final illustrious = PortraitModelCatalog.curated[0];
    final cyber = PortraitModelCatalog.curated[1];
    for (final model in <PortraitModelSpec>[illustrious, cyber]) {
      expect(model.backend, PortraitModelBackend.dreamQnnSdxl);
      expect(model.isArchive, isTrue);
      expect(model.generationSize, 1024);
      expect(model.fileName.endsWith('.zip'), isTrue);
      expect(model.downloadUrl.startsWith('https://huggingface.co/xororz/sdxl-qnn/resolve/main/'), isTrue);
      expect(model.downloadUrl, contains('dmd2_qnn2.28_8gen3.zip'));
      expect(model.fastRecommended, isTrue);
    }

    expect(illustrious.displayName, 'Illustrious v16 DMD2');
    expect(cyber.displayName, 'CyberRealistic v10 DMD2');
  });
}
