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
    # 输出格式: 标签|地区码|数量
    # 使用通用配置 CFST_REGION_PLAN，示例：
    # CFST_REGION_PLAN="HK:HKG:10;SG:SIN:8;US:LAX,SEA,SJC:12;JP:NRT,HND,KIX:6"
    local IFS=';'
    local entry label rest count codes
    for entry in ${CFST_REGION_PLAN:-}; do
        entry="$(echo "$entry" | xargs)"
        [[ -z "$entry" ]] && continue
        [[ "$entry" != *:*:* ]] && continue
        label="${entry%%:*}"
        rest="${entry#*:}"
        count="${rest##*:}"
        codes="${rest%:*}"
        if [[ -n "$label" ]] && [[ -n "$codes" ]] && [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]]; then
            echo "${label}|${codes}|${count}"
        fi
    done
}

main() {
    load_env

    export CFST_WORK_DIR
    export CFST_BIN_DIR="${CFST_WORK_DIR}/.cfst"
    mkdir -p "${CFST_WORK_DIR}" "${CFST_BIN_DIR}"

    local tmp_output="${CFST_BIN_DIR}/.converted.txt"
    local merged_output="${CFST_BIN_DIR}/.merged.txt"
    local deduped_output="${CFST_BIN_DIR}/.deduped.txt"
    local total_count=0
    local region_plan
    local no_result_msg="本次测速无结果，任务已结束（未更新 GitHub 文件）"

    echo "========== CF IP 优选开始 $(date '+%Y-%m-%d %H:%M:%S') =========="

    : > "$merged_output"
    region_plan="$(get_region_plan || true)"

    if [[ -n "$region_plan" ]]; then
        # 分地区配额模式
        while IFS='|' read -r region_tag colo count; do
            local region_file_tag
            [[ -z "$region_tag" ]] && continue
            region_file_tag="$(echo "$region_tag" | sed 's/[^A-Za-z0-9._-]/_/g')"
            echo "[PLAN] ${region_tag}: ${count} 个（${colo}）"

            local run_rc=0
            if run_cfst_once "$colo" "$count" "${CFST_BIN_DIR}/result_${region_file_tag}.csv"; then
                run_rc=0
            else
                run_rc=$?
            fi
            case $run_rc in
                0) ;;
                2)
                    echo "[WARN] ${region_tag} 无可用结果，跳过该区域"
                    continue
                    ;;
                *)
                    fail_with_notify "CF IP 优选失败" "${region_tag} 测速失败，请检查日志"
                    ;;
            esac

            if [[ ! -s "${CFST_RESULT_CSV}" ]]; then
                echo "[WARN] ${region_tag} 结果文件为空，跳过该区域"
                continue
            fi

            if convert_result "$CFST_RESULT_CSV" "$tmp_output" "false" "$count" "$region_tag"; then
                cat "$tmp_output" >> "$merged_output"
            else
                echo "[WARN] ${region_tag} 未获取到可用 IP"
            fi
        done <<< "$region_plan"

        if [[ ! -s "$merged_output" ]]; then
            echo "[INFO] ${no_result_msg}"
            send_notification "CF IP 优选无结果" "按区域测速完成但未找到可用 IP，任务正常结束"
            exit 0
        fi

        dedupe_by_ip "$merged_output" "$deduped_output"
        mv -f "$deduped_output" "$tmp_output"
        total_count="$(awk 'END {print NR+0}' "$tmp_output")"
        CFST_RESULT_COUNT="$total_count"
        export CFST_RESULT_COUNT
    else
        # 兼容单次测速模式
        local run_single_rc=0
        if run_cfst; then
            run_single_rc=0
        else
            run_single_rc=$?
        fi
        case $run_single_rc in
            0) ;;
            2)
                echo "[INFO] ${no_result_msg}"
                send_notification "CF IP 优选无结果" "单次测速无可用 IP，任务正常结束"
                exit 0
                ;;
            *)
                fail_with_notify "CF IP 优选失败" "CloudflareSpeedTest 执行失败，请检查日志"
                ;;
        esac

        if ! convert_result "$CFST_RESULT_CSV" "$tmp_output" "false" "${CFST_IP_COUNT:-10}" "${CFST_REGION_TAG:-}"; then
            echo "[INFO] ${no_result_msg}"
            send_notification "CF IP 优选无结果" "测速完成但未找到符合条件的 IP，任务正常结束"
            exit 0
        fi
    fi

    if ! push_result "$tmp_output"; then
        fail_with_notify "GitHub 同步失败" "结果文件未能 push 到 GitHub，请检查 GITHUB_SSH_KEY 与仓库权限"
    fi

    send_notification "CF IP 优选完成" "成功优选 ${CFST_RESULT_COUNT} 个 IP，已同步至 GitHub"
    echo "========== CF IP 优选完成 =========="
}

main "$@"
