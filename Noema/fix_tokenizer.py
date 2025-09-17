#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import unicodedata
from typing import Any, Dict, List, Tuple


# Canonical DeepSeek chat markers (fullwidth vertical bars U+FF5C, block U+2581)
FULLWIDTH_BAR = "\uFF5C"  # '｜'
SPM_BLOCK = "\u2581"      # '▁'
CANON_BOS = f"<{FULLWIDTH_BAR}begin{SPM_BLOCK}of{SPM_BLOCK}sentence{FULLWIDTH_BAR}>"
CANON_EOS = f"<{FULLWIDTH_BAR}end{SPM_BLOCK}of{SPM_BLOCK}sentence{FULLWIDTH_BAR}>"
CANON_USER = f"<{FULLWIDTH_BAR}User{FULLWIDTH_BAR}>"
CANON_ASSISTANT = f"<{FULLWIDTH_BAR}Assistant{FULLWIDTH_BAR}>"

# Invisible/zero-width junk and directional marks to strip (inside markers/templates)
ZERO_WIDTHS = {
    "\uFEFF",  # BOM
    "\u200B",  # ZWSP
    "\u2060",  # WORD JOINER
    "\u200D",  # ZWJ
    "\u200C",  # ZWNJ
    "\u200E",  # LRM
    "\u200F",  # RLM
    "\uFE0E",  # Variation Selector-15
    "\uFE0F",  # Variation Selector-16
}

# Space variants to normalize to ASCII space inside markers/templates
SPACE_VARIANTS = {
    "\u00A0",  # NBSP
    "\u202F",  # NNBSP
    "\u2007",  # FIGURE SPACE
    "\u2009",  # THIN SPACE
}

# Curly quotes and dashes to normalize inside markers/templates
CURLY_TO_ASCII = {
    "\u2018": "'",  # ‘
    "\u2019": "'",  # ’
    "\u201C": '"',   # “
    "\u201D": '"',   # ”
}
DASHES_TO_ASCII_HYPHEN = {
    "\u2010",  # HYPHEN
    "\u2011",  # NON-BREAKING HYPHEN
    "\u2013",  # EN DASH
    "\u2014",  # EM DASH
}


def demojibake_and_normalize(s: str) -> str:
    # Demojibake as requested, then NFC normalize. Try latin-1 first, optionally
    # fall back to cp1252 or direct replacements for known patterns. Finally pick
    # the best candidate (fewest remnants, most canonical chars present).
    candidates: List[str] = []
    try:
        candidates.append(s.encode("latin-1", errors="ignore").decode("utf-8", errors="ignore"))
    except Exception:
        candidates.append(s)
    try:
        candidates.append(s.encode("cp1252", errors="ignore").decode("utf-8", errors="ignore"))
    except Exception:
        pass
    # Direct replacements for common mojibake triples
    direct = s.replace("ï½œ", "｜").replace("â–\x81", "▁").replace("â–", "▁")
    candidates.append(direct)

    def score(t: str) -> Tuple[int, int]:
        # Lower is better for remnants count; higher is better for canonical chars
        remnants = int("ï½œ" in t) + int("â–\x81" in t) + int("â–" in t)
        canon = t.count("｜") + t.count("▁")
        return (remnants, -canon)

    best = min(candidates, key=score)
    return unicodedata.normalize("NFC", best)


def strip_zero_width_and_variation(s: str) -> str:
    if not s:
        return s
    return "".join(ch for ch in s if ch not in ZERO_WIDTHS)


def normalize_space_dash_quotes_inside(s: str) -> str:
    if not s:
        return s
    out_chars: List[str] = []
    for ch in s:
        if ch in SPACE_VARIANTS:
            out_chars.append(" ")
        elif ch in CURLY_TO_ASCII:
            out_chars.append(CURLY_TO_ASCII[ch])
        elif ch in DASHES_TO_ASCII_HYPHEN:
            out_chars.append("-")
        else:
            out_chars.append(ch)
    return "".join(out_chars)


def standardize_line_endings(s: str) -> str:
    return s.replace("\r\n", "\n").replace("\r", "\n")


def is_angle_bracketed(s: str) -> bool:
    return isinstance(s, str) and len(s) >= 2 and s.startswith("<") and s.endswith(">")


