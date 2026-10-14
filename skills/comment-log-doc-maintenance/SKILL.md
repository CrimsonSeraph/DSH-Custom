---
name: comment-log-doc-maintenance
description: |
  Run a codebase hygiene pass in three separable, reviewable tasks: comment cleanup
  (strip decorative divider comments, unify Doxygen `@brief` / trailing `///<` style,
  migrate long comment blocks into the nearest non-root README), logging rework against
  an existing log macro (delete success-path logs from hot paths, keep diagnostics with a
  keyed log-once guard), and documentation polish with the humanizer skill (fix broken
  relative links, correct stale content that the changelog and file list prove wrong,
  unify terminology). Use when asked to 优化注释 / 优化日志 / 优化文档, to remove
  `// ====` comment dividers, to stop per-frame or per-message log spam, or to
  reconcile Markdown docs with the actual code. Never changes behavior, signatures,
  build configuration, or the changelog; each task gets its own commit.
whenToUse: |
  需要对一个项目做「注释 / 日志 / 文档」三类维护，且要求小步、可审阅、可回滚、不改变业务逻辑时使用。
  触发场景：优化代码注释、删除注释里的 ===== / ----- 装饰分割线、统一 Doxygen 与 ///< 注释风格、
  把长注释迁到目录 README、优化日志宏调用点、删除每帧/每消息/高频回调里的日志、给高频路径改成只报一次、
  优化 Markdown 文档、修断链、统一术语、用 humanizer 去 AI 味。
  也适用于被要求「三个任务各提交一次，提交信息用中文」的维护类任务。
version: 1.0.0
date: 2026-09-29
---

# Comment / Log / Doc maintenance in three committed passes

## Problem

Legacy repositories accumulate three kinds of low-grade damage that nobody owns: comment
decoration and drift, logging that is either missing on error paths or spamming hot loops,
and Markdown that describes a layout the code no longer has. All three are safe to fix, but
only if the fix stays inside prose, is verifiable mechanically, and never touches behavior,
signatures, build config, or history files.

The hard part is not the edit. It is proving the edit changed nothing else, and knowing which
"documentation" claims are verifiable from the repo and which must be left alone.

## Context / Trigger Conditions

- A request to 优化注释 / 优化日志 / 优化文档, or "clean up comments", "reduce log spam",
  "reconcile docs with code".
- Comment blocks like `// ============` / `// ------ title ------` / `// ********`.
- A log macro such as `LOG_MODULE(module, method, level, ...)` with a `LogLevel` enum.
- Markdown whose project tree lists files that no longer exist (`git ls-files` disagrees).
- A repo with mixed line endings in the working tree (common when `.gitattributes` sets
  `* text=auto eol=crlf` but files were edited on another platform).

## Solution

Work in three passes, each ending in exactly one commit. Establish facts before editing; the
repo itself is the authority for "what exists".

### Pass 0 — Pre-flight (do this once, before any edit)

1. `git status --porcelain` must be empty. If not, stop and report; never edit over user work.
2. Read: root `README.md`, the project's style guide (`CodingStyle.md` etc.), the log macro
   and level enum header, the tracked file list (`git ls-files`), and the existing skills.
3. Build an explicit skip list: `third_party/`, `vendor/`, `out/`, `build/`, `node_modules/`,
   generated files, and (for this task family) `CHANGELOG.md`.
4. Prefer the repo's own conventions over the request's defaults when they conflict, and say so
   in the commit message. Example: a project that already documents members with `///<` and
   ends lines with two spaces should not be converted to Doxygen `@brief` everywhere.

### Pass 1 — Comments

1. Classify divider lines before deleting, so nothing informative is lost:
   - pure decoration (`// ============`) → delete the line;
   - decoration + title (`// ---- 单例 ----`, `// ---- 单例`) → keep the text, strip the decor;
   - a 3-line box (`// ====` / `// Title` / `// ====`) → deleting the two pure lines leaves a
     clean `// Title`.
   Verify the classification by printing the unique matched lines; do not assume one shape.
2. Regex traps (both cost real time here):
   - In .NET/PowerShell multiline patterns, `$` matches before `\n` only, so a CRLF file fails
     `[ \t]*$`. Write `\r?$` (or match `(\r?\n|$)`).
   - Preserve each file's own bytes: detect BOM and line ending, read with
     `[System.IO.File]::ReadAllText`, write back with `[System.IO.File]::WriteAllText` using
     `UTF8Encoding($false)` (or `$true` when a BOM was present). Splitting on `"`r?`n"` and
     rejoining with the detected `$nl` also works and makes line-based edits easy.
