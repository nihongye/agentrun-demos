# -*- coding: utf-8 -*-
"""
AllInOneSandboxAsync — 本地自定义沙箱
========================================

agentscope-runtime 发布包中暂无 AllInOneSandboxAsync，本文件参照
custom_sandbox.py 的模式进行自定义定义。

通过多重继承 GuiSandboxAsync / FilesystemSandboxAsync / BrowserSandboxAsync
直接复用已有的工具方法，无需在本类中重复声明。后续父类方法有变动，
本类自动获得更新。

公共 API:
  - AllInOneSandboxAsync           — all-in-one 异步沙箱
  - register_template_name(name)   — 将平台沙箱模板名注册到 SandboxRegistry，
                                     使 create_from_pool 以该名称请求平台分配沙箱
"""

import logging
from typing import Optional

from agentscope_runtime.sandbox.utils import build_image_uri, get_platform
from agentscope_runtime.sandbox.registry import SandboxRegistry
from agentscope_runtime.sandbox.enums import SandboxType
from agentscope_runtime.sandbox.box.gui.gui_sandbox import GuiSandboxAsync
from agentscope_runtime.sandbox.box.filesystem.filesystem_sandbox import FilesystemSandboxAsync
from agentscope_runtime.sandbox.box.browser.browser_sandbox import BrowserSandboxAsync
from agentscope_runtime.sandbox.constant import TIMEOUT

logger = logging.getLogger(__name__)

_DEFAULT_SANDBOX_TYPE = "all_in_one_async"


@SandboxRegistry.register(
    build_image_uri("runtime-sandbox-all-in-one"),
    sandbox_type=_DEFAULT_SANDBOX_TYPE,
    security_level="high",
    timeout=TIMEOUT,
    description="All-in-One Sandbox (Async) combining base, gui, filesystem, and browser capabilities",
)
class AllInOneSandboxAsync(GuiSandboxAsync, FilesystemSandboxAsync, BrowserSandboxAsync):
    """All-in-One 异步沙箱，集成代码执行、文件系统、浏览器、GUI 等全套工具。

    方法来源（通过 MRO 自动继承，无需重复声明）：
      - run_ipython_cell / run_shell_command  ← BaseSandboxAsync
      - computer_use / get_desktop_url_async  ← GuiSandboxAsync
      - read_file / write_file / ...          ← FilesystemSandboxAsync
      - browser_* 系列                        ← BrowserSandboxAsync
    """

    def __init__(
        self,
        sandbox_id: Optional[str] = None,
        base_url: Optional[str] = None,
        bearer_token: Optional[str] = None,
        sandbox_type: str = _DEFAULT_SANDBOX_TYPE,
        workspace_dir: Optional[str] = None,
    ):
        super().__init__(
            sandbox_id,
            base_url,
            bearer_token,
            SandboxType(sandbox_type),
            workspace_dir,
        )
        if get_platform() == "linux/arm64":
            logger.warning(
                "\nCompatibility Notice: AllInOne Sandbox may have issues on "
                "arm64 due to computer-use-mcp lacking linux/arm64 support.",
            )


# ===========================================================================
# 注册辅助函数
# ===========================================================================

def register_template_name(template_name: str) -> type:
    """将平台沙箱模板名映射到 AllInOneSandboxAsync，写入 SandboxRegistry。

    由于平台上沙箱模板名称（sandBoxTemplate.name）可能不是默认的
    "all_in_one_async"，调用此函数后：
      - SandboxRegistry.get_classes_by_type(template_name) 返回 AllInOneSandboxAsync
      - 沙箱实例的 create_from_pool_async 以 template_name 请求远程管理器，
        与平台配置保持一致

    Args:
        template_name: 平台上配置的沙箱模板名称，如 "all-in-one"。

    Returns:
        AllInOneSandboxAsync 类本身，方便链式使用。

    Example::

        SandboxClass = register_template_name("all-in-one")
        sandbox = SandboxClass(
            base_url=SANDBOX_MANAGER_URL,
            bearer_token=SANDBOX_MANAGER_TOKEN,
            sandbox_type="all-in-one",
        )
    """
    existing_values = [m.value for m in SandboxType]
    if template_name not in existing_values:
        safe_name = template_name.upper().replace("-", "_").replace(".", "_")
        SandboxType.add_member(safe_name, value=template_name)

    sandbox_type = SandboxType(template_name)
    SandboxRegistry._type_registry[sandbox_type] = AllInOneSandboxAsync
    logger.debug(
        "沙箱模板 [%s] 已注册 → AllInOneSandboxAsync",
        template_name,
    )
    return AllInOneSandboxAsync
