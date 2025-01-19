import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import {
  AbilityPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { FileSelector } from './FileSelector'

const TAG = "FileSelectorOhosPlugin"

export default class FileSelectorOhosPlugin implements FlutterPlugin, AbilityAware {

  private pluginBinding: FlutterPluginBinding | null = null;
  private fileSelectorApi: FileSelector | null = null;

  getUniqueClassName(): string {
    return "FileSelectorOhosPlugin"
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.fileSelectorApi = new FileSelector(binding);
    if (this.pluginBinding != null) {
      this.fileSelectorApi.setup(this.pluginBinding.getBinaryMessenger(), binding);
    }
  }

  onDetachedFromAbility(): void {
    this.fileSelectorApi = null;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    console.debug(TAG, 'onAttachedToEngine file selector  ')
    this.pluginBinding = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = null;
  }
}