3. Style: function docs use `@brief`/`@param`/`@return`; struct/enum/class members, globals and
   statics use a trailing `///<` comment. Do not rewrite headers, licence text, or generated
   markers.
4. Long prose comments (protocol descriptions, state machines, directory duties, design
   constraints) move to `README.md` of the current directory, or of the nearest non-root parent
   directory — never to the root README, and never create a README for a single file. In code,
   leave one or two lines plus a pointer: `// 帧布局见 include/README.md 的「关键协议与约定」`.
5. Never change code, signatures, `#include` order, or formatting outside comments.

### Pass 2 — Logging

1. Locate the macro, the level enum and the sinks first. Do not modify the macro or the enum;
   adjust call sites instead.
2. Find hot paths by following callers, not by guessing from names. High-frequency paths in a
   typical app: template `get`/`set` accessors on config objects, per-value-change rule
   evaluation and placeholder resolution, per-packet/per-datagram handlers, per-message socket
   handlers, per-tick schedulers, and timer callbacks. Confirm the frequency by reading who
   calls the function and what drives it (a value-changed signal, a 100 ms timer, a socket).
3. Delete, in those paths:
   - success-path `LOG_DEBUG` in getters/setters/templates ("获取配置成功 …");
   - `LOG_DEBUG`/`LOG_WARN` for normal outcomes of per-evaluation code ("规则未启用，跳过计算",
     "存在空值，本次计算被忽略", "计算结果: N", "无数据，按空值处理");
   - per-packet/per-message warnings that repeat for every packet ("无匹配的数据处理器").
4. Keep genuinely useful diagnostics in hot paths without flooding: guard the call with a
   bounded, keyed "first time only" helper, added to the log utility header rather than to the
   macro. The pattern used here:

   ```cpp
   /// @brief 同一问题只为首次出现返回 true（用于按次/按包触发的高频路径）
   /// @note 最多记录 kMaxKeys 个标识，避免标识无限增长
   inline bool should_log_once(const std::string& key) {
       static thread_local std::set<std::string> reported;
       constexpr std::size_t kMaxKeys = 64;
       if (reported.size() >= kMaxKeys) {
           return false;
       }
       return reported.insert(key).second;
   }
   ```

   Use it for repeating error conditions (bad expression text, config type mismatch, malformed
   payload, missing peer) with a key that names the condition, e.g. `"rule-expression-error:" + expr`.
5. Add `LOG_INFO` at state changes and `LOG_WARN` (once) when an external call is dropped
   because no peer/target is available. Do not add logs to per-tick loops or per-packet paths.
6. Never put a side-effecting expression in a log argument (`i++`, a mutating call).
7. Also fix log hygiene while you are there: the macro's method/function argument should be the
   real function name (`compute_value`, not `computeValue`), and messages should not dump
   unbounded or sensitive payloads.

### Pass 3 — Documentation

1. Load the `humanizer` skill and use it in file mode: prose only. Commands, code fences, paths,
   inline code, config keys, version numbers, links and licence text stay byte-identical.
2. Mechanically find broken links: for every `](target)` that is not `http(s)`, `mailto:` or an
   anchor, resolve it relative to the file's directory and test it. Fix the target, not the text.
3. Separate verifiable staleness from guesswork:
   - `git ls-files` shows what exists; a changelog's "removed X" entries show what was deleted.
     Both are authoritative, so a directory tree listing deleted files, or a "run
     `pip install websockets`" step for a removed bridge, is a correctable error.
   - Product intent is not verifiable. If a legacy section might still be supported, or you
     cannot tell what should replace it, leave the content and report it as needing confirmation
     instead of inventing a replacement.
4. Prefer structure that does not rot: a directory-level tree plus pointers to the per-directory
   READMEs beats a 140-line per-file listing that will be wrong within a release.
5. Unify terminology by counting variants first, then replace only in prose. Never touch a URL,
   and keep project-name vs vendor-name distinctions that are real.
6. Apply humanizer's strongest tells while editing: drop "本节为…提供完整指南" run-ups, "极大提升
   了…" inflation, decorative bold labels, emoji headings, and closers that only restate.
7. For peripheral files, a subagent with the constraints explicit (no facts changed, <30% of
   lines, no `git commit`) is a good split of work; review its report, then verify its diff
   yourself.

### Commits

One commit per pass, Chinese message, imperative-ish `feat(scope): 简述` plus bullet body:

```
feat(comments): 优化代码注释
- 移除注释装饰分割线并简化冗余注释
- 统一函数与变量注释风格
- 将长注释迁移至目录 README
```

Stage only that pass's files. If a pass produced no change, skip its commit and say why.

## Verification