def cleanup_marker_like_string(s: str) -> str:
    """Apply safe cleanup steps intended only for marker-like strings.

    Order: demojibake -> NFC -> strip zero-width/VS -> line endings ->
    normalize space/quotes/dashes -> trim -> canonicalize the four markers.
    """
    t = demojibake_and_normalize(s)
    t = strip_zero_width_and_variation(t)
    t = standardize_line_endings(t)
    t = normalize_space_dash_quotes_inside(t)
    t = t.strip()
    # Enforce canonical four markers if detected
    ok, canon = looks_like_one_of_four_chat_markers(t)
    if ok:
        return canon
    return t


def looks_like_one_of_four_chat_markers(s: str) -> Tuple[bool, str]:
    """Return (is_one_of_four, canonical_form_if_yes).

    Accept ASCII bars or fullwidth bars around the exact four payloads:
      begin▁of▁sentence, end▁of▁sentence, User, Assistant
    and always return the canonical fullwidth-bar variants.
    """
    if len(s) < 3:
        return False, s

    # Allow ASCII bars as stand-ins for fullwidth during detection.
    # First, strip the leading '<' and trailing '>' if present.
    if s.startswith("<") and s.endswith(">") and len(s) >= 2:
        inner = s[1:-1]
    else:
        return False, s

    # Normalize any ASCII vertical bars to fullwidth for comparison only
    inner_cmp = inner.replace("|", FULLWIDTH_BAR)

    candidates = {
        f"{FULLWIDTH_BAR}begin{SPM_BLOCK}of{SPM_BLOCK}sentence{FULLWIDTH_BAR}": CANON_BOS,
        f"{FULLWIDTH_BAR}end{SPM_BLOCK}of{SPM_BLOCK}sentence{FULLWIDTH_BAR}": CANON_EOS,
        f"{FULLWIDTH_BAR}User{FULLWIDTH_BAR}": CANON_USER,
        f"{FULLWIDTH_BAR}Assistant{FULLWIDTH_BAR}": CANON_ASSISTANT,
    }

    canon = candidates.get(inner_cmp)
    if canon is not None:
        return True, canon
    return False, s


def has_mojibake_remnants(s: str) -> bool:
    # Reject known mojibake sequences if they show up anywhere
    return ("ï½œ" in s) or ("â–\x81" in s) or ("â–" in s)


def cp_debug(s: str) -> str:
    """Return a compact representation listing code points for any non-ASCII char.

    Example: "<｜User｜>"
      -> "<｜User｜>  [｜:U+FF5C, ｜:U+FF5C]"
    """
    parts: List[str] = []
    for ch in s:
        if ord(ch) > 127:
            parts.append(f"{ch}:U+{ord(ch):04X}")
    extra = "  [" + ", ".join(parts) + "]" if parts else ""
    return f"{s}{extra}"


def load_json_text_bytes(p: Path) -> Tuple[str, bytes]:
    # Read raw bytes, then decode with utf-8-sig to drop any BOM.
    b = p.read_bytes()
    text = b.decode("utf-8-sig")
    return text, b


