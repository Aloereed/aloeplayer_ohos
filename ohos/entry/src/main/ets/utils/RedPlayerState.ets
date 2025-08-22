/*
 * @Author: 
 * @Date: 2025-05-31 11:07:32
 * @LastEditors: 
 * @LastEditTime: 2025-05-31 11:07:38
 * @Description: file content
 */
//红薯播放器常用设置项
export default class RedPlayerStateHolder {
  videoDuration: number = 0
  videoPosition: number = 0
  videoWidth: number = 0
  videoHeight: number = 0
  videoViewWidth: Length = '100%'
  videoViewHeight: Length = '100%'
  url: string = ''
  isStart: boolean = false
  speedIndex: number = 1
  videoCodec: string = ''
  audioCodec: string = ''
}