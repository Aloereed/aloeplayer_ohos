import { FlutterPlugin, FlutterPluginBinding, StandardMessageCodec } from '@ohos/flutter_ohos';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { PipView } from './PipView';

class PipFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  constructor(messenger: BinaryMessenger) { super(StandardMessageCodec.INSTANCE); this.messenger = messenger; }
  create(context: common.Context, id: number, args: Object): PlatformView { return new PipView(context, id, args, this.messenger); }
}
export default class PipPlugin implements FlutterPlugin {
  getUniqueClassName(): string { return 'PipPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    binding.getPlatformViewRegistry()?.registerViewFactory('aloeplayer/pip-view', new PipFactory(binding.getBinaryMessenger()));
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {}
}