def write_json(path: Path, data: Any) -> None:
    # Ensure LF newlines and UTF-8 without BOM; keep non-ASCII as-is.
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def fix_markers_in_text(s: str) -> str:
    """In a free-form text (e.g., chat_template), demojibake+NFC, strip zero-width,
    standardize line endings, and canonicalize any of the four markers appearing.
    """
    t = demojibake_and_normalize(s)
    t = strip_zero_width_and_variation(t)
    t = standardize_line_endings(t)
    # Scan for <...> segments and canonicalize known markers
    out = []
    i = 0
    n = len(t)
    while i < n:
        if t[i] == '<':
            j = t.find('>', i + 1)
            if j != -1:
                seg = t[i:j+1]
                seg2 = cleanup_marker_like_string(seg)
                out.append(seg2)
                i = j + 1
                continue
        out.append(t[i])
        i += 1
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description="Repair mojibake and normalize a DeepSeek R1 Distill tokenizer.json in place.")
    ap.add_argument("--in", dest="inp", default="tokenizer.json", help="Input tokenizer.json path")
    ap.add_argument("--out", dest="out", default="tokenizer.json", help="Output tokenizer.json path (default: in-place)")
    ap.add_argument("--dry-run", dest="dry", action="store_true", help="Dry run: show changes, run self-test, do not write")
    args = ap.parse_args()

    inp = Path(args.inp)
    outp = Path(args.out)

    if not inp.exists():
        if args.dry:
            # Allow self-test without requiring a file
            print(f"warning: input file not found: {inp}. Running self-test only due to --dry-run.")
            # Execute only the self-test path
            errors: List[str] = []
            try:
                samples = [
                    "<ï½œbeginâ–ofâ–sentenceï½œ>",
                    "<ï½œendâ–ofâ–sentenceï½œ>",
                    "<ï½œUserï½œ>",
                    "<ï½œAssistantï½œ>",
                ]
                expected = [CANON_BOS, CANON_EOS, CANON_USER, CANON_ASSISTANT]
                for s, exp in zip(samples, expected):
                    out = demojibake_and_normalize(s)
                    ok, canon = looks_like_one_of_four_chat_markers(out)
                    if not ok:
                        raise AssertionError(f"self-test: detection failed for {cp_debug(s)} -> {cp_debug(out)}")
                    if canon != exp:
                        raise AssertionError(f"self-test: expected {cp_debug(exp)}, got {cp_debug(canon)}")
            except Exception as e:
                errors.append(f"self-test failed: {e}")

            if errors:
                print("Validation errors:")
                for e in errors:
                    print(f"- {e}")
                return 1
            print("Self-test passed. Dry run complete.")
            return 0
        else:
            print(f"error: input file not found: {inp}", file=sys.stderr)
            return 2

    # Load as bytes then parse JSON
    text, orig_bytes = load_json_text_bytes(inp)
    if orig_bytes.startswith(b"\xEF\xBB\xBF"):
        print("Notice: BOM detected at start of tokenizer.json; will write BOM-free UTF-8.")
    try:
        tokenizer = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"error: failed to parse JSON: {e}", file=sys.stderr)
        return 2

    changes: List[str] = []
    modified_count = 0
    # Track object->id to ensure we never change ids of surviving tokens
    id_by_obj: Dict[int, Any] = {}
    surviving_objs_after: List[int] = []

    # 1) Process added_tokens[*].content
    added_tokens = tokenizer.get("added_tokens")
    if isinstance(added_tokens, list):
        # Capture IDs before
        for idx, tok in enumerate(added_tokens):
            if isinstance(tok, dict):
                id_by_obj[id(tok)] = tok.get("id")

        for idx, tok in enumerate(added_tokens):
            if not isinstance(tok, dict):
                continue
            if "content" not in tok or not isinstance(tok["content"], str):
                continue
            before = tok["content"]
            # Demojibake + NFC first
            mid = demojibake_and_normalize(before)
            # If looks angle-bracketed, be stricter and cleanup further
            if is_angle_bracketed(mid):
                after = cleanup_marker_like_string(mid)
            else:
                after = mid

            if after != before:
                modified_count += 1
                changes.append(
                    f"added_tokens[{idx}] id={tok.get('id')}:\n  before: {cp_debug(before)}\n  after : {cp_debug(after)}"
                )
                tok["content"] = after

            # Flags sanity
            if after in (CANON_BOS, CANON_EOS):
                tok["special"] = True
            # Keep 'normalized': false to avoid tokenizer re-normalization of bars
            tok["normalized"] = False
        # Dedupe by content (keep first occurrence)
        seen_content: Dict[str, int] = {}
        dedup_removed: List[Tuple[int, Any, str]] = []  # (index, id, content)
        new_list: List[Dict[str, Any]] = []
        for idx, tok in enumerate(added_tokens):
            if not isinstance(tok, dict):
                new_list.append(tok)
                continue
            c = tok.get("content")
            if isinstance(c, str):
                if c in seen_content:
                    dedup_removed.append((idx, tok.get("id"), c))
                    continue  # drop duplicate
                seen_content[c] = tok.get("id")
            new_list.append(tok)
        if dedup_removed:
            changes.append("Deduped added_tokens by content; removed duplicates:")
            for idx, tid, c in dedup_removed:
                changes.append(f"  removed added_tokens[{idx}] id={tid} content={cp_debug(c)}")
            added_tokens[:] = new_list
        # Capture surviving object ids to check that their 'id' fields didn't change
        for tok in added_tokens:
            if isinstance(tok, dict):
                surviving_objs_after.append(id(tok))

    # 2) Process special_tokens if a dict-like mapping exists (apply to string values)
    # In HF tokenizer.json, special_tokens is typically a list of token dicts, but
    # some variants may include a mapping elsewhere. We handle both.
    st = tokenizer.get("special_tokens")
    if isinstance(st, dict):
        for k, v in list(st.items()):
            if isinstance(v, str):
                before = v
                mid = demojibake_and_normalize(before)
                after = cleanup_marker_like_string(mid) if is_angle_bracketed(mid) else mid
                # If this maps bos/eos explicitly, ensure canonical
                if k in ("bos_token", "eos_token"):
                    ok, canon = looks_like_one_of_four_chat_markers(after)
                    if ok:
                        after = canon
                if after != before:
                    modified_count += 1
                    changes.append(
                        f"special_tokens[{k!r}]:\n  before: {cp_debug(before)}\n  after : {cp_debug(after)}"
                    )
                    st[k] = after
    elif isinstance(st, list):
        for idx, tok in enumerate(st):
            if not isinstance(tok, dict):
                continue
            if "content" in tok and isinstance(tok["content"], str):
                before = tok["content"]
                mid = demojibake_and_normalize(before)
                after = cleanup_marker_like_string(mid) if is_angle_bracketed(mid) else mid
                if after != before:
                    modified_count += 1
                    changes.append(
                        f"special_tokens[{idx}] id={tok.get('id')}:\n  before: {cp_debug(before)}\n  after : {cp_debug(after)}"
                    )
                    tok["content"] = after

    # 3) Validate: No mojibake remnants remain in any processed content
    def scan_for_remnants() -> List[str]:
        bad: List[str] = []
        if isinstance(added_tokens, list):
            for idx, tok in enumerate(added_tokens):
                if isinstance(tok, dict):
                    c = tok.get("content")
                    if isinstance(c, str) and has_mojibake_remnants(c):
                        bad.append(f"added_tokens[{idx}] id={tok.get('id')} content has mojibake remnants: {cp_debug(c)}")
                    # Within marker-like strings ensure zero-widths/VS are gone
                    if isinstance(c, str) and is_angle_bracketed(c):
                        for ch in c:
                            if ch in ZERO_WIDTHS:
                                bad.append(f"added_tokens[{idx}] id={tok.get('id')} contains zero-width/VS: {cp_debug(c)}")
        if isinstance(st, dict):
            for k, v in st.items():
                if isinstance(v, str) and has_mojibake_remnants(v):
                    bad.append(f"special_tokens[{k!r}] has mojibake remnants: {cp_debug(v)}")
                if isinstance(v, str) and is_angle_bracketed(v):
                    for ch in v:
                        if ch in ZERO_WIDTHS:
                            bad.append(f"special_tokens[{k!r}] contains zero-width/VS: {cp_debug(v)}")
        elif isinstance(st, list):
            for idx, tok in enumerate(st):
                if isinstance(tok, dict):
                    c = tok.get("content")
                    if isinstance(c, str) and has_mojibake_remnants(c):
                        bad.append(f"special_tokens[{idx}] id={tok.get('id')} has mojibake remnants: {cp_debug(c)}")
                    if isinstance(c, str) and is_angle_bracketed(c):
                        for ch in c:
                            if ch in ZERO_WIDTHS:
                                bad.append(f"special_tokens[{idx}] id={tok.get('id')} contains zero-width/VS: {cp_debug(c)}")
        return bad

    # 4) Validate: added_tokens IDs preserved for surviving tokens (we may dedupe)
    id_errors: List[str] = []
    if isinstance(added_tokens, list):
        for tok in added_tokens:
            if isinstance(tok, dict):
                oid = id(tok)
                if oid in id_by_obj:
                    before_id = id_by_obj[oid]
                    after_id = tok.get("id")
                    if before_id != after_id:
                        id_errors.append(f"token id changed for content {cp_debug(tok.get('content',''))}: before id={before_id!r}, after id={after_id!r}")
    if id_errors:
        print("error: added_tokens IDs changed (should be preserved)", file=sys.stderr)
        for e in id_errors:
            print("  - "+e, file=sys.stderr)
        return 1

    # 5) Validate: bos/eos tokens in special_tokens_map.json if present; else try to infer
    errors: List[str] = []
    spmap_path = inp.with_name("special_tokens_map.json")
    bos_expected = CANON_BOS
    eos_expected = CANON_EOS

    def validate_bos_eos_value(name: str, value: str) -> None:
        if name == "bos_token" and value != bos_expected:
            errors.append(f"bos_token mismatch: got {cp_debug(value)} expected {cp_debug(bos_expected)}")
        if name == "eos_token" and value != eos_expected:
            errors.append(f"eos_token mismatch: got {cp_debug(value)} expected {cp_debug(eos_expected)}")

    if spmap_path.exists():
        try:
            st_map_text = spmap_path.read_text(encoding="utf-8-sig")
            st_map = json.loads(st_map_text)
            for key in ("bos_token", "eos_token"):
                if key in st_map and isinstance(st_map[key], str):
                    # Apply demojibake+NFC for validation purposes only
                    orig_val = st_map[key]
                    val = cleanup_marker_like_string(orig_val)
                    # Enforce canonical for bos/eos explicitly
                    ok, canon = looks_like_one_of_four_chat_markers(val)
                    if ok:
                        val = canon
                    if val != orig_val:
                        changes.append(
                            f"special_tokens_map.json {key}:\n  before: {cp_debug(orig_val)}\n  after : {cp_debug(val)}"
                        )
                        st_map[key] = val
                    validate_bos_eos_value(key, val)
            # Optionally write back if not dry
            if not args.dry:
                # backup
                src_text = Path(spmap_path).read_text(encoding="utf-8-sig")
                Path(str(spmap_path)+".bak").write_text(src_text, encoding="utf-8", newline="\n")
                # write
                Path(spmap_path).write_text(json.dumps(st_map, ensure_ascii=False, indent=2)+"\n", encoding="utf-8", newline="\n")
        except Exception as e:
            errors.append(f"failed to read special_tokens_map.json: {e}")
    else:
        # Try to infer from tokenizer.json special_tokens list or added_tokens
        found_bos = False
        found_eos = False
        # If tokenizer.json has a dict-like special_tokens with explicit bos/eos
        if isinstance(st, dict):
            if isinstance(st.get("bos_token"), str):
                validate_bos_eos_value("bos_token", demojibake_and_normalize(st["bos_token"]))
                found_bos = st.get("bos_token") == bos_expected
            if isinstance(st.get("eos_token"), str):
                validate_bos_eos_value("eos_token", demojibake_and_normalize(st["eos_token"]))
                found_eos = st.get("eos_token") == eos_expected
        # Check special_tokens list
        if isinstance(st, list):
            for tok in st:
                if not isinstance(tok, dict):
                    continue
                c = tok.get("content")
                if c == bos_expected:
                    found_bos = True
                if c == eos_expected:
                    found_eos = True
        # Fallback: scan added tokens
        if not found_bos or not found_eos:
            if isinstance(added_tokens, list):
                for tok in added_tokens:
                    if not isinstance(tok, dict):
                        continue
                    c = tok.get("content")
                    if c == bos_expected:
                        found_bos = True
                    if c == eos_expected:
                        found_eos = True
        if not found_bos:
            errors.append(f"could not find canonical bos_token {cp_debug(bos_expected)} in tokenizer.json")
        if not found_eos:
            errors.append(f"could not find canonical eos_token {cp_debug(eos_expected)} in tokenizer.json")

    # 6) Check remnants after all transforms
    remnants = scan_for_remnants()
    errors.extend(remnants)

    # 6.1) Validate flags: BOS/EOS must be special=true; tokens with fullwidth bar should have normalized=false
    if isinstance(added_tokens, list):
        for idx, tok in enumerate(added_tokens):
            if not isinstance(tok, dict):
                continue
            c = tok.get("content")
            if not isinstance(c, str):
                continue
            if c in (CANON_BOS, CANON_EOS):
                if not bool(tok.get("special", False)):
                    errors.append(f"added_tokens[{idx}] id={tok.get('id')}: BOS/EOS must have special=true")
            if "｜" in c or "▁" in c:
                if tok.get("normalized", None) not in (False,):
                    errors.append(f"added_tokens[{idx}] id={tok.get('id')}: should set normalized=false for fullwidth markers")

    # 6.2) Vocab collisions: ensure markers are not present in vocab.json with conflicting IDs
    def load_vocab_map() -> Dict[str, int]:
        vocab: Dict[str, int] = {}
        vpath = inp.with_name("vocab.json")
        try:
            if vpath.exists():
                vt = vpath.read_text(encoding="utf-8-sig")
                vocab = json.loads(vt)
            else:
                # Try tokenizer.json embedded vocab
                model = tokenizer.get("model", {}) if isinstance(tokenizer, dict) else {}
                if isinstance(model, dict) and isinstance(model.get("vocab"), dict):
                    vocab = model["vocab"]
        except Exception:
            pass
        return vocab

    vocab_map = load_vocab_map()
    if vocab_map:
        # Map marker content -> added_tokens id
        marker_ids: Dict[str, Any] = {}
        if isinstance(added_tokens, list):
            for tok in added_tokens:
                if isinstance(tok, dict):
                    c = tok.get("content")
                    if c in (CANON_BOS, CANON_EOS, CANON_USER, CANON_ASSISTANT):
                        marker_ids[c] = tok.get("id")
        for m, mid in marker_ids.items():
            if m in vocab_map and vocab_map[m] != mid:
                errors.append(
                    f"vocab.json collision for marker {cp_debug(m)}: vocab id={vocab_map[m]} != added_token id={mid}"
                )

    # 6.3) Verify regex payloads (pre_tokenizer patterns) for sanity
    def verify_regex_payloads(original_text: str, obj: Any) -> List[str]:
        issues: List[str] = []
        def walk(x: Any):
            if isinstance(x, dict):
                # If looks like a Regex node or contains a pattern, validate
                if "pattern" in x and isinstance(x["pattern"], str):
                    pat = x["pattern"]
                    if has_mojibake_remnants(pat):
                        issues.append(f"regex pattern has mojibake remnants: {cp_debug(pat)}")
                    # Verify that JSON encoding would escape backslashes for constructs like \p{L}
                    if "\\p{" in pat:
                        enc = json.dumps(pat)
                        if "\\\\p{" not in enc:  # expect double-escaped in JSON text
                            issues.append(f"regex pattern may lose escapes when serialized: {pat}")
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        walk(obj.get("pre_tokenizer", obj))
        return issues

    errors.extend(verify_regex_payloads(text, tokenizer))

    # 7) Self-test when --dry-run is provided
    if args.dry:
        try:
            # Mojibake inputs
            samples = [
                "<ï½œbeginâ–ofâ–sentenceï½œ>",
                "<ï½œendâ–ofâ–sentenceï½œ>",
                "<ï½œUserï½œ>",
                "<ï½œAssistantï½œ>",
            ]
            expected = [CANON_BOS, CANON_EOS, CANON_USER, CANON_ASSISTANT]
            for s, exp in zip(samples, expected):
                out = demojibake_and_normalize(s)
                ok, canon = looks_like_one_of_four_chat_markers(out)
                if not ok:
                    raise AssertionError(f"self-test: detection failed for {cp_debug(s)} -> {cp_debug(out)}")
                if canon != exp:
                    raise AssertionError(f"self-test: expected {cp_debug(exp)}, got {cp_debug(canon)}")
        except Exception as e:
            errors.append(f"self-test failed: {e}")

    # Process tokenizer_config.json chat_template for consistency
    tcfg_path = inp.with_name("tokenizer_config.json")
    if tcfg_path.exists():
        try:
            cfg_text = tcfg_path.read_text(encoding="utf-8-sig")
            cfg = json.loads(cfg_text)
            if isinstance(cfg, dict) and isinstance(cfg.get("chat_template"), str):
                before_tpl = cfg["chat_template"]
                after_tpl = fix_markers_in_text(before_tpl)
                if after_tpl != before_tpl:
                    changes.append("tokenizer_config.json chat_template updated to normalize markers and line endings")
                    if not args.dry:
                        # backup and write
                        Path(str(tcfg_path)+".bak").write_text(cfg_text, encoding="utf-8", newline="\n")
                        cfg["chat_template"] = after_tpl
                        tcfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2)+"\n", encoding="utf-8", newline="\n")
        except Exception as e:
            errors.append(f"failed to process tokenizer_config.json: {e}")

    # Print change summary
    print(f"Scanned file: {inp}")
    if modified_count == 0:
        print("No content changes needed.")
    else:
        print(f"Modified {modified_count} token(s). Details:")
        for line in changes:
            print(line)

    if errors:
        print("\nValidation errors:")
        for e in errors:
            print(f"- {e}")
        return 1

    # Write outputs unless dry-run
    if args.dry:
        print("\nDry run: no files written. (Self-test executed.)")
        return 0

    # Create UTF-8 (no BOM) backup of the original input
    try:
        backup_path = outp if inp == outp else inp
        backup_bare = Path(str(backup_path))
        # Read source text via utf-8-sig to drop BOM, then write as utf-8
        src_text = backup_bare.read_text(encoding="utf-8-sig")
        (backup_bare.with_name(backup_bare.name + ".bak")).write_text(src_text, encoding="utf-8", newline="\n")
    except Exception as e:
        print(f"error: failed to write backup: {e}", file=sys.stderr)
        return 1

    # Write fixed tokenizer.json
    try:
        write_json(outp, tokenizer)
        print(f"Wrote fixed file to {outp}")
        print(f"Backup saved to {outp}.bak" if inp == outp else f"Backup saved to {inp}.bak")
    except Exception as e:
        print(f"error: failed to write output: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
