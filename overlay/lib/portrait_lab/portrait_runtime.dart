import 'dart:io';

import 'application/portrait_generation_controller.dart';
import 'infrastructure/android_portrait_model_downloader.dart';
import 'infrastructure/dream_host_accelerator.dart';
import 'infrastructure/dream_host_portrait_engine.dart';
import 'infrastructure/local_diffusion_portrait_engine.dart';
import 'infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'infrastructure/native_portrait_io.dart';
import 'infrastructure/portrait_active_model_store.dart';
import 'infrastructure/portrait_backend_router_engine.dart';
import 'infrastructure/portrait_identity_lock_engine.dart';
import 'infrastructure/portrait_model_downloader.dart';
import 'infrastructure/standalone_qnn_portrait_engine.dart';
import 'infrastructure/upstream_local_diffusion_native_generator.dart';

class PortraitRuntime {
  const PortraitRuntime._();

  static PortraitGenerationController createController() {
    final stableOutput = FileNativePortraitOutputStore();
    final stable = LocalDiffusionPortraitEngine(
      NativeLocalDiffusionImg2ImgBridge(
        decoder: ImagePackageNativePortraitDecoder(),
        generator: UpstreamLocalDiffusionNativeGenerator(),
        outputStore: stableOutput,
      ),
    );
    final dream = DreamHostPortraitEngine(
      accelerator: LocalDreamHostAccelerator(),
      outputStore: FileNativePortraitOutputStore(),
    );
    final standaloneQnn = StandaloneQnnPortraitEngine(
      backend: AndroidStandaloneQnnBackendController(),
      transport: LocalStandaloneQnnGenerationTransport(),
      outputStore: FileNativePortraitOutputStore(),
    );
    final routed = PortraitBackendRouterEngine(
      stableEngine: stable,
      dreamEngine: dream,
      standaloneQnnEngine: standaloneQnn,
    );
    final engine = Platform.isAndroid
        ? IdentityLockedPortraitEngine(
            base: routed,
            identity: AndroidPortraitIdentityLockClient(),
          )
        : routed;
    return PortraitGenerationController(engine);
  }

  static PortraitModelDownloadService createModelDownloader() {
    if (Platform.isAndroid) {
      return AndroidPortraitModelDownloadService();
    }
    return NativePortraitModelDownloadService();
  }

  static PortraitActiveModelStore createActiveModelStore() =>
      FilePortraitActiveModelStore();
}
