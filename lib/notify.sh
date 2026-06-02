#!/usr/bin/env bash
# 青龙面板通知封装

send_notification() {
    local title="$1"
    local content="$2"

    if command -v node >/dev/null 2>&1; then
        for notify_script in \
            "/ql/data/scripts/sendNotify.js" \
            "/ql/scripts/sendNotify.js" \
            "${SCRIPT_DIR}/sendNotify.js"; do
            if [[ -f "$notify_script" ]]; then
                if command -v timeout >/dev/null 2>&1; then
                    timeout 20s node "$notify_script" "$title" "$content" 2>/dev/null && return 0
                else
                    node "$notify_script" "$title" "$content" 2>/dev/null && return 0
                fi
            fi
        done
    fi

    echo "[NOTIFY] ${title}: ${content}" >&2
}

fail_with_notify() {
    local title="$1"
    local content="$2"
    send_notification "$title" "$content"
    exit 1
}
