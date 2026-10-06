# 个人主页留言系统 · 配置运行手册

> 本文件只记录「配置项放在哪里、怎么改、怎么验证」，**不含任何密钥**。
> 密钥请存到密码管理器（例如 macOS 钥匙串 / 1Password / Bitwarden），不要写进本仓库。

## 0. 当前部署现状

| 项 | 值 |
| --- | --- |
| 仓库 | `https://github.com/zzz12138-let/personal-homepage-v2` |
| 站点 | `https://zzz12138-let.github.io/personal-homepage-v2/` |
| 管理页 | `https://zzz12138-let.github.io/personal-homepage-v2/admin.html` |
| Pages 来源 | `main` 分支 / 根目录（`/`） |
| Supabase 项目 | `ypqpzmgpjslguolpigfo`（Southeast Asia · Singapore） |
| 函数端点 | `https://ypqpzmgpjslguolpigfo.supabase.co/functions/v1/submit-feedback` |
| 函数 JWT 校验 | **关闭**（`Verify JWT with legacy secret` = OFF） |
| Auth Site URL | `https://zzz12138-let.github.io/personal-homepage-v2/` |
| Auth Redirect URLs | `.../personal-homepage-v2/**`、`.../personal-homepage-v2/admin.html` |

> 换 Supabase 项目时，只需改 `assets/config.js`、`supabase/config.toml`，以及本表的 URL。

### 网络前提（重要）

`*.supabase.co` 在部分网络（含中国大陆多数线路）会被按域名重置连接。因此：

- 留言提交、管理页登录都要求**访问者所在网络能连上 `*.supabase.co`**；
- 用代理/VPN 时必须是**全局模式**，或在分流规则里显式加 `DOMAIN-SUFFIX,supabase.co,PROXY`，否则 GitHub 通而 Supabase 不通；
- 症状是：页面能打开、点提交后长时间无响应或报网络错误，浏览器控制台里对 `*.supabase.co` 的请求 `net::ERR_CONNECTION_RESET`。

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

### 6.1 接口一键验收（无需打开浏览器）

```bash
# 前提：当前网络能访问 <项目>.supabase.co，自检：
curl -sS -o /dev/null -w '%{http_code}\n' https://ypqpzmgpjslguolpigfo.supabase.co
# 返回 000 或「连接被重置」= 网络仍不通，先解决代理

bash scripts/verify-edge.sh
```

覆盖：连通性、错误来源 403、GET 405、OPTIONS 204、非法 JSON 400、蜜罐 201、字段校验 400、正常写入 201、超限 429。

### 6.2 改完 Edge Function 必须复验（重要）

在 Supabase 后台编辑器里改代码 **不等于已经上线**，一定要点右下角 **Deploy updates**，并等到出现 `Successfully updated edge function`、顶部时间变成 `in a few seconds`。

部署后用**一条命令**确认新代码真的生效（关键是看「非法 JSON」的报错文案）：

```bash
FN='https://ypqpzmgpjslguolpigfo.supabase.co/functions/v1/submit-feedback'
curl -sS -X POST "$FN" -H 'Origin: https://zzz12138-let.github.io' \
  -H 'Content-Type: application/json' --data-binary 'not-json'
```

- 回 `{"error":"请求格式无效"}` = 新代码已生效 ✅
- 回 `{"error":"请检查昵称和留言内容"}` = **线上仍是旧版本**（没部署成功），`⌘A` 清空编辑器后重新粘贴再 Deploy

> 2026-10-06 实测踩坑：编辑器里显示的是最新代码，但线上一直跑 10 月 2 日的旧草稿，
> 表现为**任何** POST（含非法 JSON、蜜罐）都回「请检查昵称和留言内容」。
> 判断依据：旧草稿拿不到请求体字段，`payload` 近似空对象，必然走字段校验失败分支；
> 而新代码在解析失败时应回「请求格式无效」。重新粘贴并 Deploy 后 11 项验收全通过。

### 6.3 清掉验收产生的测试数据

验收脚本会真实写入 3 条（昵称 `自动化测试1/2/3`，留言以 `［测试］` 开头）。到 Supabase → SQL Editor：

```sql
-- 先看一眼
select id, nickname, left(message, 40) as message_head, created_at
from public.feedback order by created_at desc;

-- 新站还没有真实留言时，直接清空
delete from public.feedback;
```

## 7. 常见故障对照

| 现象 | 大概率原因 |
| --- | --- |
| 提交报「来源不允许」 | 函数里 `ALLOWED_ORIGIN` 与实际访问域名不一致 |
| 提交报「服务暂不可用」 | 缺 `RATE_LIMIT_SALT`，或函数没部署成功 |
| 所有 POST（连非法 JSON、蜜罐在内）都回「请检查昵称和留言内容」 | 线上跑的不是仓库里的代码（旧版本没被覆盖），按 6.2 重新部署并复验 |
| 提交报「留言服务尚未配置」 | `assets/config.js` 里的 Supabase URL 还没填 |
| 管理页收不到邮件 | Auth 的 Site URL / Redirect URL 没配成当前 Pages 地址 |
| 管理页登录后看不到留言 | 登录邮箱与 policy 中的管理员邮箱不一致 |
| 页面能开但提交一直转圈 / 无响应 | 当前网络连不上 `*.supabase.co`（被重置），见第 0 节「网络前提」 |
| 管理页点了发链接但登录不进 | 同上：魔法链接回跳也需要能访问 `*.supabase.co` |

## 8. 密钥保管建议

- 用系统密码管理器保存：Supabase 账号密码、数据库密码、GitHub 账号密码、`service_role` key、`RATE_LIMIT_SALT`
- 每个服务开启两步验证（GitHub 建议用 passkey / TOTP，不要只用短信）
- 建议生成一份「恢复码」离线存放（打印一份锁起来）
