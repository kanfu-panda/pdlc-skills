#!/usr/bin/env bash
# Repo-layout + installer-script regression test.
#
# Since install.sh now wraps `claude plugin install` (which requires the
# claude CLI and isn't easily exercised in CI), this test focuses on
# verifying the repo layout the plugin system expects, plus the bits of
# install.sh that work without a claude CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

pass=0
fail=0

assert_exists() {
    local desc="$1" path="$2"
    if [[ -e "$path" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (missing: $path)"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if grep -qF "$expected" <<< "$actual"; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc"
        echo "    expected to contain: $expected"
        fail=$((fail + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (expected: $expected, got: $actual)"
        fail=$((fail + 1))
    fi
}

# ─── Test 1: plugin manifest layout ───
echo "Test: plugin manifest"
assert_exists ".claude-plugin/ directory exists"   ".claude-plugin"
assert_exists "plugin.json exists"                 ".claude-plugin/plugin.json"
assert_exists "marketplace.json exists"            ".claude-plugin/marketplace.json"

# Validate plugin.json basic fields
plugin_name=$(awk -F'"' '/"name"/{print $4; exit}' .claude-plugin/plugin.json)
plugin_version=$(awk -F'"' '/"version"/{print $4; exit}' .claude-plugin/plugin.json)
assert_eq "plugin.json name == 'pdlc'"             "pdlc"   "$plugin_name"
assert_eq "plugin.json version == VERSION"         "$(head -1 VERSION)"   "$plugin_version"

marketplace_name=$(awk -F'"' '/"name"/{print $4; exit}' .claude-plugin/marketplace.json)
assert_eq "marketplace.json name == 'pdlc-skills'" "pdlc-skills"   "$marketplace_name"

# ─── Test 2: skills layout ───
echo ""
echo "Test: skills/ layout"
assert_exists "skills/ directory exists" "skills"

skill_count=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "exactly 38 sub-skill directories" "38" "$skill_count"

for name in pdlc-feature pdlc-fix pdlc-status pdlc-prd pdlc-design pdlc-tdd pdlc-implement pdlc-review pdlc-ship pdlc-standard pdlc-relate pdlc-loop-next pdlc-loop-run pdlc-settings; do
    assert_exists "skills/$name/SKILL.md exists" "skills/$name/SKILL.md"
done

missing=0
for d in skills/*/; do
    [[ -f "${d}SKILL.md" ]] || missing=$((missing + 1))
done
assert_eq "every skill dir has SKILL.md" "0" "$missing"

non_prefixed=0
for d in skills/*/; do
    name="$(basename "$d")"
    [[ "$name" == pdlc-* ]] || non_prefixed=$((non_prefixed + 1))
done
assert_eq "every skill dir name starts with 'pdlc-'" "0" "$non_prefixed"

# ─── Test 3: shared resources ───
echo ""
echo "Test: shared resources"
assert_exists "references/templates/ directory exists" "references/templates"

template_count=$(find references/templates -maxdepth 1 -name '*-template.md' | wc -l | tr -d ' ')
assert_eq "12 user-facing templates"                   "12"  "$template_count"

prompt_count=$(find references/templates/prompts -name '*.md' | wc -l | tr -d ' ')
assert_eq "13 shared prompt fragments"                 "13"  "$prompt_count"

for f in iron-law handoff feature-id defect-id pdlc-trace self-audit state-update loop-prevention output-language relations noninteractive test-location check-commands; do
    assert_exists "references/templates/prompts/$f.md exists" "references/templates/prompts/$f.md"
done

# ─── v1.1 invariants ───
assert_exists "docs/ARCHITECTURE.md exists" "docs/ARCHITECTURE.md"
assert_exists "docs/GLOSSARY.md exists" "docs/GLOSSARY.md"
assert_exists "architecture-overview template exists" "references/templates/architecture-overview-template.md"
assert_exists "glossary template exists" "references/templates/glossary-template.md"
assert_contains "pdlc-standard declares artifact_type: surface" "artifact_type: surface" "$(cat skills/pdlc-standard/SKILL.md)"
assert_contains "state-update schema includes relations block" '"relations"' "$(cat references/templates/prompts/state-update.md)"
assert_contains "pdlc-trace header includes relations line" '关系:' "$(cat references/templates/prompts/pdlc-trace.md)"
assert_eq "pdlc-arch dropped legacy 07_reviews/design path" "0" "$(grep -c '07_reviews/design' skills/pdlc-arch/SKILL.md || true)"

# ─── loop-engineering (PR-1) invariants ───
assert_exists "noninteractive prompt fragment exists" "references/templates/prompts/noninteractive.md"
assert_exists "test-commands template exists" "references/templates/test-commands-template.yml"
assert_exists "pdlc-loop-next skill exists" "skills/pdlc-loop-next/SKILL.md"
assert_exists "pdlc-loop-run skill exists" "skills/pdlc-loop-run/SKILL.md"
assert_contains "pdlc-loop-run stays at review_done (no auto ship)" "review_done" "$(cat skills/pdlc-loop-run/SKILL.md)"
assert_contains "state-update schema includes last_phase_result" "last_phase_result" "$(cat references/templates/prompts/state-update.md)"
assert_contains "iron-law has 6th law (状态必推进)" "状态必推进" "$(cat references/templates/prompts/iron-law.md)"
assert_contains "pdlc-implement @includes noninteractive" "noninteractive.md" "$(cat skills/pdlc-implement/SKILL.md)"
assert_contains "pdlc-ship states autonomous does not bypass" "对本命令无效" "$(cat skills/pdlc-ship/SKILL.md)"

# ─── statusline (v1.4) invariants ───
assert_exists "bin/pdlc-statusline.sh exists" "bin/pdlc-statusline.sh"
assert_exists "pdlc-statusline.sh is executable" "bin/pdlc-statusline.sh"
if [[ -x "bin/pdlc-statusline.sh" ]]; then
    echo "  ✓ pdlc-statusline.sh has +x bit"; pass=$((pass + 1))
else
    echo "  ✗ pdlc-statusline.sh missing +x bit"; fail=$((fail + 1))
fi
assert_exists "pdlc-settings skill exists" "skills/pdlc-settings/SKILL.md"
assert_exists "statusline config example exists" "references/templates/pdlc-statusline.example.json"
assert_exists "statusline scenario test exists" "tests/statusline-check.sh"
assert_contains "pdlc-settings degrades when settings.json write is gated" "被安全层拦截" "$(cat skills/pdlc-settings/SKILL.md)"
assert_contains "statusline script exits empty for non-PDLC dirs" "非 PDLC 项目 → 立即吐空" "$(cat bin/pdlc-statusline.sh)"

# ─── multi-platform adapters (v1.5) invariants ───
assert_exists "docs/pdlc-methodology.md (Tier 1 core) exists" "docs/pdlc-methodology.md"
assert_exists "adapters/ directory exists" "adapters"
assert_exists "adapters/README.md exists" "adapters/README.md"
assert_exists "Codex adapter build_codex.py exists" "adapters/build_codex.py"
assert_exists "adapter-codex scenario test exists" "tests/adapter-codex-check.sh"
assert_exists "ADR 0003 multi-platform exists" "docs/decisions/0003-multi-platform-adapters.md"
assert_contains "install.sh supports --target codex" "target codex" "$(cat install.sh)"
assert_contains "methodology declares platform-neutral core" "平台中立" "$(cat docs/pdlc-methodology.md)"
assert_contains "build_codex denylists Claude-only skills" "pdlc-loop-run" "$(cat adapters/build_codex.py)"

# ─── Codex loop-run driver (v1.5.2) invariants ───
assert_exists "codex-loop-run.sh driver exists" "adapters/codex-loop-run.sh"
assert_exists "loop-run driver test exists" "tests/adapter-codex-loop-run-check.sh"
assert_exists "ADR 0004 codex-loop-run exists" "docs/decisions/0004-codex-loop-run.md"
assert_contains "driver never auto-ships (review_done terminal)" "review_done" "$(cat adapters/codex-loop-run.sh)"
assert_contains "driver has stuck-stop guard" "stuck-stop" "$(cat adapters/codex-loop-run.sh)"

# ─── B2 quality gate (ADR 0005 §5) invariants ───
assert_exists "pdlc-quality skill exists"           "skills/pdlc-quality/SKILL.md"
assert_exists "quality-targets template exists"     "references/templates/quality-targets-template.yml"
assert_exists "e2e-flow-map template exists"        "references/templates/e2e-flow-map-template.yml"
assert_exists "quality-report template exists"      "references/templates/quality-report-template.md"
# 第一个地基：核心流覆盖必须靠显式 flow→test 映射机械核对，不能靠模型意见
assert_contains "quality uses explicit flow→test map, not model opinion" \
  "e2e-flow-map.yml" "$(cat skills/pdlc-quality/SKILL.md)"
assert_contains "quality treats a broken mapping as red" \
  "映射腐烂" "$(cat skills/pdlc-quality/SKILL.md)"
# 第二个地基：PRD 对账防 false-green——清单腐烂会让矩阵全绿而现实有洞
assert_contains "quality reconciles PRD against core_flows" \
  "强制对账" "$(cat skills/pdlc-quality/SKILL.md)"
assert_contains "quality names the false-green failure mode" \
  "false-green" "$(cat skills/pdlc-quality/SKILL.md)"
# 对账自身的 false-green：PRD 没有 P0/P1 标记时提取为空集、不产生漂移，
# 若就此判「无漂移 ✅」等于宣称那份 PRD 的流程都覆盖了。真项目上实测踩到过。
assert_contains "quality distinguishes unjudgeable from no-drift" \
  "不可判" "$(cat skills/pdlc-quality/SKILL.md)"
# 量不到不得算通过
assert_contains "quality never passes an unmeasured item" \
  "不得因此判为通过" "$(cat skills/pdlc-quality/SKILL.md)"
# go/no-go 由人拍
assert_contains "quality leaves go/no-go to a human" \
  "放行由人" "$(cat skills/pdlc-quality/SKILL.md)"
# 发布挂钩：ship 读最近一份质量报告
assert_contains "ship gates on the latest quality report" \
  "07_reviews/quality/" "$(cat skills/pdlc-ship/SKILL.md)"
# 上游挂钩：PRD 产出 P0/P1 流程时提示补 core_flows
assert_contains "prd hooks new P0/P1 flows into core_flows" \
  "core_flows" "$(cat skills/pdlc-prd/SKILL.md)"

# ─── 测试定位布局无关（真项目验证所得）───
# 守卫必须区分「项目没测试」和「测试不在我预期位置」——后者拦了就是误伤。
# 真实项目常用 backend/tests/ 单体布局，老的写死路径清单会让它直接卡死。
assert_exists "test-location fragment exists" "references/templates/prompts/test-location.md"
assert_contains "test-location distinguishes no-tests from wrong-place" \
  "测试不在我预期的位置" "$(cat references/templates/prompts/test-location.md)"
assert_contains "test-location defers to the project's own declaration" \
  "test-commands.yml" "$(cat references/templates/prompts/test-location.md)"
# 优先问 runner 而非翻文件——in-source 测试的语言里翻文件根本找不到
assert_contains "test-location interrogates the runner, not just the filesystem" \
  "优先问 runner" "$(cat references/templates/prompts/test-location.md)"
# Rust 单测在源文件的 #[cfg(test)] 里；tests/ 按 Cargo 约定只放集成测试。
# 照文件清单判红会稳定误伤所有 Rust 项目。
assert_contains "test-location handles in-source tests (Rust cfg(test))" \
  "#[cfg(test)]" "$(cat references/templates/prompts/test-location.md)"
assert_contains "test-location handles Vitest in-source testing" \
  "import.meta.vitest" "$(cat references/templates/prompts/test-location.md)"
# 三态而非两态：无法判定不得并入通过
assert_contains "test-location refuses to pass when it cannot tell" \
  "绝不等于" "$(cat references/templates/prompts/test-location.md)"
# ADR 记录这条反模式，供后续做同类闸门时自查
assert_contains "ADR 0005 records the cannot-tell-vs-fine anti-pattern" \
  "无法判定（缺证据）" "$(cat docs/decisions/0005-testing-and-quality-capability.md)"
for s in pdlc-implement pdlc-tdd pdlc-feature pdlc-fix; do
    assert_contains "$s uses layout-agnostic test location" \
      "templates/prompts/test-location.md" "$(cat skills/$s/SKILL.md)"
done
# 正文里不得再写死那份路径清单（frontmatter 的 produces/requires 声明不算）
# grep 无匹配时退出码为 1，pipefail 下会让整条管道失败 → 必须显式吞掉
hardcoded="$( { grep -l 'backend/services/<服务名>/src/test/' skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')"
assert_eq "no skill body hardcodes the old test-path list" "0" "$hardcoded"

# ─── check 命令三态语义 + yml 自动保鲜 ───
# 「命令跑不了(127)」被记成 false 是会误导人的虚报：它说"检查失败"，
# 于是有人去查代码，而真正的问题是 test-commands.yml 过期了。
assert_exists "check-commands fragment exists" "references/templates/prompts/check-commands.md"
assert_contains "check-commands defines three-state exit semantics" \
  "无法判定" "$(cat references/templates/prompts/check-commands.md)"
assert_contains "check-commands forbids recording unrunnable as false" \
  "绝不能是 \`false\`" "$(cat references/templates/prompts/check-commands.md)"
assert_contains "check-commands treats unrunnable as a staleness signal" \
  "过期信号" "$(cat references/templates/prompts/check-commands.md)"
# 方向规则：变严可自动、变松必须人确认——防「自动修复把闸门修没了」
assert_contains "check-commands gates loosening behind human confirmation" \
  "变严可以自动，变松必须由人签字" "$(cat references/templates/prompts/check-commands.md)"
for s in pdlc-tdd pdlc-implement pdlc-review pdlc-quality pdlc-test-setup; do
    assert_contains "$s uses the check-command exit semantics" \
      "templates/prompts/check-commands.md" "$(cat skills/$s/SKILL.md)"
done
assert_contains "test-setup offers --refresh for staleness" \
  "\`--refresh\`" "$(cat skills/pdlc-test-setup/SKILL.md)"
assert_contains "quality reports config health" \
  "配置健康度" "$(cat skills/pdlc-quality/SKILL.md)"

# ─── 派生计数守卫 ───
# 教训：历次改 skill 数时，「36」「22」这类字面量能被批量替换扫到，但**派生数字**
# （总数−Layer1、总数−denylist）扫不到，会静默过期。这里用实际数量反算来校验。
_total=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
_l1=$(grep -l '^layer: 1' skills/*/SKILL.md | wc -l | tr -d ' ')
_deny=$(grep -c '^    "pdlc-' adapters/build_codex.py 2>/dev/null || echo 0)
# usage-guide 的「其他 N 个阶段」= 总数 − Layer1
_want_rest=$((_total - _l1))
assert_contains "usage-guide's derived 'other N stages' matches total-layer1" \
  "其他 ${_want_rest} 个阶段" "$(cat docs/usage-guide.md)"
# adapters/README 的「共 N 个 skill 投影」= 总数 − denylist
_want_proj=$((_total - 2))
assert_contains "adapters/README projection count matches total-denylist" \
  "共 ${_want_proj} 个 skill 投影" "$(cat adapters/README.md)"

# ─── 契约一致性回归闸（Copilot 评审所得）───
# 规范与回归契约不得互相打架：片段允许 null，eval 也允许 null
assert_contains "check-commands allows null as well as omission" \
  "或写 \`null\`" "$(cat references/templates/prompts/check-commands.md)"
# frontmatter 不得再硬编码测试/源码布局——正文已改为布局无关，元数据要跟上
hardcoded_fm="$( { grep -l 'backend/services/\*/src/test/$' skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')"
assert_eq "no frontmatter hardcodes fixed test layouts" "0" "$hardcoded_fm"
# 覆盖率口径唯一：以项目配置为准，不得散落多个裸阈值
bare_cov="$( { grep -l '目标 >= 80%\|覆盖率 ≥ 80%\|覆盖率目标：>= 80%' skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')"
assert_eq "no skill states a bare coverage threshold" "0" "$bare_cov"
# 报告模板的对账行必须能表达「不可判」，否则与规则冲突
assert_contains "report template can express the unjudgeable state" \
  "✅ / ⚠️ / ❌" "$(cat references/templates/quality-report-template.md)"

# ─── B1 test-setup (ADR 0005 §4) invariants ───
assert_exists "pdlc-test-setup skill exists"        "skills/pdlc-test-setup/SKILL.md"
# 本命令的命门：写进 test-commands.yml 的命令必须先真跑过。这条纪律丢了，
# 它就会生成「看起来对但跑不了」的命令，污染下游每个阶段的 checks。
assert_contains "test-setup requires commands be verified before writing" \
  "必须先被真跑过一次" "$(cat skills/pdlc-test-setup/SKILL.md)"
assert_contains "test-setup leaves unverified entries blank" \
  "猜出来的命令一律不写" "$(cat skills/pdlc-test-setup/SKILL.md)"
# 不得顺手建 CI——日常 check 本地跑是本仓的既定纪律
assert_contains "test-setup wires local hooks, not CI" \
  "不新建 CI workflow" "$(cat skills/pdlc-test-setup/SKILL.md)"
# 诚实边界：不能吹「帮你生成全部测试」
assert_contains "test-setup does not overclaim test generation" \
  "不生成完整测试套件" "$(cat skills/pdlc-test-setup/SKILL.md)"

# ─── Behavioural evals (ADR 0005 · A-live) invariants ───
assert_exists "evals/run.sh exists"                 "evals/run.sh"
assert_exists "evals/run.sh is executable"          "evals/run.sh"
assert_exists "EVALS.md exists"                     "evals/EVALS.md"
assert_exists "ADR 0005 testing capability exists"  "docs/decisions/0005-testing-and-quality-capability.md"
assert_exists "honest-checks fixture exists"        "evals/fixtures/honest-checks/scenario.sh"
assert_exists "red-light-gate fixture exists"       "evals/fixtures/red-light-gate/scenario.sh"
assert_exists "stale-config fixture exists"         "evals/fixtures/stale-config/scenario.sh"
# 第三态的回归闸：命令跑不了(127) 既不能记 false（会把人引去查代码），也不能记 true
assert_contains "stale-config forbids encoding unrunnable as a boolean" \
  "唯独不能是 false" "$(cat evals/fixtures/stale-config/scenario.sh)"
# 分档判据必须留在文档里——它决定一个场景要不要烧模型额度
assert_contains "EVALS.md states the tier criterion" "契约由谁执行" "$(cat evals/EVALS.md)"
# 抖动 ≠ 契约破坏：这条政策丢了，A-live 会因限流误报"契约回归"
assert_contains "runner classifies env-flake vs contract-break" "环境抖动" "$(cat evals/run.sh)"
assert_contains "runner reports inconclusive rather than green" "无结论" "$(cat evals/run.sh)"
# red-light-gate 的假绿护栏：没有守卫哨兵不得判通过
assert_contains "red-light-gate requires guard sentinel" "PDLC 守卫" \
  "$(cat evals/fixtures/red-light-gate/scenario.sh)"
# 免费的结构自检必须可用（不烧额度）
check_out="$(./evals/run.sh --check 2>&1 || true)"
assert_contains "evals --check passes offline" "fixture 结构自检全部通过" "$check_out"

# ─── Test 4: install.sh without claude CLI ───
echo ""
echo "Test: install.sh (claude CLI not required for these subcommands)"

help_out="$(bash install.sh --help 2>&1)"
assert_contains "--help shows usage"                "Usage:"                          "$help_out"
assert_contains "--help mentions /pdlc-feature"     "/pdlc-feature"                   "$help_out"
assert_contains "--help mentions one-liner"         "raw.githubusercontent.com"       "$help_out"

version_out="$(bash install.sh --version 2>&1)"
assert_contains "--version shows version status"    "pdlc-skills version status"      "$version_out"
assert_contains "--version shows local clone"       "Local clone:"                    "$version_out"

bogus_out="$(bash install.sh --bogus 2>&1 || true)"
assert_contains "unknown arg shows error"           "Unknown argument"                "$bogus_out"

# ─── Test 5: docs / repo hygiene ───
echo ""
echo "Test: repo hygiene"

# 多字节相邻守卫：`$var` 紧跟中文时，bash 会把多字节的首字节并进变量名，
# 报 `xxx?: unbound variable` 甚至改变语义。这类写法几乎总藏在**错误分支**里
# ——正常路径跑不到，一旦真出错连报错本身都崩。本仓已被它坑过 4 次，故设此闸。
# 修法：加花括号 `${var}中文`。
# 用 awk + C locale 按字节匹配（macOS 的 grep 没有 -P，无法用 \x 类）。
mb_hits="$(LC_ALL=C find . -name '*.sh' -not -path './.git/*' -exec \
    awk '/\$[A-Za-z_][A-Za-z0-9_]*[^ -~]/ {print FILENAME":"FNR}' {} + 2>/dev/null || true)"
if [[ -z "$mb_hits" ]]; then
    echo "  ✓ no \$var directly adjacent to multibyte text (use \${var} instead)"
    pass=$((pass + 1))
else
    echo "  ✗ \$var directly adjacent to multibyte text — wrap as \${var}:"
    # shellcheck disable=SC2086  # 需要按空白拆成多行输出，此处刻意不加引号
    printf '      %s\n' $mb_hits
    fail=$((fail + 1))
fi

assert_exists "README.md exists"                    "README.md"
assert_exists "README.zh-CN.md exists"              "README.zh-CN.md"
assert_exists "LICENSE exists"                      "LICENSE"
assert_exists "VERSION exists"                      "VERSION"
assert_exists "CHANGELOG.md exists"                 "CHANGELOG.md"
assert_exists "CONTRIBUTING.md exists"              "CONTRIBUTING.md"
assert_exists "SECURITY.md exists"                  "SECURITY.md"
assert_exists "CODE_OF_CONDUCT.md exists"           "CODE_OF_CONDUCT.md"
assert_exists "docs/usage-guide.md exists"          "docs/usage-guide.md"

# Legacy structure must NOT exist
if [[ ! -e "SKILL.md" ]]; then
    echo "  ✓ no legacy root SKILL.md"
    pass=$((pass + 1))
else
    echo "  ✗ legacy root SKILL.md still present"
    fail=$((fail + 1))
fi

if [[ ! -e "references/commands" ]]; then
    echo "  ✓ no legacy references/commands/ dir"
    pass=$((pass + 1))
else
    echo "  ✗ legacy references/commands/ still present"
    fail=$((fail + 1))
fi

if [[ ! -e "docs/reference.md" ]]; then
    echo "  ✓ no legacy docs/reference.md"
    pass=$((pass + 1))
else
    echo "  ✗ legacy docs/reference.md still present"
    fail=$((fail + 1))
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