1. **Comments-only assertion (the key check).** Parse `git diff -U0 --no-color` and assert that
   every added and removed line is a comment line or blank. With the README migration in the
   same commit, exclude that file from the assertion and check it separately.
   ```powershell
   $diff = git diff -U0 --no-color -- . ':(exclude)include/README.md'
   # removed/added lines must match '^//' or be empty
   ```
2. **Re-scan for leftovers.** After the divider pass, grep for `^\s*//\s*[=\-*~_#]{3,}` and
   expect zero hits; also check for triple newlines introduced by deleted lines.
3. **Compile check without a full build.** If `out/build/<preset>/compile_commands.json` exists,
   load the MSVC environment and syntax-check only the touched translation units — cheap and it
   covers every changed header transitively:
   ```powershell
   cmd /c "`"…\VC\Auxiliary\Build\vcvars64.bat`" >nul 2>&1 && set" | ForEach-Object {
       if ($_ -match '^([^=]+)=(.*)$') { Set-Item "env:$($matches[1])" $matches[2] }
   }
   # per entry in compile_commands.json: tokenize .command (respect quotes), drop token 0,
   # drop /c /Fo* /Fd* /showIncludes, append /Zs, run with workdir = $entry.directory
   ```
   `compile_commands.json` may carry only a `command` string, so quote-aware tokenizing is
   required; passing the compiler path itself through as an argument makes `cl.exe` report
   thousands of bogus `warning C4828` lines about its own binary as "source".
4. **Code-fence integrity for doc edits.** Compare the fenced blocks of `HEAD:file` with the
   working copy as multisets (`Compare-Object` on sorted block lists). Index-wise comparison is
   misleading whenever a block is added or removed, because every later index shifts.
5. `git status --porcelain` at the end must show only the intended files, and
   `git status --porcelain -- CHANGELOG.md` must be empty.

## Example

Session that produced this skill: a Qt6/QML C++ project, 65 code files and 16 Markdown files.

- Pass 1 (commit `feat(comments): 优化代码注释`, 65 files, +228/−498): classified 474 divider
  lines into 290 pure (deleted) and 156 with titles (stripped to `// 单例`); migrated five
  protocol/design blocks (relay message set, coyote BLE `B0`/`BF`/`B1`, 8-byte wave frame,
  listener envelope, rule-graph node semantics) into `include/README.md`; left two-line
  summaries plus pointers in the headers. Verified with the comments-only diff assertion.
- Pass 2 (commit `feat(logging): 优化日志`, 9 files, +51/−35): removed success-path debug logs
  from config `get`/`set` templates and four per-evaluation logs in the rule engine, added the
  bounded `should_log_once` helper for the five repeating error conditions, added an INFO on BLE
  disconnect and a once-only warning when a command has no paired target. Verified by `/Zs`
  syntax-checking the five touched translation units (all pass).
- Pass 3 (commit `feat(docs): 优化项目文档`, 10 files, +210/−346): fixed two broken links
  (`LICENSE.txt` → `LICENSE`), replaced a 140-line stale file tree with a directory-level tree,
  deleted a `pip install websockets qrcode` quick-start step that a removed component required,
  corrected config README keys against the real JSON, unified `DG-Lab` → `DG-LAB` in prose,
  and ran humanizer over the peripheral docs via a subagent.

## Notes

- Mixed line endings are the most common silent failure. A regex pass that "worked" on half the
  files is almost always the CRLF `$` trap; check the leftover scan before believing the result.
- The `edit` tool requires a prior read of the file and refuses after an external script rewrote
  it ("file changed since it was read"), and a batch of parallel edits to the same file can fail
  with "old_string was not found" — re-read and retry once rather than switching tools.
- When the file sandbox itself fails to initialize with
  `SetNamedSecurityInfoW failed (Win32 5): grantWrite(<workspace>)`, the shell is unusable, not
  the command: it needs a wider file policy. Once the runtime policy is already
  `danger-full-access` with approvals disabled, do **not** pass `sandbox_permissions` — the
  request is rejected automatically.
- Never "fix" a comment by changing the code. If a comment and the code disagree, the code wins
  and the comment is corrected, or the item is reported.
- Documentation that describes a removed feature is worse than absent documentation: it costs a
  reader a debugging session. Prefer a short accurate statement plus a pointer to the changelog
  over preserving history in place.

## References

- Repo-side rules followed here: `CodingStyle.md` (§7 function comments, §8 logging, §9 comment
  basics), `CONTRIBUTING.md`, `CHANGELOG.md` (authoritative for removals, never modified).
- `humanizer` skill (dsh) — file mode, prose-only rewriting.
- `continuous-learning` skill (dsh) — this file's format and quality bar.
