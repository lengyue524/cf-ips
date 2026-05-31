#!/usr/bin/env bash
# 将 CFST 的 result.csv 转换为自定义格式

convert_result() {
    local csv_file="$1"
    local output_file="$2"
    local append_mode="${3:-false}"
    local max_count="${4:-0}"
    local enable_download="${CFST_ENABLE_DOWNLOAD:-true}"
    local line_count=0

    if [[ ! -f "$csv_file" ]]; then
        echo "[CONVERT] 找不到 CSV: ${csv_file}" >&2
        return 1
    fi

    if [[ "$append_mode" != "true" ]]; then
        : > "$output_file"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$max_count" =~ ^[0-9]+$ ]] && [[ "$max_count" -gt 0 ]] && [[ "$line_count" -ge "$max_count" ]]; then
            break
        fi

        # 跳过表头
        [[ "$line" == *"IP 地址"* || "$line" == *"IP,"* ]] && continue
        [[ -z "$line" ]] && continue

        local ip sent recv loss delay speed region
        IFS=',' read -r ip sent recv loss delay speed region <<< "$line"

        ip="$(echo "$ip" | xargs)"
        delay="$(echo "$delay" | xargs)"
        speed="$(echo "$speed" | xargs)"
        region="$(echo "$region" | xargs)"

        [[ -z "$ip" ]] && continue
        [[ -z "$region" || "$region" == "N/A" ]] && region="N/A"

        if [[ "${enable_download}" == "true" || "${enable_download}" == "1" ]]; then
            printf '%s#%s-%sms-%sM/s\n' "$ip" "$region" "$delay" "$speed" >> "$output_file"
        else
            printf '%s#%s-%sms\n' "$ip" "$region" "$delay" >> "$output_file"
        fi
        ((line_count++)) || true
    done < "$csv_file"

    echo "[CONVERT] 已写入 ${line_count} 条记录 -> ${output_file}"
    CFST_RESULT_COUNT=$line_count
    export CFST_RESULT_COUNT

    if [[ "$line_count" -eq 0 ]]; then
        return 1
    fi
    return 0
}

dedupe_by_ip() {
    local input_file="$1"
    local output_file="$2"

    awk -F'#' '!seen[$1]++' "$input_file" > "$output_file"
}
