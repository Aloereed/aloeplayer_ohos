import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { PipSession } from './PipSession';
export default class PipPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private session?: PipSession;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'PipPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'aloeplayer/system-pip');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'open') {
        this.session?.dispose();
        this.session = new PipSession(this.context, call.args, this.channel!);
        router.pushUrl({ url: 'pages/PipPlayer' }).then(() => result.success(null)).catch(() => {
          this.session?.dispose(); result.error('PIP_PAGE', '无法打开画中画页面', null);
        });
      } else if (call.method === 'close') {
        this.session?.close().then(() => result.success(null));
        if (!this.session) result.success(null);
      } else if (call.method === 'dispose') {
        this.session?.dispose(); this.session = undefined; result.success(null);
      } else if (this.session) { this.session.onMethodCall(call, result); }
      else { result.error('NO_SESSION', '画中画会话已结束', null); }
    }});
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.session?.dispose(); this.channel?.setMethodCallHandler(null);
  }
}
