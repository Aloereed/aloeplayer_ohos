# Project instructions

- Run all Flutter, Hvigor, HAP, APP, and HarmonyOS/OHOS compilation commands outside the sandbox. In this environment sandboxed builds can leave `cmd.exe` spinning without launching Dart or producing artifacts.
- Treat `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` as the canonical unsigned HAP output. Verify its timestamp after every HAP build.
