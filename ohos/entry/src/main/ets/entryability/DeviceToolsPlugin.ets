import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { statfs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class DeviceToolsPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  getUniqueClassName(): string { return 'DeviceToolsPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'aloeplayer/device-tools');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'freeBytes') {
        statfs.getFreeSize('/data/storage/el2/base').then((size: number) => result.success(size)).catch((error: BusinessError) => result.error('STORAGE', 'Cannot read storage capacity: ' + error.code, null));
      } else { result.notImplemented(); }
    }});
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void { this.channel?.setMethodCallHandler(null); }
}
