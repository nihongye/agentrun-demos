# -*- coding: utf-8 -*-
"""
AgentScope Skills Sandbox Demo 配置文件
========================================

本文件是用户最主要的在线调试入口，支持以下修改：
  - SYS_PROMPT：调整助手的系统人设与行为风格
  - SKILLS_DIR：skills 目录路径（镜像内默认 /app/skills）
  - SANDBOX_SKILLS_DIR：skills 在沙箱内的挂载路径
  - DISABLED_SKILLS：禁用部分 skill（按 name 字段匹配）

沙箱及模型相关配置通过环境变量注入，详见 README.md 中的"环境变量参考"。

关键环境变量：
  ALL_IN_ONE_SANDBOX_NAME    平台沙箱模板名称（必填）
  SANDBOX_MANAGER_URL        沙箱管理器地址（必填）
  SANDBOX_MANAGER_TOKEN      沙箱管理器访问凭证（可选）
"""

import os

# ---------------------------------------------------------------------------
# 【在线调试演示】系统提示词 (SYS_PROMPT)
# ---------------------------------------------------------------------------
# 系统提示词从外部 Markdown 文件加载，便于独立编辑和版本管理
_SYS_PROMPT_FILE = os.path.join(os.path.dirname(__file__), "system-prompt.md")

def _load_sys_prompt() -> str:
    """从 system-prompt.md 加载系统提示词，跳过文件开头的 YAML-style 注释行。"""
    try:
        with open(_SYS_PROMPT_FILE, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        raise FileNotFoundError(
            f"系统提示词文件不存在: {_SYS_PROMPT_FILE}\n"
            "请确保 system-prompt.md 与 config.py 在同一目录下。"
        )

SYS_PROMPT: str = _load_sys_prompt()

# ---------------------------------------------------------------------------
# 沙箱模板名称（从环境变量读取）
# ---------------------------------------------------------------------------
# 对应平台 YAML 中 sandBoxTemplate.name 字段。
# 代码启动时通过 register_template_name() 将其注册到 SandboxRegistry，
# 使 create_from_pool 以该名称向远程沙箱管理器请求分配实例。
SANDBOX_TEMPLATE_NAME: str = os.environ.get("ALL_IN_ONE_SANDBOX_NAME", "all-in-one")

# ---------------------------------------------------------------------------
# Skills 目录配置
# ---------------------------------------------------------------------------

# 本地 skills 目录（镜像内打包路径，用于启动时上传到沙箱）
SKILLS_DIR: str = os.path.join(os.path.dirname(__file__), "skills")

# skills 在沙箱工作区内的目标路径（沙箱 workspace 根为 /workspace）
SANDBOX_SKILLS_DIR: str = "/workspace/skills"

# 禁用的 skills（填写 SKILL.md 中 name 字段的值，留空则全部启用）
# 示例：DISABLED_SKILLS = ["slack-gif-creator", "claude-api"]
DISABLED_SKILLS: list[str] = []
