#!/usr/bin/env bash
# 将 CFST 的 result.csv 转换为自定义格式

convert_result() {
    local csv_file="$1"
    local output_file="$2"
    local append_mode="${3:-false}"
    local max_count="${4:-0}"
    local enable_download="${CFST_ENABLE_DOWNLOAD:-true}"
    local tmp_rank
    local tmp_selected
    local line_count=0

    if [[ ! -f "$csv_file" ]]; then
        echo "[CONVERT] 找不到 CSV: ${csv_file}" >&2
        return 1
    fi

    if [[ "$append_mode" != "true" ]]; then
        : > "$output_file"
    fi

    tmp_rank="${output_file}.rank.$$"
    tmp_selected="${output_file}.selected.$$"

    if [[ "${enable_download}" == "true" || "${enable_download}" == "1" ]]; then
        # 下载测速开启时，按综合分数排序：
        # score = speed * 1000 / (delay + 1)
        # 分数越高表示下载速度更快且延迟更低。
        awk -F',' '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            NR == 1 { next }
            NF < 7 { next }
            {
                ip = trim($1); delay = trim($5); speed = trim($6); region = trim($7);
                if (ip == "" || delay == "" || speed == "") next;
                if (region == "" || region == "N/A") region = "N/A";
                d = delay + 0; s = speed + 0;
                score = (s * 1000.0) / (d + 1.0);
                line = sprintf("%s#%s-%sms-%sM/s", ip, region, delay, speed);
                printf("%.6f\t%s\n", score, line);
            }
        ' "$csv_file" | sort -t $'\t' -k1,1nr > "$tmp_rank"
    else
        # 未开启下载测速时，仅按延迟从低到高选取。
        awk -F',' '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            NR == 1 { next }
            NF < 7 { next }
            {
                ip = trim($1); delay = trim($5); region = trim($7);
                if (ip == "" || delay == "") next;
                if (region == "" || region == "N/A") region = "N/A";
                d = delay + 0;
                line = sprintf("%s#%s-%sms", ip, region, delay);
                printf("%.6f\t%s\n", d, line);
            }
        ' "$csv_file" | sort -t $'\t' -k1,1n > "$tmp_rank"
    fi

    if [[ "$max_count" =~ ^[0-9]+$ ]] && [[ "$max_count" -gt 0 ]]; then
        awk -F'\t' 'NR <= max { print $2 }' max="$max_count" "$tmp_rank" > "$tmp_selected"
    else
        awk -F'\t' '{ print $2 }' "$tmp_rank" > "$tmp_selected"
    fi

    cat "$tmp_selected" >> "$output_file"
    line_count="$(awk 'END {print NR+0}' "$tmp_selected")"

    rm -f "$tmp_rank" "$tmp_selected"

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
