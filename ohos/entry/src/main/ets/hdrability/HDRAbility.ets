/*
 * @Author: 
 * @Date: 2025-03-22 12:14:16
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-22 13:53:11
 * @Description: file content
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

export default class HDRAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    if (want.parameters!=null) {
      console.log(`[sweet] uri: ${want.parameters!.url}`)
      AppStorage.setOrCreate("videoUriForSweet", want.parameters!.url)
      AppStorage.setOrCreate("playListForSweet", want.parameters!.urls)
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    if (want.parameters!=null) {
      console.log(`[sweet] uri: ${want.parameters!.url}`)
      AppStorage.setOrCreate("videoUriForSweet", want.parameters!.url)
      AppStorage.setOrCreate("playListForSweet", want.parameters!.urls)
    }
}

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    // 1.获取应用主窗口。
      // 2.实现沉浸式效果。方式一：设置导航栏、状态栏不显示。
    //   let names: Array<'status' | 'navigation'> = [];
    //   windowClass.setWindowSystemBarEnable(names)
    //     .then(() => {
    //       console.info('Succeeded in setting the system bar to be visible.');
    //     })
    //     .catch((err: BusinessError) => {
    //       console.error('Failed to set the system bar to be visible. Cause:' + JSON.stringify(err));
    //     });
    // })
    // 3.为沉浸式窗口加载对应的目标页面。
    windowStage.loadContent("pages/Player", (err: BusinessError) => {
      let errCode: number = err.code;
      if (errCode) {
        console.error('Failed to load the content. Cause:' + JSON.stringify(err));
        return;
      }
      console.info('Succeeded in loading the content.');
    });
}

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
