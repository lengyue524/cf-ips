#!/usr/bin/env bash
# 青龙定时脚本：Cloudflare IP 优选 + GitHub 同步
# 依赖: curl/wget, tar, git, node(通知可选)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFST_WORK_DIR="${CFST_WORK_DIR:-$SCRIPT_DIR}"

source "${SCRIPT_DIR}/lib/notify.sh"
source "${SCRIPT_DIR}/lib/install_cfst.sh"
source "${SCRIPT_DIR}/lib/convert_result.sh"
source "${SCRIPT_DIR}/lib/sync_github.sh"

load_env() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # shellcheck disable=SC1091
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    fi

    # 青龙环境变量中私钥常用 \n 表示换行
    if [[ -n "${GITHUB_SSH_KEY:-}" ]]; then
        GITHUB_SSH_KEY="${GITHUB_SSH_KEY//\\n/$'\n'}"
        export GITHUB_SSH_KEY
    fi
}

main() {
    load_env

    export CFST_WORK_DIR
    export CFST_BIN_DIR="${CFST_WORK_DIR}/.cfst"

    local tmp_output="${CFST_BIN_DIR}/.converted.txt"

    echo "========== CF IP 优选开始 $(date '+%Y-%m-%d %H:%M:%S') =========="

    if ! run_cfst; then
        fail_with_notify "CF IP 优选失败" "CloudflareSpeedTest 执行失败，请检查日志"
    fi

    if ! convert_result "$CFST_RESULT_CSV" "$tmp_output"; then
        fail_with_notify "CF IP 优选无结果" "测速完成但未找到符合条件的 IP，请放宽 CFST_COLO 或测速条件"
    fi

    if ! push_result "$tmp_output"; then
        fail_with_notify "GitHub 同步失败" "结果文件未能 push 到 GitHub，请检查 GITHUB_SSH_KEY 与仓库权限"
    fi

    send_notification "CF IP 优选完成" "成功优选 ${CFST_RESULT_COUNT} 个 IP，已同步至 GitHub"
    echo "========== CF IP 优选完成 =========="
}

main "$@"
