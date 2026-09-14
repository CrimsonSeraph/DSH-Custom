#!/usr/bin/env python3
"""代码审查工具：在 DSH 上下文之外读文件、调用本地 coder、只把意见返回。

DSH 调用时只传路径，源文件不进入主模型上下文。
"""

import argparse
import json
import os
import sys
from typing import List

import requests

ROUTER = os.environ.get("LMSTUDIO_ROUTER_BASE", "http://127.0.0.1:1235")
# 单文件读取上限（字符）；避免误读大文件把本地上下文也撑爆
PER_FILE_LIMIT = int(os.environ.get("LOCAL_REVIEW_PER_FILE_LIMIT", "30000"))
# 全部文件总量上限
TOTAL_LIMIT = int(os.environ.get("LOCAL_REVIEW_TOTAL_LIMIT", "80000"))


def read_files(paths: List[str]) -> tuple[dict, str]:
    """读取文件，返回 ({path: content}, error)。任一失败就返回 error。"""
    files = {}
    total = 0
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                content = f.read()
        except (OSError, UnicodeDecodeError) as e:
            return {}, f"读取失败：{p} ({e})"
        if len(content) > PER_FILE_LIMIT:
            content = content[:PER_FILE_LIMIT] + "\n... [truncated]"
        files[p] = content
        total += len(content)
        if total > TOTAL_LIMIT:
            return {}, f"文件总量超限（{total} 字符），请减少文件数或分段审查"
    return files, ""


def build_prompt(files: dict, focus: str) -> str:
    parts = []
    parts.append(
        "你是代码审查员。审查下面的文件，只报告**真正的问题**："
        "bug、边界条件遗漏、安全问题、明显的逻辑错误。"
        "不要报告风格偏好、命名建议、注释多少。"
        "每条问题给出：文件、行号（如能确定）、问题、建议。"
        "如果没问题，直接说「未发现实质问题」。\n"
    )
    if focus:
        parts.append(f"\n审查重点：{focus}\n")
    for path, content in files.items():
        parts.append(f"\n### {path}\n```\n{content}\n```")
    return "\n".join(parts)


def review(paths: List[str], focus: str, mode: str, max_tokens: int) -> str:
    files, err = read_files(paths)
    if err:
        return f"[local_review] {err}"

    prompt = build_prompt(files, focus)
    payload = {
        "model": mode,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.1,
    }
    try:
        resp = requests.post(f"{ROUTER}/v1/chat/completions", json=payload, timeout=300)
        resp.raise_for_status()
    except requests.exceptions.RequestException as e:
        return f"[local_review] 调用本地 coder 失败：{e}"

    data = resp.json()
    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        return f"[local_review] 响应结构异常：{json.dumps(data)[:300]}"
    return content or "[local_review] 本地模型返回空内容"


def main() -> int:
    ap = argparse.ArgumentParser(description="本地代码审查（源文件不进主模型上下文）")
    ap.add_argument("paths", nargs="+", help="要审查的文件路径")
    ap.add_argument("--focus", default="", help="审查重点，如「边界条件」「并发安全」")
    ap.add_argument(
        "--mode", default="coder", help="模型别名：coder（默认）| coder-deep"
    )
    ap.add_argument("--max-tokens", type=int, default=1024)
    args = ap.parse_args()

    print(review(args.paths, args.focus, args.mode, args.max_tokens))
    return 0


if __name__ == "__main__":
    sys.exit(main())
