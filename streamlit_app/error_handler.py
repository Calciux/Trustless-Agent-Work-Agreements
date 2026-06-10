"""
error_handler.py — Centralized error classification and recovery strategy.
"""

from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from caw_types import JobContext, ErrorCategory, RecoveryAction
    from session_state import SessionStateManager


class CAWTimeoutError(Exception):
    """CAW CLI command exceeded timeout."""
    pass


class CAWRejectedError(Exception):
    """User rejected Pact in CAW App."""
    pass


class CAWUnavailableError(Exception):
    """CAW CLI not installed or not running."""
    pass


class LLMAPIError(Exception):
    """LLM API call failed (auth, rate limit, 5xx)."""
    pass


class LLMParseError(Exception):
    """LLM response not valid JSON."""
    pass


class OnChainRevertError(Exception):
    """Transaction reverted on-chain."""
    pass


class OnChainGasError(Exception):
    """Insufficient gas (SETH balance)."""
    pass


class OnChainInsufficientFundsError(Exception):
    """Not enough tokens for operation."""
    pass


class NetworkError(Exception):
    """RPC unavailable, network down."""
    pass


# Mapping of exception types → ErrorCategory
_ERROR_CATEGORY_MAP = {
    CAWTimeoutError:              "caw_timeout",
    CAWRejectedError:            "caw_rejected",
    CAWUnavailableError:         "caw_unavailable",
    LLMAPIError:                 "llm_api_error",
    LLMParseError:               "llm_parse_error",
    OnChainRevertError:          "onchain_revert",
    OnChainGasError:             "onchain_gas",
    OnChainInsufficientFundsError: "onchain_insufficient_funds",
    NetworkError:                "network_error",
}

# Recovery strategies per error category
_RECOVERY_MAP = {
    "caw_timeout":               ("retry",   3,  "CAW 操作超时，已重试 {n} 次。请在 CAW App 中手动确认，或点击 [重试]。"),
    "caw_rejected":             ("prompt_user", 1, "Pact 被拒绝。是否要修改参数重新提交？"),
    "caw_unavailable":          ("fallback", 0, "CAW CLI 未找到。请确认已安装 CAW 并设置 PATH。或开启 Mock 模式进行 UI 测试。"),
    "llm_api_error":            ("retry",   3,  "LLM 服务暂时不可用（{error}），已重试 {n} 次。您可以手动选择操作类型继续。"),
    "llm_parse_error":          ("retry",   1,  "LLM 返回格式异常。请手动确认参数。"),
    "onchain_revert":           ("prompt_user", 1, "链上交易回滚：{reason}。请检查参数后重试。"),
    "onchain_gas":              ("prompt_user", 0, "Gas 不足！当前余额：{balance} SETH。请为钱包充值。"),
    "onchain_insufficient_funds": ("prompt_user", 0, "代币余额不足！需要 {required} {token}，当前余额：{balance} {token}。"),
    "config_error":             ("abort",    0,  "配置错误：{detail}。请检查 .env 文件。"),
    "user_abort":              ("abort",    0,  "操作已取消。当前进度已保存。"),
    "network_error":            ("retry",   3,  "网络不可用（{error}）。请检查网络连接后重试。"),
    "unknown_error":            ("prompt_user", 0, "未知错误：{error}。请重试或报告此问题。"),
}


class ErrorHandler:
    """
    Central error handler: classifies exceptions, determines recovery
    strategy, tracks retry counts, and generates user-facing messages.
    """

    def __init__(self, max_retries: int = 3):
        self.max_retries = max_retries
        self._retry_counts: dict = {}  # category -> count

    # ------------------------------------------------------------------
    # Classification
    # ------------------------------------------------------------------

    def classify(self, exception: Exception) -> str:
        """Classify an exception into an ErrorCategory string."""
        for exc_type, category in _ERROR_CATEGORY_MAP.items():
            if isinstance(exception, exc_type):
                return category

        # Heuristic classification from message
        msg = str(exception).lower()
        if "timeout" in msg:
            return "caw_timeout"
        if "reject" in msg:
            return "caw_rejected"
        if "rate limit" in msg or "429" in msg:
            return "llm_api_error"
        if "revert" in msg:
            return "onchain_revert"
        if "gas" in msg:
            return "onchain_gas"
        if "insufficient" in msg:
            return "onchain_insufficient_funds"
        if "network" in msg or "connection" in msg:
            return "network_error"
        if "config" in msg or "api_key" in msg:
            return "config_error"

        return "unknown_error"

    # ------------------------------------------------------------------
    # Recovery
    # ------------------------------------------------------------------

    def get_recovery_action(self, category: str) -> str:
        """Return the RecoveryAction for a given error category."""
        return _RECOVERY_MAP.get(category, ("prompt_user", 0, ""))[0]

    def should_retry(self, category: str) -> bool:
        """Check if retry limit has been reached for this category."""
        max_r = _RECOVERY_MAP.get(category, ("retry", 0, ""))[1]
        if max_r == 0:
            return False
        current = self._retry_counts.get(category, 0)
        return current < max_r

    def record_retry(self, category: str) -> None:
        """Increment retry counter for a category."""
        self._retry_counts[category] = self._retry_counts.get(category, 0) + 1

    def reset_retries(self) -> None:
        """Reset all retry counters (called on new workflow)."""
        self._retry_counts.clear()

    # ------------------------------------------------------------------
    # User messages
    # ------------------------------------------------------------------

    def get_user_message(self, exception: Exception, **kwargs) -> str:
        """Generate a user-friendly error message."""
        category = self.classify(exception)
        _, _, template = _RECOVERY_MAP.get(category, ("", 0, "未知错误：{error}"))
        n = self._retry_counts.get(category, 0)
        msg = template.format(
            error=str(exception),
            n=n,
            reason=str(exception),
            **kwargs
        )
        return msg

    # ------------------------------------------------------------------
    # Unified handler
    # ------------------------------------------------------------------

    def handle(
        self,
        error: Exception,
        session: "SessionStateManager",
        **kwargs
    ) -> str:
        """
        Determine recovery action and update session.
        Returns the recovery action string.
        """
        category = self.classify(error)
        action = self.get_recovery_action(category)
        message = self.get_user_message(error, **kwargs)

        # Log to session
        session.add_log_entry("ERROR", message)

        # If retryable, increment counter
        if action == "retry":
            self.record_retry(category)
            if not self.should_retry(category):
                action = "prompt_user"

        return action
