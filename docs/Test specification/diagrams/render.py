#!/usr/bin/env python3
"""DOTファイルと共通スタイル設定（diagram-style.json）から、構成図のSVGを生成するスクリプト。

特定の案件・図（BlueCom等）のファイル名には依存しない。
使い方の詳細はこのフォルダの README.md を参照すること。

使用例：
    python3 render.py BlueCom試験構成図.dot
    python3 render.py templates/basic-connection.dot -o /tmp/sample.svg
    python3 render.py 図A.dot 図B.dot 図C.dot
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_STYLE_PATH = SCRIPT_DIR / "diagram-style.json"

REQUIRED_STYLE_KEYS = [
    "font",
    "fontSize",
    "fontColor",
    "fillColor",
    "strokeColor",
    "strokeWidth",
    "cornerRounded",
    "edgeColor",
    "edgeWidth",
    "nodeSpacing",
]


def find_dot_executable() -> str:
    """Graphvizの`dot`実行ファイルを探す。見つからない場合は分かりやすいエラーで終了する。"""
    dot_path = shutil.which("dot")
    if dot_path:
        return dot_path

    print(
        "エラー：Graphvizの`dot`コマンドが見つかりません。\n"
        "このスクリプトはDOTファイルからSVGを生成するためにGraphvizを使用します。\n"
        "\n"
        "【原因】\n"
        "  Graphvizがインストールされていない、またはPATHが通っていません。\n"
        "\n"
        "【必要な準備】\n"
        "  以下のいずれかの方法でGraphvizをインストールしてください。\n"
        "    - Ubuntu/Debian系 : sudo apt-get update && sudo apt-get install -y graphviz\n"
        "    - macOS (Homebrew): brew install graphviz\n"
        "    - Windows         : https://graphviz.org/download/ からインストーラーを入手\n"
        "\n"
        "  インストール後、ターミナルで `dot -V` を実行し、バージョンが表示されることを確認してください。",
        file=sys.stderr,
    )
    sys.exit(1)


def load_style(style_path: Path) -> dict:
    """共通スタイル設定ファイル（JSON）を読み込む。"""
    if not style_path.is_file():
        print(
            f"エラー：共通スタイル設定ファイルが見つかりません：{style_path}\n"
            "diagram-style.json の場所を --style オプションで指定するか、"
            "このファイルをdiagramsフォルダ内に用意してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        with style_path.open("r", encoding="utf-8") as f:
            style = json.load(f)
    except json.JSONDecodeError as e:
        print(
            f"エラー：共通スタイル設定ファイル（{style_path}）の形式が正しいJSONではありません。\n{e}",
            file=sys.stderr,
        )
        sys.exit(1)

    missing = [key for key in REQUIRED_STYLE_KEYS if key not in style]
    if missing:
        print(
            f"エラー：共通スタイル設定ファイル（{style_path}）に次の項目が不足しています：{', '.join(missing)}",
            file=sys.stderr,
        )
        sys.exit(1)

    return style


def build_default_attribute_args(style: dict) -> list:
    """共通スタイル設定を、`dot`コマンドのデフォルト属性オプション（-G/-N/-E）へ変換する。

    DOTファイル自体にはスタイルを記載せず、構成（図形・接続関係）だけを記載する方針のため、
    スタイルはすべてここでコマンドライン引数として与える。
    """
    node_style = "filled"
    if style["cornerRounded"]:
        node_style = "rounded," + node_style

    args = [
        # 図形（ノード）全体のデフォルト設定
        "-Nshape=box",
        f"-Nstyle={node_style}",
        f"-Nfontname={style['font']}",
        f"-Nfontsize={style['fontSize']}",
        f"-Nfontcolor={style['fontColor']}",
        f"-Nfillcolor={style['fillColor']}",
        f"-Ncolor={style['strokeColor']}",
        f"-Npenwidth={style['strokeWidth']}",
        # 接続線（エッジ）全体のデフォルト設定
        f"-Efontname={style['font']}",
        f"-Efontsize={style['fontSize']}",
        f"-Efontcolor={style['fontColor']}",
        f"-Ecolor={style['edgeColor']}",
        f"-Epenwidth={style['edgeWidth']}",
        # 図形間の間隔（同じ列内の間隔・列と列の間隔の両方に同じ値を適用する）
        f"-Gnodesep={style['nodeSpacing']}",
        f"-Granksep={style['nodeSpacing']}",
        # グラフ全体のラベル等に使うフォント
        f"-Gfontname={style['font']}",
        f"-Gfontsize={style['fontSize']}",
    ]
    return args


def render_one(dot_executable: str, dot_file: Path, output_file: Path, style_args: list) -> None:
    if not dot_file.is_file():
        print(f"エラー：DOTファイルが見つかりません：{dot_file}", file=sys.stderr)
        sys.exit(1)

    command = [dot_executable, "-Tsvg", *style_args, str(dot_file), "-o", str(output_file)]

    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        print(
            f"エラー：Graphvizによる生成に失敗しました：{dot_file}\n"
            f"--- dotコマンドのエラー出力 ---\n{result.stderr}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"生成しました：{dot_file} → {output_file}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="DOTファイルと共通スタイル設定からSVGを生成する。"
    )
    parser.add_argument(
        "dot_files",
        nargs="+",
        help="入力するDOTファイルのパス（複数指定可）。日本語ファイル名も使用できる。",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="出力するSVGファイルのパス。DOTファイルを複数指定した場合は使用できない（各DOTファイルと同じ場所・同じ名前で自動的に生成する）。",
    )
    parser.add_argument(
        "--style",
        default=str(DEFAULT_STYLE_PATH),
        help=f"共通スタイル設定ファイル（JSON）のパス。省略時は {DEFAULT_STYLE_PATH} を使用する。",
    )
    args = parser.parse_args()

    if args.output and len(args.dot_files) > 1:
        print(
            "エラー：-o/--output は、DOTファイルを1つだけ指定した場合のみ使用できます。",
            file=sys.stderr,
        )
        sys.exit(1)

    dot_executable = find_dot_executable()
    style = load_style(Path(args.style))
    style_args = build_default_attribute_args(style)

    for dot_file_arg in args.dot_files:
        dot_file = Path(dot_file_arg)
        if args.output:
            output_file = Path(args.output)
        else:
            output_file = dot_file.with_suffix(".svg")
        render_one(dot_executable, dot_file, output_file, style_args)


if __name__ == "__main__":
    main()
