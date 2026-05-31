#!/usr/bin/env bash
# GitHub SSH 配置与 push

setup_ssh() {
    local ssh_dir="${HOME}/.ssh"
    local key_file="${ssh_dir}/cf_ips_deploy_key"

    if [[ -z "${GITHUB_SSH_KEY}" ]]; then
        echo "[GIT] 未配置 GITHUB_SSH_KEY" >&2
        return 1
    fi

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    printf '%s\n' "$GITHUB_SSH_KEY" > "$key_file"
    chmod 600 "$key_file"

    if ! grep -q "Host github.com" "${ssh_dir}/config" 2>/dev/null; then
        cat >> "${ssh_dir}/config" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ${key_file}
    StrictHostKeyChecking accept-new
EOF
        chmod 600 "${ssh_dir}/config"
    fi

    export GIT_SSH_COMMAND="ssh -i ${key_file} -o StrictHostKeyChecking=accept-new"
}

verify_git_repo() {
    if [[ ! -d "${CFST_WORK_DIR}/.git" ]]; then
        echo "[GIT] 当前目录不是 git 仓库，请先在青龙中添加本仓库订阅" >&2
        return 1
    fi
}

push_result() {
    local output_file="$1"
    local branch="${GITHUB_BRANCH:-main}"
    local rel_path="${CFST_OUTPUT_FILE:-cf_ips.txt}"
    local target="${CFST_WORK_DIR}/${rel_path}"
    local msg="chore: update CF IPs $(date '+%Y-%m-%d %H:%M:%S')"

    setup_ssh || return 1
    verify_git_repo || return 1

    git -C "$CFST_WORK_DIR" config user.email "cf-ips@qinglong.local"
    git -C "$CFST_WORK_DIR" config user.name "cf-ips-bot"

    echo "[GIT] 同步远程分支 ..."
    git -C "$CFST_WORK_DIR" pull --rebase origin "$branch" 2>/dev/null || true

    mkdir -p "$(dirname "$target")"
    cp -f "$output_file" "$target"

    git -C "$CFST_WORK_DIR" add "$rel_path"

    if git -C "$CFST_WORK_DIR" diff --cached --quiet; then
        echo "[GIT] 内容无变化，跳过 push"
        return 0
    fi

    git -C "$CFST_WORK_DIR" commit -m "$msg" || return 1
    git -C "$CFST_WORK_DIR" push origin "$branch" || return 1

    echo "[GIT] 已 push 到 origin/${branch}:${rel_path}"
}
