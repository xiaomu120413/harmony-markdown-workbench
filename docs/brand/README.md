# 木笺 MuMark 品牌资源

2026-10-19 用户确认：中文名称“木笺”，英文名称“MuMark”，与木枢、MuTransfer 同属 Mu 系列。
本轮参考 `../ftp/AppScope/resources/base/media/app_icon.svg` 的矢量语言。

- 蓝青底色：`#075AE6 → #087EF0 → #00A6D9`，轻高光。
- 白色折角文档，薄荷色 `#9BF0E0` 笔形强调编辑语义。
- 不用文字，在小尺寸下通过文档与笔识别。
- 两层 1024×1024 PNG 为不透明背景和透明前景，系统负责应用图标遮罩。

母版：`mumark-background.svg`、`mumark-foreground.svg`。
产物：`AppScope/resources/base/media/` 中的 `background.png`、`foreground.png`、`app_icon.svg`。
矢量和产物都在仓库中，不依赖外部图片服务。

重建（Python 需 CairoSVG）：

```powershell
python scripts/gen-icons.py
```

PowerShell 入口调用同一生成脚本，不再包含特定机器的输出目录。
保留原 bundleName 和数据目录，品牌重命名不要求清空文档。
