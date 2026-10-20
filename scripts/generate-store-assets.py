"""Compose store artwork from real screenshots. Requires Pillow; no application changes."""
from pathlib import Path
import hashlib
import json
import math
import zipfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/store/mumark-1.0.0'
SOURCE = OUT / 'source'
FONT = Path('C:/Windows/Fonts')
WHITE = '#f4f8ff'
MUTED = '#aec4db'
TEAL = '#9bf0e0'
TAGLINE = '离线写作，轻松编辑与预览'
INTRO = '''木笺 MuMark 是一款本地离线 Markdown 编辑器，适合记录想法、整理笔记和撰写文档。

【专注写作】
支持标题、列表、任务清单、表格、引用、代码块等常用 Markdown 格式，提供查找替换与大纲导航，让长文档更易整理。

【编辑与预览】
支持编辑、预览和适合宽屏的分屏模式。既能专注输入，也能查看文字排版效果。

【本地文件】
通过系统文件选择器打开文档，编辑后保存到原位置。支持最近文件、应用内资料库及恢复草稿，方便继续未完成的写作。

【图文内容】
可插入本地图片和 HTML 内容块。HTML 引用的图片、CSS 可通过系统选择器补齐，合成为离线附件；脚本不执行。

【灵活导出】
支持导出 Markdown、网页 HTML 与图文 ZIP，方便保存和传递内容。需要一起带走图片及内容块时，可选择图文 ZIP。

【舒适界面】
适配 HarmonyOS 手机、平板与 PC/2in1，支持深浅色主题、字号、自动换行和自动保存设置。

无需注册账号，离线使用。把灵感写成文字，让记录成为下一次创作的起点。'''

SLIDES = [
    ('phone', '01-write', '把灵感\n写成文字', '从一句想法，开始一篇好文章。',
     ['MARKDOWN 编辑', '标题 · 列表 · 表格'], 'phone-01-edit.jpeg', '手机模拟器，本轮演示文档'),
    ('phone', '02-preview', '文字落下\n排版即现', '编辑与预览，自在切换。',
     ['轻松预览', '清晰阅读每一段'], 'phone-02-preview.jpeg', '手机模拟器，本轮演示文档'),
    ('phone', '03-outline', '长文有序\n思路清晰', '用大纲，找到下一段的方向。',
     ['大纲导航', '让章节一目了然'], 'phone-03-outline.jpeg', '手机模拟器，本轮演示文档'),
    ('phone', '04-export', '写好的内容\n轻松带走', '为不同场景，选一种交付方式。',
     ['灵活导出', 'Markdown · HTML · 图文 ZIP'], 'phone-04-export.jpeg', '手机模拟器，本轮导出面板'),
    ('tablet', '01-space', '大屏展开\n思路不设限', '编辑与预览，在同一块画布相遇。',
     ['分屏模式', '让输入与阅读并行'], 'tablet-01-split.jpeg', 'API 22 MatePad 真机，2026-10-19 历史截图'),
    ('tablet', '02-content', '不止文字\n图文也出彩', '图片与 HTML 内容块，丰富表达。',
     ['图文内容', '离线附件 · 清晰呈现'], 'tablet-02-preview.jpeg', 'API 22 MatePad 真机，2026-10-20 验收截图'),
    ('tablet', '03-comfort', '你的习惯\n你的写作空间', '主题、字号和换行，由你选择。',
     ['舒适阅读', '轻松调整常用设置'], 'tablet-03-settings.jpeg', 'API 22 MatePad 真机，2026-10-19 历史截图'),
    ('pc', '01-focus', '给灵感\n一张大画布', '让每一个想法，都有展开的空间。',
     ['专注写作', '本地 Markdown 文件'], 'pc-01-edit.png', 'API 26 MateBook 真机，本轮演示；从完整桌面裁取木笺窗口'),
    ('pc', '02-theme', '深浅之间\n找到舒适', '适合自己的界面，让思路更从容。',
     ['深浅主题', '字号 · 换行 · 默认视图'], 'pc-02-settings.jpg', 'API 26 MateBook 真机，2026-10-19 历史截图'),
    ('pc', '03-files', '打开原文件\n继续你的创作', '另存与导出，选择清晰可见。',
     ['本地文件', '保存 · 另存为 · 导出副本'], 'pc-03-actions.jpg', 'API 26 MateBook 真机窄窗，2026-10-19 历史截图'),
]


def font(size, bold=False, latin=False):
    name = ('segoeuib.ttf' if bold else 'segoeui.ttf') if latin else ('msyhbd.ttc' if bold else 'msyh.ttc')
    return ImageFont.truetype(str(FONT / name), size)


def write_text(draw, xy, text, size, color=WHITE, bold=False, spacing=12):
    x, y = xy
    for line in text.split('\n'):
        draw.text((x, y), line, font=font(size, bold), fill=color, anchor='lt')
        y += size + spacing
    return y


