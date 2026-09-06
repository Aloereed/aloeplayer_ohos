/*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  BinaryMessenger,
  Log,
  MethodChannel,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { MethodCallHandlerImpl } from './MethodCallHandlerImpl';

const TAG = "InAppPurchasePlugin"

export class InAppPurchasePlugin implements FlutterPlugin, AbilityAware {
  private methodChannel: MethodChannel | null = null
  private methodCallHandler: MethodCallHandlerImpl | null = null
  private context: common.UIAbilityContext | null = null

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.setUpMethodChannel(binding.getBinaryMessenger(), binding.getApplicationContext());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.teardownMethodChannel();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context
    this.methodCallHandler?.setContext(this.context)
  }

  onDetachedFromAbility(): void {
    this.methodCallHandler?.setContext(null)
  }

  getUniqueClassName(): string {
    return TAG
  }

  setUpMethodChannel(messenger: BinaryMessenger, context: common.Context) {
    this.methodChannel = new MethodChannel(messenger, "plugins.flutter.io/in_app_purchase");
    this.methodCallHandler =
      new MethodCallHandlerImpl(context, this.methodChannel);
    this.methodChannel.setMethodCallHandler(this.methodCallHandler);
  }

  teardownMethodChannel() {
    this.methodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.methodCallHandler = null;
    this.context = null;
  }
}
