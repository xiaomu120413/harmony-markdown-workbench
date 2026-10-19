"""Render the reviewed Mu-series vectors; requires CairoSVG. No machine-specific paths."""
from pathlib import Path
import cairosvg

root = Path(__file__).resolve().parent.parent
source = root / 'docs' / 'brand'
target = root / 'AppScope' / 'resources' / 'base' / 'media'
for layer in ('background', 'foreground'):
    cairosvg.svg2png(url=str(source / f'mumark-{layer}.svg'),
                    write_to=str(target / f'{layer}.png'), output_width=1024, output_height=1024)
background = (source / 'mumark-background.svg').read_text(encoding='utf-8')
foreground = (source / 'mumark-foreground.svg').read_text(encoding='utf-8')
combined = background.replace('</svg>', foreground[foreground.index('>') + 1:])
(target / 'app_icon.svg').write_text(combined, encoding='utf-8')
print('MuMark icon layers and SVG generated')