def wrap(draw, value, size, width):
    lines, line = [], ''
    for char in value:
        if draw.textlength(line + char, font=font(size)) > width:
            lines.append(line)
            line = char
        else:
            line += char
    return '\n'.join(lines + [line])


def background(size, index):
    # Reuse the brand's actual background artwork, tinted for clear text contrast.
    source = Image.open(ROOT / 'AppScope/resources/base/media/background.png').convert('RGB')
    texture = ImageOps.fit(source, size).filter(ImageFilter.GaussianBlur(80))
    grey = ImageOps.grayscale(texture)
    tint = ImageOps.colorize(grey, '#08162d', ['#165187', '#124863', '#1b4d80'][index % 3]).convert('RGBA')
    base = ImageOps.colorize(Image.linear_gradient('L').resize(size), '#050d1b', '#123c63').convert('RGBA')
    return Image.blend(base, tint, .45)


def brand(canvas, device):
    d = ImageDraw.Draw(canvas)
    portrait = device == 'phone'
    x, y = (76, 70) if portrait else (88, 60)
    bg = Image.open(ROOT / 'AppScope/resources/base/media/background.png').convert('RGBA')
    bg.alpha_composite(Image.open(ROOT / 'AppScope/resources/base/media/foreground.png').convert('RGBA'))
    bg.thumbnail((68, 68))
    mask = Image.new('L', bg.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 67, 67), 14, fill=255)
    canvas.paste(bg, (x, y), mask)
    write_text(d, (x+88, y+2), '木笺', 32, bold=True)
    d.text((x+88, y+43), 'MuMark', font=font(19, latin=True), fill=MUTED, anchor='lt')
    label = {'phone':'PHONE', 'tablet':'TABLET', 'pc':'PC / 2in1'}[device]
    width = d.textlength(label, font=font(22, latin=True))
    d.text((canvas.width-width-80, y+20), label, font=font(22, latin=True), fill=TEAL, anchor='lt')


def frame(canvas, screenshot, box, radius=22):
    x, y, w, h = [int(v) for v in box]
    screen = Image.open(screenshot).convert('RGB')
    screen.thumbnail((w, h), Image.Resampling.LANCZOS)
    x += (w-screen.width)//2
    y += (h-screen.height)//2
    shadow = Image.new('RGBA', canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle((x-12,y-10,x+screen.width+12,y+screen.height+12), radius+8, fill=(0,0,0,180))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
    mask = Image.new('L', screen.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,screen.width-1,screen.height-1), radius, fill=255)
    canvas.paste(screen, (x,y), mask)
    ImageDraw.Draw(canvas).rounded_rectangle((x-2,y-2,x+screen.width+1,y+screen.height+1), radius, outline='#48627c', width=2)
    return {'x':x, 'y':y, 'width':screen.width, 'height':screen.height}


