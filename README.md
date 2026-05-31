# CF IP 优选（青龙 + CloudflareSpeedTest）

在 [青龙面板](https://github.com/whyour/qinglong) 定时运行 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)，将优选 IP 写入文件并 push 到 GitHub。

支持两种模式：

- 单次模式：用 `CFST_COLO + CFST_IP_COUNT` 获取一组优选 IP
- 分区域配额模式：按标签分配数量，脚本分区域测速并合并去重

## 输出格式

启用下载测速：

```
104.27.200.69:443#HK-146.23ms-28.64M/s
```

禁用下载测速（不含下载速度及前面的 `-`）：

```
104.27.200.69:443#HK-146.23ms
```

写入文件前会先做优选排序：

- 开启下载测速：按综合分数 `speed * 1000 / (delay + 1)` 从高到低选取（兼顾低延迟和高速度）
- 关闭下载测速：按延迟从低到高选取

## 快速部署

### 1. 创建 GitHub 仓库

将本仓库 push 到 GitHub（例如 `your-user/cf-ips`）。

### 2. 生成 Deploy Key

1. GitHub 仓库 → Settings → Deploy keys → Add deploy key
2. 勾选 **Allow write access**
3. 保存生成的私钥，稍后填入青龙环境变量

### 3. 青龙添加仓库

青龙 → 订阅管理 → 添加订阅：

- 名称：`cf-ips`
- 类型：公开仓库 / 私有仓库
- 链接：`git@github.com:your-user/cf-ips.git`

拉取后脚本位于青龙脚本目录下的 `cf-ips/cf_ips.sh`。

### 4. 配置环境变量

在青龙「环境变量」中添加（参考 `config.example.env`）：

| 变量 | 必填 | 说明 |
|------|------|------|
| `GITHUB_SSH_KEY` | 是 | Deploy Key 私钥完整内容 |
| `GITHUB_REPO` | 建议填 | 可填 `user/repo` 或 SSH 地址；当青龙执行目录不含 `.git` 时为必填（脚本会自动克隆临时仓库后 push） |
| `GITHUB_BRANCH` | 否 | 默认 `main` |
| `CFST_VERSION` | 否 | 固定版本如 `v2.3.5`；留空用 latest |
| `CFST_COLO` | 否 | 地区码，如 `HKG,LAX,SEA`（需 HTTPing） |
| `CFST_REGION_TAG` | 否 | 单次模式输出标签，如 `HK` / `SG` / `US` |
| `CFST_IP_COUNT` | 否 | 优选数量，默认 `10` |
| `CFST_REGION_PLAN` | 推荐 | 通用分区域配置，格式 `标签:地区码列表:数量`，多个用 `;` |
| `CFST_ENABLE_DOWNLOAD` | 否 | `true` / `false`，默认 `true` |
| `CFST_PORT` | 否 | 测速端口，默认 `443`，输出结果会追加 `:端口` |
| `CFST_DOWNLOAD_URL` | 否 | 自定义下载测速地址 |
| `CFST_OUTPUT_FILE` | 否 | 输出文件名，默认 `cf_ips.txt` |

也可在脚本目录创建 `.env` 文件（已被 `.gitignore` 忽略）。

### 5. 添加定时任务

```bash
task cf-ips/cf_ips.sh
```

建议 cron 间隔大于单次测速耗时（如每 6 小时：`0 */6 * * *`）。

## 通知

脚本在以下情况通过青龙 `sendNotify` 推送通知：

- CFST 执行失败
- 测速结果为空（0 条 IP）
- GitHub push 失败
- 成功完成时发送摘要

## 注意事项

- `-cfcolo` 地区筛选仅在 HTTPing 模式下生效；设置 `CFST_COLO` 时脚本会自动加 `-httping`
- 设置 `CFST_REGION_PLAN` 后，脚本按该计划分区域执行测速（推荐）
- 禁用下载测速且未设置地区时，地区码可能为 `N/A`
- `.cfst/` 目录存放 CFST 二进制与临时文件，已加入 `.gitignore`
- 服务器上 HTTPing 并发过高可能被限流，可在 CFST 上游文档中了解 `-n` 参数（本脚本使用默认值）

## 分区域配额示例（推荐）

```bash
CFST_REGION_PLAN="HK:HKG:5;SG:SIN:3;US:LAX,SEA,SJC:4;JP:NRT,HND,KIX:3"
```

上面的配置会按四个标签分别测速，最后合并为一个结果文件并按 IP 去重。  
你也可以扩展任意区域，例如 `EU:FRA,MAD,AMS:6`、`TW:TPE,KHH:4`。

## 目录结构

```
cf-ips/
├── cf_ips.sh              # 主入口
├── config.example.env     # 环境变量示例
├── lib/
│   ├── install_cfst.sh    # 下载/安装 CFST
│   ├── convert_result.sh  # CSV → 自定义格式
│   ├── sync_github.sh     # Git push
│   └── notify.sh          # 青龙通知
└── cf_ips.txt             # 测速结果（由脚本生成并 push）
```

## License

脚本 MIT；CloudflareSpeedTest 遵循 GPL-3.0。
