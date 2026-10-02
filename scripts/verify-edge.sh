#!/usr/bin/env bash
# 验收已部署的 submit-feedback Edge Function。
#
# 用法：
#   bash scripts/verify-edge.sh
#
# 前提：当前网络能访问 <项目>.supabase.co
#   （国内多数线路会按域名重置，需全局代理；先用下面这条自检：
#    curl -sS -o /dev/null -w '%{http_code}\n' https://ypqpzmgpjslguolpigfo.supabase.co
#    只要不是 000 / 连接被重置即可）
#
# 注意：第 4 段会真实写入 3 条以「［测试］」开头的留言，验证完请到
#       Supabase → Table Editor → feedback 删除，或让助手清理。

FN="https://ypqpzmgpjslguolpigfo.supabase.co/functions/v1/submit-feedback"
GOOD="https://zzz12138-let.github.io"
BAD="https://evil.example.com"

pass=0
fail=0

t() { # t <名称> <期望码> <实际码> <响应体>
  local name="$1" exp="$2" got="$3" body="$4"
  if [ "$exp" = "$got" ]; then
    printf "  \033[32mPASS\033[0m %-30s %s  %s\n" "$name" "$got" "$body"
    pass=$((pass+1))
  else
    printf "  \033[31mFAIL\033[0m %-30s got=%s want=%s  %s\n" "$name" "$got" "$exp" "$body"
    fail=$((fail+1))
  fi
}

call() { # call <method> <origin> [body] -> "code|body"
  local method="$1" origin="$2" body="$3" out
  if [ -n "$body" ]; then
    out=$(curl -sS --max-time 20 -X "$method" "$FN" \
      -H "Origin: $origin" -H "Content-Type: application/json" \
      --data-binary "$body" -w '\n%{http_code}' 2>&1)
  else
    out=$(curl -sS --max-time 20 -X "$method" "$FN" \
      -H "Origin: $origin" -w '\n%{http_code}' 2>&1)
  fi
  local code; code=$(printf '%s' "$out" | tail -1)
  local b; b=$(printf '%s' "$out" | sed '$d' | tr -d '\n' | cut -c1-90)
  printf '%s|%s' "$code" "$b"
}

echo "== 0. 连通性自检 =="
c=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$FN" 2>&1 || echo "ERR")
echo "  端点返回: $c   （000 表示网络仍不通，先解决代理再继续）"

echo "== 1. 方法与来源防护 =="
r=$(call GET "$GOOD");        t "GET 应拒绝" 405 "${r%%|*}" "${r#*|}"
r=$(call POST "$BAD" '{"nickname":"x","message":"aaaaaaaaaaaa"}'); t "错误来源应拒绝" 403 "${r%%|*}" "${r#*|}"
r=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -X OPTIONS "$FN" -H "Origin: $GOOD" 2>&1); t "OPTIONS 预检" 204 "$r" ""

echo "== 2. 载荷校验 =="
r=$(call POST "$GOOD" 'not-json');  t "非法 JSON" 400 "${r%%|*}" "${r#*|}"
r=$(call POST "$GOOD" '{"nickname":"机器人","message":"aaaaaaaaaaaa","website":"http://spam"}'); t "蜜罐命中(丢弃)" 201 "${r%%|*}" "${r#*|}"
r=$(call POST "$GOOD" '{"nickname":"某人","message":"太短"}'); t "内容过短" 400 "${r%%|*}" "${r#*|}"

echo "== 3. 正常写入 + 限流 (阈值 3/60s) =="
msg='［测试］这是一条自动化验收留言，验证接口链路。'
for i in 1 2 3; do
  r=$(call POST "$GOOD" "{\"nickname\":\"自动化测试${i}\",\"message\":\"${msg}（第${i}条）\"}")
  t "第 ${i} 次正常提交" 201 "${r%%|*}" "${r#*|}"
done
for i in 4 5; do
  r=$(call POST "$GOOD" "{\"nickname\":\"自动化测试${i}\",\"message\":\"${msg}（第${i}条）\"}")
  t "第 ${i} 次应被限流" 429 "${r%%|*}" "${r#*|}"
done

echo
echo "结果: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && echo "全部通过 ✅ 记得删除 3 条测试留言" || echo "有失败项 ❌"