def poster(row, index):
    device, slug, title, subtitle, labels, filename, provenance = row
    size = (1080,1920) if device=='phone' else (1920,1080)
    canvas = background(size, index)
    brand(canvas, device)
    d = ImageDraw.Draw(canvas)
    if device == 'phone':
        first, second = title.split('\n')
        write_text(d, (78,200), first, 104, bold=True)
        bottom = write_text(d, (78,326), second, 104, TEAL, True, spacing=22)
        write_text(d, (82,bottom+22), wrap(d, subtitle, 34, 916), 34, MUTED)
        d.line((82,535,998,535), fill='#35516d', width=2)
        d.text((82,558), labels[0], font=font(24,True), fill=TEAL, anchor='lt')
        # Keep the complete original screenshot visible; no UI retouching or stretching.
        placed = frame(canvas, SOURCE/filename, (120,630,840,1210), 24)
        write_text(d, (82,1870), 'MuMark  /  让记录成为创作的起点', 22, MUTED)
    else:
        title_size = 88 if max(map(len,title.split('\n'))) <= 6 else 76
        first, second = title.split('\n')
        write_text(d, (92,238), first, title_size, bold=True)
        bottom = write_text(d, (92,264+title_size), second, title_size, TEAL, True, spacing=26)
        write_text(d, (96,bottom+28), wrap(d, subtitle, 29, 570), 29, MUTED, spacing=13)
        d.line((96,644,632,644), fill='#35516d', width=2)
        write_text(d, (96,682), labels[0], 31, TEAL, True)
        write_text(d, (96,738), wrap(d, labels[1], 24, 550), 24, MUTED)
        source = Image.open(SOURCE/filename)
        if source.width/source.height < 1:
            placed = frame(canvas, SOURCE/filename, (790,154,1000,850), 18)
        else:
            placed = frame(canvas, SOURCE/filename, (762,192,1080,758), 18)
        d.text((96,948), 'LOCAL.  SIMPLE.  YOURS.', font=font(18,latin=True), fill=MUTED, anchor='lt')
        write_text(d, (96,986), '木笺 MuMark · 本地 Markdown 编辑器', 21, MUTED)
    target = OUT/device/f'{slug}.png'
    target.parent.mkdir(exist_ok=True)
    canvas.convert('RGB').save(target, optimize=True)
    assert Image.open(target).size == size
    assert target.stat().st_size < 5_000_000
    return {'file':str(target.relative_to(OUT)).replace('\\','/'), 'size':size,
            'bytes':target.stat().st_size, 'source':f'source/{filename}',
            'provenance':provenance, 'screenshotPlacement':placed,
            'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}


def contact_sheet(results):
    cells = (640, 440)
    sheet = Image.new('RGB',(1920,cells[1]*math.ceil(len(results)/3)), '#081425')
    d = ImageDraw.Draw(sheet)
    for i,item in enumerate(results):
        pic = Image.open(OUT/item['file']); pic.thumbnail((610,390),Image.Resampling.LANCZOS)
        x,y = (i%3)*640,(i//3)*440
        sheet.paste(pic,(x+(640-pic.width)//2,y+12))
        d.text((x+20,y+410),item['file'],font=font(16,latin=True),fill=WHITE)
    sheet.save(OUT/'preview.jpg',quality=94)


def text_files():
    assert len(TAGLINE)<=17 and len(INTRO)<=8000
    (OUT/'一句话简介.txt').write_text(TAGLINE,encoding='utf-8')
    (OUT/'应用介绍.txt').write_text(INTRO,encoding='utf-8')
    instructions = '''木笺 MuMark 1.0.0 上架素材

此目录只对应用户截图页面的“应用介绍 / 一句话简介 / 手机、平板、PC截图”，没有补写其他后台字段。

1. 语言：简体中文（默认）。
2. 应用名称：木笺。正式包名 com.mumark.app，版本 1.0.0。
3. 应用介绍：复制“应用介绍.txt”。一句话简介：复制“一句话简介.txt”（17 字以内）。
4. 手机选择“竖向截图”：上传 phone 文件夹的 01–04，1080×1920 PNG。
5. 平板选择“横向截图”：上传 tablet 文件夹的 01–03，1920×1080 PNG。
6. PC/2in1 选择“横向截图”：上传 pc 文件夹的 01–03，1920×1080 PNG。
7. 每张均为对应比例、低于 5 MB；每端至少三张。不要把 preview.jpg 总览图当成单张上传。

画面说明：海报外层包含宣传文案和排版。内嵌界面来自实际设备/模拟器截图，仅裁切独立应用窗口、等比缩放或圆角显示，没有改写界面文字或新增虚构按钮。source 是未绘制覆盖的原图，来源详见 manifest.json。手机为本轮模拟器演示；PC 第一张为本轮真机演示，其余 PC/平板沿用已留存真机图，因此示例文件名/时间可能带验收字样。设备不便独占时没有继续操作或虚构新截图。

此页面当前显示的硬性约束已检查；平台是否接受带宣传排版的截图仍以实际上传/审核结果为准。如要求原始截图，请从 source 选择对应真实界面，不要上传本目录的其他清单文件。未执行实际后台上传、保存或提交审核。

重建：在仓库根目录运行 python scripts/generate-store-assets.py，需 Pillow 和 Windows 系统字体。ZIP 由同一脚本生成到 build-logs；包含所有上传图片、文案、来源清单和预览。
'''
    (OUT/'上传说明.txt').write_text(instructions,encoding='utf-8')
    (OUT/'README.md').write_text('# 木笺 1.0.0 上架截图\n\n'
        '应用介绍、一句话简介与三端海报见本目录，上传方式见 上传说明.txt。'
        '所有画面来源与尺寸在 manifest.json，preview.jpg 是总览，source 是真实界面原图。\n\n'
        '手机 4 张竖图（1080×1920），平板与 PC 各 3 张横图（1920×1080）。'
        '每张 PNG 小于 5 MB；未上传或提交审核。\n',encoding='utf-8')


def main():
    OUT.mkdir(exist_ok=True,parents=True)
    results = [poster(row,i) for i,row in enumerate(SLIDES)]
    text_files(); contact_sheet(results)
    manifest = {'date':'2026-10-20','application':'木笺 MuMark','bundleName':'com.mumark.app',
        'version':'1.0.0','tagline':TAGLINE,'taglineCharacters':len(TAGLINE),
        'introductionCharacters':len(INTRO),'images':results,
        'method':'Brand vector layers + typography + unretouched real screenshots; no generated UI',
        'notSubmitted':True}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    archive = ROOT/'build-logs/木笺-1.0.0-上架截图素材.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for path in OUT.rglob('*'):
            if path.is_file(): z.write(path, path.relative_to(OUT))
    print(f'{len(results)} PNG posters verified; tagline={len(TAGLINE)}/17; introduction={len(INTRO)}/8000')
    print(archive)


if __name__ == '__main__': main()
