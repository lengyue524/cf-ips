#!/usr/bin/env bash
# 下载并安装 CloudflareSpeedTest 可执行文件

CFST_BIN_DIR="${CFST_WORK_DIR}/.cfst"
CFST_BIN="${CFST_BIN_DIR}/cfst"

detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv6l) echo "arm" ;;
        i386|i686) echo "386" ;;
        *)
            echo "unsupported architecture: ${machine}" >&2
            return 1
            ;;
    esac
}

get_latest_version() {
    curl -fsSL "https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null \
        || wget -qO- "https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+'
}

install_cfst() {
    local arch tarball url version extract_name

    arch="$(detect_arch)" || return 1
    mkdir -p "$CFST_BIN_DIR"

    if [[ -n "${CFST_VERSION}" ]]; then
        version="${CFST_VERSION#v}"
        version="v${version#v}"
        url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/${version}/cfst_linux_${arch}.tar.gz"
    else
        url="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/cfst_linux_${arch}.tar.gz"
        version="latest"
    fi

    tarball="${CFST_BIN_DIR}/cfst_linux_${arch}.tar.gz"
    echo "[CFST] 下载 ${version} (${arch}) ..."

    if ! curl -fsSL -o "$tarball" "$url" 2>/dev/null; then
        if ! wget -q -O "$tarball" "$url"; then
            echo "[CFST] 下载失败: ${url}" >&2
            return 1
        fi
    fi

    tar -zxf "$tarball" -C "$CFST_BIN_DIR" || return 1
    chmod +x "$CFST_BIN"

    if [[ ! -x "$CFST_BIN" ]]; then
        echo "[CFST] 解压后未找到可执行文件" >&2
        return 1
    fi

    echo "[CFST] 安装完成: $(${CFST_BIN} -v 2>/dev/null | head -1 || echo unknown)"
}

ensure_cfst() {
    if [[ -x "$CFST_BIN" ]]; then
        echo "[CFST] 使用已有二进制: ${CFST_BIN}"
        return 0
    fi
    install_cfst
}

build_cfst_args() {
    local -n _args=$1
    local csv_file="$2"
    local ip_count="$3"
    local colo="$4"
    local enable_download="${CFST_ENABLE_DOWNLOAD:-true}"
    local test_port="${CFST_PORT:-443}"

    _args=(-f "${CFST_BIN_DIR}/ip.txt" -o "$csv_file")
    _args+=(-tp "$test_port")

    if [[ "${enable_download}" == "true" || "${enable_download}" == "1" ]]; then
        _args+=(-p 0 -dn "$ip_count")
    else
        _args+=(-dd -p "$ip_count")
    fi

    if [[ -n "${colo}" ]]; then
        _args+=(-httping -cfcolo "${colo}")
    elif [[ -n "${CFST_COLO:-}" ]]; then
        _args+=(-httping -cfcolo "${CFST_COLO}")
    fi

    if [[ -n "${CFST_DOWNLOAD_URL:-}" ]]; then
        _args+=(-url "${CFST_DOWNLOAD_URL}")
    fi
}

run_cfst_once() {
    local colo="${1:-}"
    local ip_count="${2:-${CFST_IP_COUNT:-10}}"
    local csv_file="${3:-${CFST_BIN_DIR}/result.csv}"
    local -a args=()

    ensure_cfst || return 1

    if [[ ! -f "${CFST_BIN_DIR}/ip.txt" ]]; then
        echo "[CFST] 缺少 ip.txt，请重新安装 CFST" >&2
        return 1
    fi

    build_cfst_args args "$csv_file" "$ip_count" "$colo"

    echo "[CFST] 执行: ${CFST_BIN} ${args[*]}"
    rm -f "$csv_file"

    (cd "$CFST_BIN_DIR" && "$CFST_BIN" "${args[@]}") || return 1

    if [[ ! -f "$csv_file" ]]; then
        echo "[CFST] 未生成结果文件 result.csv" >&2
        return 1
    fi

    CFST_RESULT_CSV="$csv_file"
    export CFST_RESULT_CSV
}

run_cfst() {
    run_cfst_once "${CFST_COLO:-}" "${CFST_IP_COUNT:-10}" "${CFST_BIN_DIR}/result.csv"
}
