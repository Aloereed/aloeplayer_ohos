import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { statfs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

export default class DeviceToolsPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;
  private taskId?: number;
  private starting?: Promise<void>;
  private canceled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (info.id === this.taskId) {
      this.taskId = undefined;
      this.channel?.invokeMethod('downloadBackgroundCanceled', null);
    }
  };
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'DeviceToolsPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'aloeplayer/device-tools');
    backgroundTaskManager.on('continuousTaskCancel', this.canceled);
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'freeBytes') {
        statfs.getFreeSize('/data/storage/el2/base').then((size: number) => result.success(size)).catch((error: BusinessError) => result.error('STORAGE', 'Cannot read storage capacity: ' + error.code, null));
      } else if (call.method === 'startDownloadBackground') {
        if (!this.starting) this.starting = this.startDownload();
        this.starting.then(() => result.success(true)).catch((error: BusinessError) => result.error('BACKGROUND', 'Background transfer unavailable: ' + error.code, null));
      } else if (call.method === 'stopDownloadBackground') {
        this.stopDownload().then(() => result.success(null)).catch((error: BusinessError) => result.error('BACKGROUND', 'Cannot stop background transfer: ' + error.code, null));
      } else { result.notImplemented(); }
    }});
  }
  private async startDownload(): Promise<void> {
    if (this.taskId !== undefined) return;
    const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY, requestCode: 20260906, actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
    const request = new backgroundTaskManager.ContinuousTaskRequest();
    request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
    request.wantAgent = agent;
    const notification = await backgroundTaskManager.startBackgroundRunning(this.context, request);
    this.taskId = notification.continuousTaskId;
  }
  private async stopDownload(): Promise<void> {
    try { await this.starting; } catch (error) {}
    this.starting = undefined;
    const id = this.taskId;
    this.taskId = undefined;
    // Stop this transfer's task only; audio playback may own a separate task.
    if (id !== undefined) await backgroundTaskManager.stopBackgroundRunning(this.context, id);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    backgroundTaskManager.off('continuousTaskCancel', this.canceled);
    this.stopDownload().catch(() => {});
  }
}
