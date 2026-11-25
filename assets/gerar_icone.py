"""Gera o icone do OTSS: um porquinho fucando a "lama" de logs ate achar o erro (linha vermelha).
Desenho original (formas geometricas), sem uso de imagem de terceiros.
Saida: assets/otss.png (1024), assets/otss.ico (16-256) e assets/previa.png (comparacao de tamanhos).
Uso: python assets/gerar_icone.py
     python assets/gerar_icone.py --origem assets/otss-porco-invideo.png   (usa um PNG pronto em vez do desenho)
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

AQUI = Path(__file__).resolve().parent
S = 1024                      # tela de trabalho
CONTORNO = (52, 36, 42, 255)  # marrom bem escuro
ROSA = (246, 168, 186, 255)
ROSA_ESC = (228, 128, 152, 255)
LAMA = (122, 88, 58, 255)
LAMA_CLARA = (168, 128, 88, 255)
ERRO = (220, 38, 38, 255)
W = 34                        # espessura do traco


def elipse(d, caixa, fill, w=W):
    d.ellipse(caixa, fill=CONTORNO)
    x0, y0, x1, y1 = caixa
    d.ellipse((x0 + w, y0 + w, x1 - w, y1 - w), fill=fill)


def desenhar():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Orelhas (atras da cabeca)
    d.polygon([(250, 300), (180, 70), (420, 220)], fill=CONTORNO)
    d.polygon([(275, 270), (220, 130), (385, 225)], fill=ROSA_ESC)
    d.polygon([(774, 300), (844, 70), (604, 220)], fill=CONTORNO)
    d.polygon([(749, 270), (804, 130), (639, 225)], fill=ROSA_ESC)

    # Cabeca
    elipse(d, (190, 170, 834, 740), ROSA)

    # Olhos concentrados, olhando para baixo (pupila no fundo do olho)
    for cx in (390, 634):
        d.ellipse((cx - 44, 380, cx + 44, 468), fill=CONTORNO)
        d.ellipse((cx - 16, 430, cx + 12, 456), fill=(255, 255, 255, 255))

    # Focinho descendo para dentro da lama
    elipse(d, (340, 600, 684, 830), ROSA_ESC)
    for cx in (456, 568):
        d.ellipse((cx - 28, 660, cx + 28, 726), fill=CONTORNO)

    # Lama de logs NA FRENTE: cobre a parte de baixo do focinho (ele esta fucando)
    d.ellipse((30, 700, 994, 1120), fill=CONTORNO)
    d.ellipse((30 + W, 700 + W, 994 - W, 1120 - W), fill=LAMA)
    # linhas de log na lama
    for x0, y, x1 in [(140, 860, 430), (520, 860, 880), (210, 940, 560), (620, 940, 800)]:
        d.rounded_rectangle((x0, y, x1, y + 34), radius=17, fill=LAMA_CLARA)
    # a linha do erro, desenterrada bem na frente do focinho
    d.rounded_rectangle((300, 778, 724, 826), radius=24, fill=ERRO)

    # Respingos de lama levantados pelo focinho
    for x, y, r in [(270, 700, 30), (760, 690, 34), (205, 640, 18), (830, 625, 20), (330, 650, 14)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=CONTORNO)
        d.ellipse((x - r + 8, y - r + 8, x + r - 8, y + r - 8), fill=LAMA)
    return img


def carregar(origem):
    """Abre um PNG pronto e o centraliza numa tela quadrada S x S transparente."""
    img = Image.open(origem).convert('RGBA')
    img.thumbnail((S, S), Image.LANCZOS)
    tela = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    tela.alpha_composite(img, ((S - img.width) // 2, (S - img.height) // 2))
    return tela


def main():
    p = argparse.ArgumentParser(description='Gera o icone do OTSS.')
    p.add_argument('--origem', type=Path, help='PNG pronto para usar no lugar do desenho')
    args = p.parse_args()
    img = carregar(args.origem) if args.origem else desenhar()
    img.save(AQUI / 'otss.png')
    tamanhos = [16, 24, 32, 48, 64, 128, 256]
    img.save(AQUI / 'otss.ico', sizes=[(t, t) for t in tamanhos])

    # Previa: 256 + tamanhos pequenos ampliados (sem suavizar) para avaliar legibilidade
    prev = Image.new('RGBA', (256 + 3 * 136 + 40, 300), (245, 245, 245, 255))
    prev.paste(img.resize((256, 256), Image.LANCZOS), (10, 22), img.resize((256, 256), Image.LANCZOS))
    x = 286
    for t in (48, 32, 16):
        pequeno = img.resize((t, t), Image.LANCZOS)
        grande = pequeno.resize((128, 128), Image.NEAREST)
        prev.paste(grande, (x, 86), grande)
        x += 136
    prev.save(AQUI / 'previa.png')
    print('ok:', AQUI / 'otss.ico')


if __name__ == '__main__':
    main()
