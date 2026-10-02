# 个人主页 · 在线留言

张正卓的个人主页，含一个「在线留言」表单：访客提交后写入 Supabase 数据库，站长通过 `admin.html` 用邮箱魔法链接登录查看。

## 目录

```
index.html                                    主页（GitHub Pages 发布）
admin.html                                    留言管理页（noindex）
assets/config.js                              前端唯一配置来源
assets/*.jpg|png                              页面图片
supabase/migrations/0001_feedback.sql         建表 / RLS / 字段保护
supabase/functions/submit-feedback/index.ts   提交入口（校验 + 蜜罐 + 限流 + 写库）
supabase/config.toml                          Supabase 项目标识
docs/runbook.md                               配置运行手册（不含密钥）
```

## 留言链路

1. 访客在主页点「给我反馈」，填昵称（选填）+ 关系 + 设备 + 内容（≥10 字）
2. 前端 POST 到 Supabase Edge Function `submit-feedback`
3. 函数校验来源 Origin、剥离蜜罐字段、按 IP 哈希限流（60 秒最多 3 条），再用 service key 写入 `feedback` 表
4. 站长打开 `admin.html`，用管理员邮箱收魔法链接登录，可查看留言并把某条标为已读

## 防刷策略

- **蜜罐**：表单里有一个肉眼不可见的 `website` 字段，被填写即丢弃（返回成功但不写库）
- **限流**：对访客 IP 加盐哈希后计数，60 秒内最多 3 条
- 不使用第三方人机验证，前端不加载任何外部验证脚本

## 首次部署

1. 新建 Supabase 项目
2. 在 SQL Editor 执行 `supabase/migrations/0001_feedback.sql`
3. 在 Edge Functions → Secrets 设置 `RATE_LIMIT_SALT`（随机长字符串）
4. 部署 `submit-feedback` 函数（`verify_jwt = false`）
5. 把项目 URL 与 Publishable key 填进 `assets/config.js`
6. Authentication → URL Configuration：Site URL 与 Redirect URL 指向本仓库 Pages 地址
7. 发布到 GitHub Pages，用 `admin.html` 验证登录

> 详细配置位置与验证步骤见 `docs/runbook.md`。本仓库不含任何密钥。
