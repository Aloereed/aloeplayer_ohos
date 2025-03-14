// import { executeFFmpegCommandAPP } from '../../../cpp/types/entry'
import libAddon from 'libentry.so'
// import { RandomUtil } from '@pura/harmony-utils';
import { util } from '@kit.ArkTS';

export interface FFmpegCommandOptions {
  cmds: Array<string>;
  onFFmpegProgress: (progress: number) => void;
  onFFmpegFail: (code: number, msg: string) => void;
  onFFmpegSuccess: () => void;
}

export class FFMpegUtils {
  static executeFFmpegCommand(options: FFmpegCommandOptions): Promise<number> {
    let uuid = util.generateRandomUUID(true);
    // let uuid = RandomUtil.generateUUID32()
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegProgress", options.onFFmpegProgress)
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegFail", options.onFFmpegFail)
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegSuccess", options.onFFmpegSuccess)


    return new Promise<number>((resolve, reject) => {
      try {
        libAddon.executeFFmpegCommandAPP(uuid, options.cmds.length, options.cmds).then((code: number) => {
          resolve(code)
        }).catch((err: Error) => {
          reject(err)
        })
      } catch (e) {
        reject(e)
      }
    })
  }
  static executeFFmpegCommand2(options: FFmpegCommandOptions): Promise<number> {
    let uuid = util.generateRandomUUID(true);
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegProgress", options.onFFmpegProgress)
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegFail", options.onFFmpegFail)
    libAddon.JSBind.bindFunction(uuid + "_onFFmpegSuccess", options.onFFmpegSuccess)


    return new Promise<number>((resolve, reject) => {
      try {
        libAddon.executeFFmpegCommandAPP2(uuid, options.cmds.length, options.cmds).then((code: number) => {
          resolve(code)
        }).catch((err: Error) => {
          reject(err)
        })
      } catch (e) {
        reject(e)
      }
    })
  }
}
