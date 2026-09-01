import 'application/portrait_generation_controller.dart';
import 'infrastructure/local_diffusion_portrait_engine.dart';
import 'infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'infrastructure/native_portrait_io.dart';
import 'infrastructure/upstream_local_diffusion_native_generator.dart';

class PortraitRuntime {
  const PortraitRuntime._();

  static PortraitGenerationController createController() {
    return PortraitGenerationController(
      LocalDiffusionPortraitEngine(
        NativeLocalDiffusionImg2ImgBridge(
          decoder: ImagePackageNativePortraitDecoder(),
          generator: UpstreamLocalDiffusionNativeGenerator(),
          outputStore: FileNativePortraitOutputStore(),
        ),
      ),
    );
  }
}
