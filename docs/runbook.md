# 个人主页留言系统 · 配置运行手册

> 本文件只记录「配置项放在哪里、怎么改、怎么验证」，**不含任何密钥**。
> 密钥请存到密码管理器（例如 macOS 钥匙串 / 1Password / Bitwarden），不要写进本仓库。

## 1. 系统组成

| 部分 | 位置 | 说明 |
| --- | --- | --- |
| 主页 | 本仓库 `index.html` | 静态页面，GitHub Pages 发布 |
| 管理页 | 本仓库 `admin.html` | 管理员登录后查看 / 标记留言 |
| 前端配置 | 本仓库 `assets/config.js` | 前端唯一配置来源 |
| 提交入口 | `supabase/functions/submit-feedback/index.ts` | 校验 + 蜜罐 + 限流 + 写库 |
| 数据库 | `supabase/migrations/0001_feedback.sql` | 建表 / RLS / 字段保护触发器 |
| 项目标识 | `supabase/config.toml` | Supabase `project_id` |

## 2. 公开配置（写在前端，可公开）

| 键 | 文件 | 值从哪里取 |
| --- | --- | --- |
| `supabaseUrl` | `assets/config.js` | Supabase → Project Settings → Data API → Project URL |
| `supabasePublishableKey` | `assets/config.js` | 同上页面 → API Keys → publishable / anon |
| `adminEmail` | `assets/config.js` | 你自己设定的管理员邮箱，需与数据库策略、Auth 一致 |

这三项设计上就会出现在浏览器里，**不是机密**。但 `service_role` key 是机密，任何情况下都不能放进前端。

## 3. 私密配置（只在 Supabase 后台）

| 名称 | 类型 | 在哪设置 | 用途 |
| --- | --- | --- | --- |
| `RATE_LIMIT_SALT` | Edge Function Secret | Supabase → Edge Functions → Secrets | 给访客 IP 加盐，避免明文存 IP |
| `SUPABASE_URL` | 运行时自动注入 | — | 函数内部访问数据库 |
| `SUPABASE_SERVICE_ROLE_KEY` | 运行时自动注入 | — | 函数绕过 RLS 写库，**勿外泄** |
| 数据库密码 | Supabase 账号级 | Supabase → Project Settings → Database | 仅连接数据库时需要 |

## 4. 管理员邮箱在三处必须一致

1. `assets/config.js` → `adminEmail`
2. `supabase/migrations/0001_feedback.sql` → 两条 policy 里的 email 条件
3. Supabase → Authentication → Users / 登录邮箱

> 换管理员邮箱时，三处都要改，并对已建表执行 policy 更新。

## 5. 防刷策略

- **蜜罐**：表单中隐藏的 `website` 字段被填写 → 返回成功但不写库
- **限流**：同一 IP 哈希，60 秒内最多 3 条（见函数顶部 `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW_MS`）

## 6. 验证清单

1. 打开主页 → 点「给我反馈」→ 填完提交 → 出现「反馈已收到」
2. 打开 `admin.html` → 点「发送登录链接」→ 去邮箱点链接 → 回到同一浏览器 → 看到留言列表
3. 点某条「标为已读」→ 刷新页面 → 状态保留

## 7. 常见故障对照

| 现象 | 大概率原因 |
| --- | --- |
| 提交报「来源不允许」 | 函数里 `ALLOWED_ORIGIN` 与实际访问域名不一致 |
| 提交报「服务暂不可用」 | 缺 `RATE_LIMIT_SALT`，或函数没部署成功 |
| 提交报「留言服务尚未配置」 | `assets/config.js` 里的 Supabase URL 还没填 |
| 管理页收不到邮件 | Auth 的 Site URL / Redirect URL 没配成当前 Pages 地址 |
| 管理页登录后看不到留言 | 登录邮箱与 policy 中的管理员邮箱不一致 |

## 8. 密钥保管建议

- 用系统密码管理器保存：Supabase 账号密码、数据库密码、GitHub 账号密码、`service_role` key、`RATE_LIMIT_SALT`
- 每个服务开启两步验证（GitHub 建议用 passkey / TOTP，不要只用短信）
- 建议生成一份「恢复码」离线存放（打印一份锁起来）
