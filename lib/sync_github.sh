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
    [[ -d "${CFST_WORK_DIR}/.git" ]]
}

normalize_repo_url() {
    local repo="${GITHUB_REPO:-}"
    if [[ -z "$repo" ]]; then
        echo ""
        return 0
    fi
    if [[ "$repo" != git@* && "$repo" != https://* ]]; then
        repo="git@github.com:${repo}.git"
    fi
    echo "$repo"
}

prepare_push_repo() {
    local branch="${GITHUB_BRANCH:-main}"
    local repo_url
    local sync_dir

    if verify_git_repo; then
        PUSH_REPO_DIR="${CFST_WORK_DIR}"
        export PUSH_REPO_DIR
        return 0
    fi

    repo_url="$(normalize_repo_url)"
    if [[ -z "$repo_url" ]]; then
        echo "[GIT] 当前目录无 .git，且未配置 GITHUB_REPO，无法 push" >&2
        return 1
    fi

    sync_dir="${CFST_WORK_DIR}/.git-sync-repo"
    if [[ ! -d "${sync_dir}/.git" ]]; then
        echo "[GIT] 当前目录非仓库，开始克隆远程仓库到临时目录 ..."
        git clone --branch "$branch" "$repo_url" "$sync_dir" || return 1
    else
        git -C "$sync_dir" remote set-url origin "$repo_url"
        git -C "$sync_dir" fetch origin "$branch" || true
        git -C "$sync_dir" checkout "$branch" || git -C "$sync_dir" checkout -b "$branch"
        git -C "$sync_dir" pull --rebase origin "$branch" 2>/dev/null || true
    fi

    PUSH_REPO_DIR="$sync_dir"
    export PUSH_REPO_DIR
}

push_result() {
    local output_file="$1"
    local branch="${GITHUB_BRANCH:-main}"
    local rel_path="${CFST_OUTPUT_FILE:-cf_ips.txt}"
    local target
    local msg="chore: update CF IPs $(date '+%Y-%m-%d %H:%M:%S')"

    setup_ssh || return 1
    prepare_push_repo || return 1

    target="${PUSH_REPO_DIR}/${rel_path}"

    git -C "$PUSH_REPO_DIR" config user.email "cf-ips@qinglong.local"
    git -C "$PUSH_REPO_DIR" config user.name "cf-ips-bot"

    echo "[GIT] 同步远程分支 ..."
    git -C "$PUSH_REPO_DIR" pull --rebase origin "$branch" 2>/dev/null || true

    mkdir -p "$(dirname "$target")"
    cp -f "$output_file" "$target"

    git -C "$PUSH_REPO_DIR" add "$rel_path"

    if git -C "$PUSH_REPO_DIR" diff --cached --quiet; then
        echo "[GIT] 内容无变化，跳过 push"
        return 0
    fi

    git -C "$PUSH_REPO_DIR" commit -m "$msg" || return 1
    git -C "$PUSH_REPO_DIR" push origin "$branch" || return 1

    echo "[GIT] 已 push 到 origin/${branch}:${rel_path}"
}
