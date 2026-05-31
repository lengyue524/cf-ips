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

get_region_plan() {
    # 输出格式: 区域名|地区码|数量
    local hk_count="${CFST_HK_COUNT:-0}"
    local sg_count="${CFST_SG_COUNT:-0}"
    local us_count="${CFST_US_COUNT:-0}"
    local jp_count="${CFST_JP_COUNT:-0}"

    local hk_codes="${CFST_HK_CODES:-HKG}"
    local sg_codes="${CFST_SG_CODES:-SIN}"
    local us_codes="${CFST_US_CODES:-LAX,SEA,SJC}"
    local jp_codes="${CFST_JP_CODES:-NRT,HND,KIX}"

    if [[ "$hk_count" =~ ^[0-9]+$ ]] && [[ "$hk_count" -gt 0 ]]; then
        echo "香港|${hk_codes}|${hk_count}"
    fi
    if [[ "$sg_count" =~ ^[0-9]+$ ]] && [[ "$sg_count" -gt 0 ]]; then
        echo "新加坡|${sg_codes}|${sg_count}"
    fi
    if [[ "$us_count" =~ ^[0-9]+$ ]] && [[ "$us_count" -gt 0 ]]; then
        echo "美国|${us_codes}|${us_count}"
    fi
    if [[ "$jp_count" =~ ^[0-9]+$ ]] && [[ "$jp_count" -gt 0 ]]; then
        echo "日本|${jp_codes}|${jp_count}"
    fi
}

main() {
    load_env

    export CFST_WORK_DIR
    export CFST_BIN_DIR="${CFST_WORK_DIR}/.cfst"

    local tmp_output="${CFST_BIN_DIR}/.converted.txt"
    local merged_output="${CFST_BIN_DIR}/.merged.txt"
    local deduped_output="${CFST_BIN_DIR}/.deduped.txt"
    local total_count=0
    local region_plan

    echo "========== CF IP 优选开始 $(date '+%Y-%m-%d %H:%M:%S') =========="

    : > "$merged_output"
    region_plan="$(get_region_plan || true)"

    if [[ -n "$region_plan" ]]; then
        # 分地区配额模式
        while IFS='|' read -r region_name colo count; do
            [[ -z "$region_name" ]] && continue
            echo "[PLAN] ${region_name}: ${count} 个（${colo}）"

            if ! run_cfst_once "$colo" "$count" "${CFST_BIN_DIR}/result_${region_name}.csv"; then
                fail_with_notify "CF IP 优选失败" "${region_name} 测速失败，请检查日志"
            fi

            if convert_result "$CFST_RESULT_CSV" "$tmp_output" "false"; then
                cat "$tmp_output" >> "$merged_output"
            else
                echo "[WARN] ${region_name} 未获取到可用 IP"
            fi
        done <<< "$region_plan"

        if [[ ! -s "$merged_output" ]]; then
            fail_with_notify "CF IP 优选无结果" "按地区测速完成，但未找到符合条件的 IP，请调整地区码或数量"
        fi

        dedupe_by_ip "$merged_output" "$deduped_output"
        mv -f "$deduped_output" "$tmp_output"
        total_count="$(awk 'END {print NR+0}' "$tmp_output")"
        CFST_RESULT_COUNT="$total_count"
        export CFST_RESULT_COUNT
    else
        # 兼容单次测速模式
        if ! run_cfst; then
            fail_with_notify "CF IP 优选失败" "CloudflareSpeedTest 执行失败，请检查日志"
        fi

        if ! convert_result "$CFST_RESULT_CSV" "$tmp_output"; then
            fail_with_notify "CF IP 优选无结果" "测速完成但未找到符合条件的 IP，请放宽 CFST_COLO 或测速条件"
        fi
    fi

    if ! push_result "$tmp_output"; then
        fail_with_notify "GitHub 同步失败" "结果文件未能 push 到 GitHub，请检查 GITHUB_SSH_KEY 与仓库权限"
    fi

    send_notification "CF IP 优选完成" "成功优选 ${CFST_RESULT_COUNT} 个 IP，已同步至 GitHub"
    echo "========== CF IP 优选完成 =========="
}

main "$@"
