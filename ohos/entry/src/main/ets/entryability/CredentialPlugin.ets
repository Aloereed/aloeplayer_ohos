import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export default class CredentialPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  getUniqueClassName(): string { return 'CredentialPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'aloeplayer/credentials');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      this.handle(call, result);
    }});
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
  }
  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    const key = call.argument('key') as string;
    if (!key || key.length > 200) { result.error('INVALID_KEY', 'Invalid credential key', null); return; }
    const encoder = new util.TextEncoder();
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encoder.encodeInto('aloeplayer.' + key));
    try {
      if (call.method === 'write') {
        // A prefix supports empty passwords without an empty asset secret.
        const value = call.argument('value') as string;
        query.set(asset.Tag.SECRET, encoder.encodeInto('v1:' + value));
        query.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        query.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
        await asset.add(query);
        result.success(null);
      } else if (call.method === 'read') {
        query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
        const entries = await asset.query(query);
        const secret = entries.length > 0 ? entries[0].get(asset.Tag.SECRET) as Uint8Array : undefined;
        result.success(secret ? new util.TextDecoder().decodeToString(secret).substring(3) : null);
      } else if (call.method === 'delete') {
        await asset.remove(query);
        result.success(null);
      } else { result.notImplemented(); }
    } catch (error) {
      const issue = error as BusinessError;
      if (issue.code === 24000002 && call.method !== 'write') { result.success(null); }
      else { result.error('CREDENTIAL_STORE', 'Secure credential operation failed: ' + issue.code, null); }
    }
  }
}
