# ClankerNPU 固件 → 可选插件包 改造说明

把原来「现编完塞进 `files/lib/firmware/airoha/` 覆盖 rootfs」的做法，换成
**生成标准 OpenWrt 包**，于是可以直接用 config 符号勾选：

```sh
CONFIG_PACKAGE_airoha-en7581-mt7916-npu-firmware=y
```

## 改了什么

| 文件 | 变动 |
|---|---|
| `scripts/gen-npu-fw-package.sh` | **新增**。调 `build-npu-fw.sh` 编译 → 生成 `package/custom/airoha-<soc>-<wifi>-npu-firmware/`（Makefile + `src/*.bin`）→ 写 `npu-fw.env` / `npu-fw-packages.txt` |
| `scripts/strip-default-npu-fw.sh` | **新增**。把 `airoha-{en7581,en7581-mt7996,an7583}-npu-firmware` 从 `target/linux/airoha/**` 的 `DEFAULT_PACKAGES` / `DEVICE_PACKAGES` 里摘掉 |
| `packages/npu-clanker-template/Makefile.in` | **新增**。包 Makefile 模板（`@PKG_NAME@` / `@FW_PREFIX@` / `@CONFLICTS@` 等占位符） |
| `.github/workflows/build-ponwrt.yml` | 新增 4.5 步；5.5 改为生成包 + re-index feed；7.5 重写为统一写 `CONFIG_PACKAGE_*`；9 步校验包符号 |
| `README.md` | 新增「ClankerNPU 固件现在是可选插件包」章节 |

## 包名规则

`airoha-<soc>-<wifi>-npu-firmware`

- AN7581：`airoha-en7581-mt7916-npu-firmware` / `-mt7992-` / `airoha-en7581-mt7996-clanker-npu-firmware`
- AN7583：`airoha-an7583-{mt7916,mt7992,mt7993,mt7996,nowifi}-npu-firmware`
- AN7552：`airoha-an7552-{mt7916,mt7991,mt7993}-npu-firmware`

> AN7581+MT7996 与 linux-firmware 已有的 `airoha-en7581-mt7996-npu-firmware` 重名，
> 生成脚本自动改名加 `-clanker-`，避免包符号冲突。

## 为什么必须摘 DEFAULT_PACKAGES

`airoha-en7581-npu-firmware` 是 an7581 subtarget 的 `DEFAULT_PACKAGE`，
`make defconfig` 会强制拉回 `=y`。它和 ClankerNPU 包装的是同一批文件名
（`/lib/firmware/airoha/<prefix>_npu_{rv32,data}.bin`），两个包同时进 rootfs 时
谁生效取决于安装顺序 —— 不可控。

摘掉之后装哪个完全由 `.config` 决定。包符号本身还在，`npu_fw=stock` 照样能 `=y` 勾上。

## 怎么用

| 场景 | 做法 |
|---|---|
| 默认 | `npu_fw=clanker` + `npu_wifi=auto`，工作流自动写入 `CONFIG_PACKAGE_airoha-en7581-mt7916-npu-firmware=y` |
| 手动指定变体 | 在 `configs/<机型>.config` 里直接写 `CONFIG_PACKAGE_airoha-en7581-mt7992-npu-firmware=y`，7.5 步检测到就沿用 |
| 把所有变体都编成可选包 | `npu_wifi=all`（`npu_default_wifi` 决定默认勾哪个），之后自己改 configs 挑 |
| 完全不装固件 | `npu_fw=none` |

## 关于 `CONFIG_DEFAULT_` / `CONFIG_MODULE_DEFAULT_`

日志里常看到这两行跟 `CONFIG_PACKAGE_` 一起出现：

```
CONFIG_DEFAULT_airoha-en7581-npu-firmware=y
CONFIG_MODULE_DEFAULT_airoha-en7581-npu-firmware=y
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y
```

前两个是 `DEFAULT_PACKAGES` 生成的门控符号，`CONFIG_PACKAGE_x` 的
`default y if DEFAULT_x` 靠它触发。7.5 步会把这三类前缀**全部**写成
`is not set`（只有选中项写 `=y`），所以即使 4.5 的摘除因 ponwrt 改了
`target.mk` 结构而失效，defconfig 也不会把 stock 固件拉回来。

> ponwrt 基座 config 里大小写不一致（写成 `airoha-en7581-MT7996-npu-firmware`），
> 脚本一律转小写再比对，不会漏。

## 易踩的坑

**包目录生成了，但固件里没有固件文件，且不报错** —— 因为 `CONFIG_PACKAGE_xxx`
符号不存在，defconfig 把 `=y` 当无效符号静默删掉。

防护已经做了三层：

1. 5.5 步生成包后立刻 `rm -f tmp/.packageinfo` + `feeds update custom` + `feeds install -a`，并打印 `package/feeds/custom/` 下的链接；
2. 9 步在 defconfig 后强制校验选中符号仍是 `=y`，否则带 5 条排查线索直接失败；
3. `npu_fw_files_fallback=true` 可额外把镜像铺进 `files/lib/firmware/airoha` 兜底
   （默认 `false` —— 开了以后包置 `n` 也会生效，破坏「可选」语义，仅排查用）。

## 回滚

把 `npu_fw` 选成 `stock` 即可回到 linux-firmware 官方固件；
想彻底回到旧行为，用 git 还原 `.github/workflows/build-ponwrt.yml`
并恢复 `packages/airoha-npu-clanker-firmware/` 即可。
